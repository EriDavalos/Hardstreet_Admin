#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

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

  // Manda a Dart qué se tocó en el panel: "agenda" (con id) o "new".
  void SendEventWidgetTap(const std::string& action, int id);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Widget de escritorio: la app le empuja los próximos eventos.
  std::unique_ptr<EventWidget> event_widget_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      events_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
