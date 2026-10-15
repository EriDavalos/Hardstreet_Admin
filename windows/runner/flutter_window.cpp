#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

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
  // El panel de eventos es una ventana propia: se destruye antes que la app.
  event_widget_.reset();
  events_channel_.reset();
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
        result->NotImplemented();
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
