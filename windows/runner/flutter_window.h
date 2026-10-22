#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

// windows.h primero: shellapi.h usa sus macros (EXTERN_C, DECLSPEC_IMPORT).
#include <windows.h>

#include <shellapi.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "event_widget.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Panel flotante "Próximos eventos" (widget de escritorio) + su canal.
  void SetUpEventsChannel();

  // Canal `hardstreet/window`: pantalla completa REAL de la ventana (el
  // reproductor de vídeo la pide; WebView2 no puede agrandar la ventana).
  void SetUpFullscreenChannel();

  // Manda a Dart qué se tocó en el panel: "agenda" (con id) o "new".
  void SendEventWidgetTap(const std::string& action, int id);

  // ---- Bandeja del sistema (avisos con la ventana cerrada) ----
  //
  // Cerrar la ventana NO termina la app: se oculta en la bandeja y sigue
  // consultando avisos (recordatorios de eventos y avisos del paquete) para
  // que el toast salga aunque el panel no esté abierto. Se sale de verdad con
  // «Salir» en el menú del icono de la bandeja.
  bool HideToTray();          // false si el sistema no aceptó el icono
  void ShowFromTray();        // vuelve a mostrar la ventana
  void ShowTrayMenu();        // menú Abrir / Salir
  void QuitFromTray();        // sale de la app de verdad
  void RemoveTrayIcon();
  void ShowBackgroundHint();  // avisa UNA vez que sigue en segundo plano

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Widget de escritorio: la app le empuja los próximos eventos.
  std::unique_ptr<EventWidget> event_widget_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      events_channel_;

  // Pantalla completa de la ventana (estado para poder volver exactamente al
  // estilo y al tamaño anteriores).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      fullscreen_channel_;
  bool is_fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  RECT saved_rect_{};

  // Icono de la bandeja (NULL hasta que el usuario cierra la ventana).
  NOTIFYICONDATAW tray_icon_{};
  bool tray_icon_added_ = false;
  bool tray_hint_shown_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
