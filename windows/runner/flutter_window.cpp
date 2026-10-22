#include "flutter_window.h"

#include <cwchar>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// ---- Bandeja del sistema ----
//
// Mensaje con el que el icono avisa de los clics (bandeja -> ventana).
constexpr UINT kTrayCallbackMessage = WM_APP + 42;
constexpr UINT kTrayMenuOpen = 1;
constexpr UINT kTrayMenuExit = 2;
constexpr UINT kTrayIconId = 1;

// std::string (UTF-8, lo que manda el codec de Flutter) a std::wstring.
std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                       static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), size);
  return out;
}

// Valor de una clave del mapa de argumentos (nullptr si no viene).
const flutter::EncodableValue* ArgOf(const flutter::EncodableMap& map,
                                     const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringOf(const flutter::EncodableValue* value) {
  if (value == nullptr) return std::string();
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

bool BoolOf(const flutter::EncodableValue* value, bool fallback) {
  if (value == nullptr) return fallback;
  const auto* flag = std::get_if<bool>(value);
  return flag == nullptr ? fallback : *flag;
}

// Entero de 64 bits del mapa de argumentos (lo usa el instante del evento, que
// en ms no cabe en 32 bits; 0 si no viene).
int64_t Int64Of(const flutter::EncodableValue* value) {
  if (value == nullptr) return 0;
  if (const auto* largo = std::get_if<int64_t>(value)) return *largo;
  if (const auto* corto = std::get_if<int>(value)) return *corto;
  return 0;
}

// Entero del mapa de argumentos (Dart manda int64; 0 si no viene).
int IntOf(const flutter::EncodableValue* value) {
  return static_cast<int>(Int64Of(value));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetUpEventsChannel();
  SetUpFullscreenChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // El icono de la bandeja se va con la ventana (si se queda, Windows deja un
  // icono fantasma hasta que se pasa el ratón por encima).
  RemoveTrayIcon();
  // El panel de eventos es una ventana propia: se destruye antes que la app.
  event_widget_.reset();
  events_channel_.reset();
  fullscreen_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// Canal `hardstreet/events_widget`: el widget de "próximos eventos" del
// escritorio. La app manda los eventos YA FORMATEADOS y la bandera `dark` (modo
// de la app, claro/oscuro); aquí solo se guardan y se dibujan (no hay que tocar
// red ni credenciales).
void FlutterWindow::SetUpEventsChannel() {
  event_widget_ = std::make_unique<EventWidget>(GetHandle());
  events_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "hardstreet/events_widget",
          &flutter::StandardMethodCodec::GetInstance());
  // El panel solo dibuja: al hacer clic AVISA a la app (Dart navega).
  // Una fila -> detalle de esa agenda; el botón "+" -> alta de evento.
  event_widget_->on_event_tap = [this](int id) {
    SendEventWidgetTap("agenda", id);
  };
  event_widget_->on_add_tap = [this]() { SendEventWidgetTap("new", 0); };

  events_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "update") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr || event_widget_ == nullptr) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          const std::wstring header =
              WideFromUtf8(StringOf(ArgOf(*args, "header")));
          const bool visible = BoolOf(ArgOf(*args, "visible"), false);
          // Modo de la APP (claro/oscuro): el panel se pinta como ella.
          const bool dark = BoolOf(ArgOf(*args, "dark"), false);
          // El rol puede crear agendas: solo entonces el panel ofrece el "+".
          const bool can_add = BoolOf(ArgOf(*args, "canAdd"), false);
          std::vector<EventWidget::Event> events;
          const auto* events_value = ArgOf(*args, "events");
          const auto* list = events_value == nullptr
                                 ? nullptr
                                 : std::get_if<flutter::EncodableList>(events_value);
          if (list != nullptr) {
            for (const auto& item : *list) {
              const auto* map = std::get_if<flutter::EncodableMap>(&item);
              if (map == nullptr) continue;
              EventWidget::Event event;
              event.id = IntOf(ArgOf(*map, "id"));
              event.service = IntOf(ArgOf(*map, "service"));
              event.title = WideFromUtf8(StringOf(ArgOf(*map, "title")));
              event.subtitle = WideFromUtf8(StringOf(ArgOf(*map, "subtitle")));
              event.when = WideFromUtf8(StringOf(ArgOf(*map, "when")));
              event.day = WideFromUtf8(StringOf(ArgOf(*map, "day")));
              event.time = WideFromUtf8(StringOf(ArgOf(*map, "time")));
              event.show_day = BoolOf(ArgOf(*map, "showDay"), false) &&
                               !event.day.empty();
              // El instante permite al panel RECALCULAR el rótulo del día con
              // la hora actual (ver EventWidget::RefreshNow).
              event.at_ms = Int64Of(ArgOf(*map, "at"));
              events.push_back(std::move(event));
            }
          }
          event_widget_->Update(header, events, visible, dark, can_add);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "isVisible") {
          const bool visible = event_widget_ != nullptr && event_widget_->visible();
          result->Success(flutter::EncodableValue(visible));
          return;
        }
        // La app pide volver a mostrarse (p. ej. al tocar una notificación
        // con la ventana cerrada en la bandeja).
        if (method == "showWindow") {
          ShowFromTray();
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
}

// Canal `hardstreet/window`: pantalla completa REAL de la ventana.
//
// El visor de vídeo vive dentro de un WebView2 y ahí `requestFullscreen` no
// puede agrandar la VENTANA (el botón solo escondía la barra del panel). Aquí
// se guarda el estilo y el tamaño actuales y la ventana se pone sin bordes
// sobre el monitor; al salir se restaura exactamente como estaba.
void FlutterWindow::SetUpFullscreenChannel() {
  fullscreen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "hardstreet/window",
          &flutter::StandardMethodCodec::GetInstance());
  fullscreen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setFullscreen") {
          result->NotImplemented();
          return;
        }
        const auto* flag = std::get_if<bool>(call.arguments());
        const bool enable = flag != nullptr && *flag;
        HWND hwnd = GetHandle();
        if (hwnd == nullptr) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (enable == is_fullscreen_) {
          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }
        if (enable) {
          saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
          GetWindowRect(hwnd, &saved_rect_);
          MONITORINFO monitor = {};
          monitor.cbSize = sizeof(MONITORINFO);
          if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                             &monitor)) {
            const RECT& area = monitor.rcMonitor;
            SetWindowLongPtr(hwnd, GWL_STYLE,
                             (saved_style_ &
                              ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX |
                                WS_MAXIMIZEBOX | WS_SYSMENU)) |
                                 WS_POPUP | WS_VISIBLE);
            SetWindowPos(hwnd, HWND_TOP, area.left, area.top,
                         area.right - area.left, area.bottom - area.top,
                         SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
            is_fullscreen_ = true;
          }
        } else {
          SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
          SetWindowPos(hwnd, nullptr, saved_rect_.left, saved_rect_.top,
                       saved_rect_.right - saved_rect_.left,
                       saved_rect_.bottom - saved_rect_.top,
                       SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
          is_fullscreen_ = false;
        }
        result->Success(flutter::EncodableValue(is_fullscreen_));
      });
}

// Avisa a Dart QUÉ se tocó en el panel (nativo -> Dart). Dart ya tiene
// registrado el handler de `onWidgetTap` en el mismo canal; así el panel no
// necesita saber nada de navegación ni de sesión.
void FlutterWindow::SendEventWidgetTap(const std::string& action, int id) {
  if (!events_channel_) return;
  // La app tiene que VERSE: el panel está siempre visible y se puede tocar con
  // la ventana minimizada; sin esto el detalle se abriría "por detrás".
  if (IsIconic(GetHandle())) ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
  flutter::EncodableMap args;
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  args[flutter::EncodableValue("id")] =
      flutter::EncodableValue(static_cast<int64_t>(id));
  events_channel_->InvokeMethod(
      "onWidgetTap",
      std::make_unique<flutter::EncodableValue>(args));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Clics en el icono de la bandeja: abrir la ventana o su menú.
  if (message == kTrayCallbackMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowFromTray();
        return 0;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        return 0;
      default:
        return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      // Cerrar la ventana NO apaga la app: queda en la bandeja consultando
      // avisos (recordatorios y avisos del paquete) y avisa con el toast del
      // sistema. Si la bandeja no está disponible, se cierra como siempre.
      if (HideToTray()) return 0;
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// ===================== Bandeja del sistema =====================

bool FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return false;

  if (!tray_icon_added_) {
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(NOTIFYICONDATAW);
    icon.hWnd = hwnd;
    icon.uID = kTrayIconId;
    icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    icon.uCallbackMessage = kTrayCallbackMessage;
    icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    lstrcpynW(icon.szTip, L"Hardstreet Platform - avisos en segundo plano",
              ARRAYSIZE(icon.szTip));
    if (!Shell_NotifyIconW(NIM_ADD, &icon)) {
      // Sin bandeja (explorador caído, sesión rara): se cierra normal antes
      // que desaparecer sin forma de volver.
      return false;
    }
    tray_icon_ = icon;
    tray_icon_added_ = true;
  }

  ShowWindow(hwnd, SW_HIDE);
  ShowBackgroundHint();
  return true;
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kTrayMenuOpen, L"Abrir Hardstreet");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Salir");

  POINT cursor{};
  GetCursorPos(&cursor);
  // Regla de la bandeja: sin traer la ventana al frente el menú no se cierra
  // al hacer clic fuera.
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, hwnd,
      nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (command == kTrayMenuOpen) ShowFromTray();
  if (command == kTrayMenuExit) QuitFromTray();
}

void FlutterWindow::QuitFromTray() {
  RemoveTrayIcon();
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    // WM_DESTROY -> Win32Window::MessageHandler cierra el bucle de mensajes.
    DestroyWindow(hwnd);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowBackgroundHint() {
  if (tray_hint_shown_ || !tray_icon_added_) return;
  tray_hint_shown_ = true;

  NOTIFYICONDATAW hint = tray_icon_;
  hint.uFlags = NIF_INFO;
  hint.dwInfoFlags = NIIF_INFO;
  lstrcpynW(hint.szInfoTitle, L"Hardstreet sigue activo",
            ARRAYSIZE(hint.szInfoTitle));
  lstrcpynW(hint.szInfo,
            L"Cerraste la ventana, pero seguimos en la bandeja para avisarte "
            L"de tus eventos. Clic derecho en el icono > Salir.",
            ARRAYSIZE(hint.szInfo));
  Shell_NotifyIconW(NIM_MODIFY, &hint);
}
