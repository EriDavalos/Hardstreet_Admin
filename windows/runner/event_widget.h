#ifndef RUNNER_EVENT_WIDGET_H_
#define RUNNER_EVENT_WIDGET_H_

#include <windows.h>

#include <functional>
#include <string>
#include <utility>
#include <vector>

// Panel flotante "Próximos eventos" del escritorio de Windows.
//
// Es la versión Windows del widget de inicio de Android: una ventanita SIN
// bordes, SIEMPRE visible por encima de las demás, anclada a la esquina
// inferior derecha del área de trabajo. La app (que tiene la sesión y los
// datos) le EMPUJA los eventos ya formateados por el MethodChannel
// `hardstreet/events_widget`; el panel solo los dibuja con GDI.
//
// Sigue el MODO DE LA APP: la bandera `dark` que llega en cada update elige
// entre la paleta clara y la oscura. Ambas son EXACTAMENTE los colores del
// tema de la app (lib/theme.dart): tarjeta = cardColor, textos = onSurface /
// onSurfaceVariant, acento = primary y líneas = dividerColor.
//
// Muestra TODA la agenda próxima agrupada por día y, si no cabe en el panel,
// se desplaza con la rueda del ratón (hay una barra fina a la derecha).
//
// Interacción:
//  - clic en un evento  -> avisa a la app (callback) para abrir SU detalle;
//  - clic en el botón "+" (solo si el rol puede crear agendas) -> alta;
//  - clic en el resto   -> trae la ventana principal al frente;
//  - se puede ARRASTRAR (mantener y mover) para colocarlo donde quieras.
class EventWidget {
 public:
  struct Event {
    // Id de la agenda: es lo que la app abre al hacer clic en la fila (0 si el
    // evento viene de un aviso y no hay agenda que abrir).
    int id = 0;
    // Id del SERVICIO de la agenda: elige el color de la tarjeta (cada evento
    // se tiñe con el color de su servicio, como en el calendario de la app).
    int service = 0;
    std::wstring title;
    std::wstring subtitle;
    std::wstring when;  // fecha y hora ("25 oct · 17:30")
    // Rótulo del DÍA ("HOY · 16 OCT"). Se pinta SOLO cuando [show_day] es
    // true: es el primer evento de esa fecha, así varios eventos del mismo día
    // quedan debajo de un solo rótulo.
    std::wstring day;
    std::wstring time;  // hora sola ("17:30"), para filas con rótulo.
    bool show_day = false;
    // Instante del evento (epoch en ms, hora local). El panel lo usa para
    // RECALCULAR el rótulo del día con la hora actual y descartar lo que ya
    // pasó: el rótulo que empuja la app envejece y un "HOY" de ayer sigue
    // diciendo "HOY" si la app no vuelve a empujar. 0 = sin instante (carga
    // vieja): se respeta tal cual lo que mandó la app.
    long long at_ms = 0;
  };

  // Paleta del panel: siempre la de la app (claro u oscuro). Pública porque los
  // dos juegos de colores viven en el .cpp; el panel se pinta con 
  // EventWidget::Colors().
  struct Palette {
    COLORREF card;       // fondo de la tarjeta (cardColor)
    COLORREF border;     // borde de la tarjeta (dividerColor)
    COLORREF brand;      // acento de la marca (encabezado, rótulo de día y "+")
    COLORREF accent;     // hora del evento
    COLORREF text;       // titular (onSurface)
    COLORREF muted;      // cliente · servicio (onSurfaceVariant)
    COLORREF divider;    // línea bajo el encabezado
    COLORREF badge_bg;   // pastilla del contador
    COLORREF add_bg;      // pastilla del botón "Agregar agenda"
    COLORREF separator;  // línea entre eventos
  };

  // Avisos hacia la app. Los conecta FlutterWindow (son los que hacen que un
  // clic abra el detalle de la agenda o el alta de evento).
  std::function<void(int)> on_event_tap;  // recibe el id de la agenda
  std::function<void()> on_add_tap;

  explicit EventWidget(HWND owner);
  ~EventWidget();

  EventWidget(const EventWidget&) = delete;
  EventWidget& operator=(const EventWidget&) = delete;

  // Guarda los eventos y muestra (visible = true) u oculta el panel.
  // [dark]    = modo de la APP (claro/oscuro).
  // [can_add] = el rol puede crear agendas: se dibuja el botón "+".
  void Update(const std::wstring& header, const std::vector<Event>& events,
              bool visible, bool dark, bool can_add);
  void Hide();
  bool visible() const { return hwnd_ != nullptr; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  const Palette& Colors() const;
  // Recalcula [events_] a partir de [all_events_] con la hora ACTUAL: rótulos
  // de día al día y sin lo que ya pasó. La llama cada empujón de la app y el
  // temporizador propio del panel (ver kRefreshTimerId en el .cpp).
  void RefreshNow();
  // Lo que hace el temporizador propio del panel: recalcula y repinta.
  void RefreshByTimer();
  void EnsureWindow();
  void DestroyPanel();
  void PlaceAtCorner();
  void Paint(HDC dc);
  void FocusOwner();
  void ScrollBy(int delta);
  int ContentHeight() const;   // alto de TODA la lista
  int MaxViewHeight() const;   // tope del listado visible (según la pantalla)
  int ViewHeight() const;      // listado visible (recortado al tope)
  int PanelHeight() const;     // tarjeta completa
  int MaxScroll() const;
  std::wstring BadgeText() const;
  // Id de la agenda bajo [p] (punto en coordenadas de cliente), o 0.
  int EventAt(POINT p) const;

  HWND owner_;
  HWND hwnd_ = nullptr;

  std::wstring header_ = L"Pr\u00f3ximos eventos";
  // Lo que empujó la app (sin filtrar): es la fuente de [events_], que es lo
  // que de verdad se dibuja y se vuelve a calcular con la hora actual.
  std::vector<Event> all_events_;
  std::vector<Event> events_;
  bool dark_ = false;     // modo de la APP (no el del sistema)
  bool can_add_ = false;  // ¿se ofrece el botón "Agregar agenda"?
  int scroll_ = 0;        // desplazamiento del listado, en píxeles

  // Zonas de clic, calculadas en el último Paint (coordenadas de cliente).
  std::vector<std::pair<int, int>> row_hits_;  // una por evento [top, bottom)
  RECT add_box_ = {0, 0, 0, 0};                // botón "+" (vacío = oculto)

  HFONT header_font_ = nullptr;
  HFONT badge_font_ = nullptr;
  HFONT title_font_ = nullptr;
  HFONT time_font_ = nullptr;
  HFONT body_font_ = nullptr;
  HFONT day_font_ = nullptr;  // rótulo de fecha (pequeño y en mayúsculas)

  // Arrastre del panel.
  bool dragging_ = false;
  bool moved_ = false;
  POINT drag_origin_{0, 0};
  RECT drag_start_{0, 0, 0, 0};
};

#endif  // RUNNER_EVENT_WIDGET_H_
