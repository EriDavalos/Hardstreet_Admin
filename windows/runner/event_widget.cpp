#include "event_widget.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace {

// Posición del cursor dentro de la ventana (lparam de los mensajes de ratón).
POINT PointFromLParam(LPARAM lparam) {
  POINT p;
  p.x = static_cast<short>(LOWORD(lparam));
  p.y = static_cast<short>(HIWORD(lparam));
  return p;
}

constexpr wchar_t kClassName[] = L"HardstreetEventWidget";
constexpr int kWidth = 376;    // ancho del panel
constexpr int kMargin = 18;    // separación con el borde del área de trabajo
constexpr int kPadding = 16;   // relleno interior
constexpr int kHeaderH = 40;   // encabezado (título + contador) más GRANDE
constexpr int kDividerGap = 8;
constexpr int kContentGap = 10;  // aire entre el separador y el listado
constexpr int kMaxViewH = 640;   // tope del listado visible (el resto se rueda)
constexpr int kSepH = 8;         // banda donde va la línea entre eventos
constexpr int kDayH = 24;        // rótulo del día
constexpr int kTitleH = 25;      // titular + hora
constexpr int kSubH = 19;        // cliente · servicio
constexpr int kItemGap = 10;     // aire bajo cada evento
constexpr int kEmptyH = 22;
constexpr int kScrollStep = 56;  // una muesca de la rueda
constexpr int kAddSize = 34;    // lado del botón "+" (Agregar agenda)
constexpr int kAddGap = 10;     // aire entre el botón, el contador y el título
// Tarjeta de cada evento: fondo tenue del color del servicio ("disimulado pero
// que se entienda a simple vista", como el calendario de Agendas) + una barra
// de acento a la izquierda.
constexpr int kRowRadius = 12;
constexpr int kRowInset = 5;   // aire entre la tarjeta y los textos
constexpr int kBarW = 3;       // grosor de la barra de servicio

// Colores por servicio: la MISMA paleta del calendario de la app
// (lib/pages/agendas_page.dart, `_agendaPalette`). Cada evento se tiñe con el
// color de su servicio, así dos eventos distintos se distinguen de un vistazo.
constexpr COLORREF kServiceColors[8] = {
    RGB(0x8B, 0x5C, 0xF6),  // violeta
    RGB(0x10, 0xB9, 0x81),  // esmeralda
    RGB(0xF5, 0x9E, 0x0B),  // ámbar
    RGB(0x3B, 0x82, 0xF6),  // azul
    RGB(0xEF, 0x44, 0x44),  // rojo
    RGB(0x14, 0xB8, 0xA6),  // turquesa
    RGB(0xEC, 0x48, 0x99),  // rosa
    RGB(0x63, 0x66, 0xF1),  // índigo
};

COLORREF ServiceColor(int service) {
  return kServiceColors[(service < 0 ? -service : service) % 8];
}

// Mezcla lineal de [a] sobre [b] con peso [t] (0 = b, 1 = a). Sirve para teñir
// el fondo de una fila con el color del servicio SIN que grite.
double BlendComponent(int a, int b, double t) {
  return a * t + b * (1.0 - t);
}

COLORREF Blend(COLORREF a, COLORREF b, double t) {
  return RGB(static_cast<int>(BlendComponent(GetRValue(a), GetRValue(b), t)),
             static_cast<int>(BlendComponent(GetGValue(a), GetGValue(b), t)),
             static_cast<int>(BlendComponent(GetBValue(a), GetBValue(b), t)));
}

// Alto de un evento (con su separador y su rótulo de día, si tocan).
int EventHeight(const EventWidget::Event& e, bool first) {
  int h = first ? 0 : kSepH;
  if (e.show_day && !e.day.empty()) h += kDayH;
  h += kTitleH;
  if (!e.subtitle.empty()) h += kSubH;
  return h + kItemGap;
}

// Paleta de la app en CLARO: los MISMOS valores del tema claro de la app
// (AppTheme.light): tarjeta = cardColor, texto = onSurface, secundario =
// onSurfaceVariant, acento = primary y líneas = dividerColor.
constexpr EventWidget::Palette kLight = {
    /* card      */ RGB(243, 246, 252),  // #F3F6FC (gris azulado: se separa
                                         // del escritorio blanco)
    /* border    */ RGB(226, 232, 242),
    /* brand     */ RGB(47, 107, 255),   // #2F6BFF (primary)
    /* accent    */ RGB(47, 107, 255),   // #2F6BFF (primary)
    /* text      */ RGB(26, 27, 33),     // #1A1B21 (onSurface)
    /* muted     */ RGB(69, 70, 79),     // #45464F (onSurfaceVariant)
    /* divider   */ RGB(219, 226, 238),  // línea bajo el encabezado
    /* badge_bg  */ RGB(230, 238, 255),
    /* add_bg    */ RGB(230, 238, 255),
    /* separator */ RGB(230, 235, 244),
};

// Paleta de la app en OSCURO: mismos colores del tema oscuro (AppTheme.dark).
// La app NO aclara su azul de marca en oscuro (primary sigue siendo #2F6BFF) ni
// cambia el texto: el widget debe verse igual que la app, no "parecido".
constexpr EventWidget::Palette kDark = {
    /* card      */ RGB(13, 18, 28),     // #0D121C (más oscuro: el panel se
                                         // despega del escritorio)
    /* border    */ RGB(37, 45, 60),
    /* brand     */ RGB(47, 107, 255),   // #2F6BFF (primary)
    /* accent    */ RGB(47, 107, 255),   // #2F6BFF (primary)
    /* text      */ RGB(227, 225, 233),  // #E3E1E9 (onSurface del tema)
    /* muted     */ RGB(198, 198, 208),  // #C6C6D0 (onSurfaceVariant)
    /* divider   */ RGB(35, 43, 58),     // línea bajo el encabezado
    /* badge_bg  */ RGB(24, 39, 72),
    /* add_bg    */ RGB(24, 39, 72),
    /* separator */ RGB(28, 36, 50),
};

HFONT MakeFont(HDC dc, int point_size, bool bold) {
  const int height = -MulDiv(point_size, GetDeviceCaps(dc, LOGPIXELSY), 72);
  return CreateFontW(height, 0, 0, 0, bold ? FW_SEMIBOLD : FW_NORMAL, FALSE,
                     FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                     CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                     DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
}

// Una línea de texto con el formato que se pida.
void DrawTextIn(HDC dc, HFONT font, COLORREF color, const RECT& box,
                const std::wstring& text, UINT format) {
  if (text.empty()) return;
  HGDIOBJ old_font = SelectObject(dc, font);
  SetTextColor(dc, color);
  RECT r = box;
  DrawTextW(dc, text.c_str(), -1, &r, format | DT_NOPREFIX);
  SelectObject(dc, old_font);
}

void DrawLine(HDC dc, HFONT font, COLORREF color, const RECT& box,
              const std::wstring& text) {
  DrawTextIn(dc, font, color, box, text,
             DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
}

// Ancho de un texto con la fuente dada.
int TextWidth(HDC dc, HFONT font, const std::wstring& text) {
  if (text.empty()) return 0;
  HGDIOBJ old_font = SelectObject(dc, font);
  SIZE size = {};
  GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()), &size);
  SelectObject(dc, old_font);
  return size.cx;
}

// Línea de 1 px (separadores del panel).
void HairLine(HDC dc, COLORREF color, int x1, int x2, int y) {
  HPEN pen = CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_pen = SelectObject(dc, pen);
  MoveToEx(dc, x1, y, nullptr);
  LineTo(dc, x2, y);
  SelectObject(dc, old_pen);
  DeleteObject(pen);
}

void FillRectColor(HDC dc, COLORREF color, const RECT& box) {
  HBRUSH brush = CreateSolidBrush(color);
  FillRect(dc, &box, brush);
  DeleteObject(brush);
}

// Rectángulo con esquinas redondeadas y relleno SÓLIDO (sin borde): lo usan las
// tarjetas de cada evento y su barra de acento.
void RoundedFill(HDC dc, COLORREF color, const RECT& box, int radius) {
  HBRUSH brush = CreateSolidBrush(color);
  HGDIOBJ old_brush = SelectObject(dc, brush);
  HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
  RoundRect(dc, box.left, box.top, box.right, box.bottom, radius, radius);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(brush);
}

}  // namespace

EventWidget::EventWidget(HWND owner) : owner_(owner) {}

EventWidget::~EventWidget() {
  DestroyPanel();
  if (header_font_) DeleteObject(header_font_);
  if (badge_font_) DeleteObject(badge_font_);
  if (title_font_) DeleteObject(title_font_);
  if (time_font_) DeleteObject(time_font_);
  if (body_font_) DeleteObject(body_font_);
  if (day_font_) DeleteObject(day_font_);
}

const EventWidget::Palette& EventWidget::Colors() const {
  return dark_ ? kDark : kLight;
}

std::wstring EventWidget::BadgeText() const {
  const size_t n = events_.size();
  if (n == 0) return std::wstring();
  if (n == 1) return L"1 evento";
  return std::to_wstring(n) + L" eventos";
}

int EventWidget::ContentHeight() const {
  if (events_.empty()) return kEmptyH;
  int h = 0;
  for (size_t i = 0; i < events_.size(); ++i) {
    h += EventHeight(events_[i], i == 0);
  }
  return h;
}

// Tope del listado: lo que quepa en la pantalla sin comerse el escritorio.
int EventWidget::MaxViewHeight() const {
  HMONITOR monitor =
      MonitorFromWindow(owner_ ? owner_ : hwnd_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  int work_h = 800;
  if (GetMonitorInfoW(monitor, &info)) {
    work_h = info.rcWork.bottom - info.rcWork.top;
  }
  const int chrome =
      kPadding * 2 + kHeaderH + kDividerGap + kContentGap;
  int max_view = work_h - 2 * kMargin - chrome;
  if (max_view < 90) max_view = 90;
  return std::min(max_view, kMaxViewH);
}

int EventWidget::ViewHeight() const {
  return std::min(ContentHeight(), MaxViewHeight());
}

int EventWidget::PanelHeight() const {
  return kPadding * 2 + kHeaderH + kDividerGap + kContentGap + ViewHeight();
}

int EventWidget::MaxScroll() const {
  return std::max(0, ContentHeight() - ViewHeight());
}

void EventWidget::ScrollBy(int delta) {
  const int next = std::max(0, std::min(scroll_ + delta, MaxScroll()));
  if (next == scroll_) return;
  scroll_ = next;
  if (hwnd_) InvalidateRect(hwnd_, nullptr, TRUE);
}

void EventWidget::EnsureWindow() {
  if (hwnd_) return;
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = EventWidget::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    RegisterClassW(&wc);
    registered = true;
  }
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kClassName,
      L"Pr\u00f3ximos eventos", WS_POPUP, 0, 0, kWidth, PanelHeight(), owner_,
      nullptr, GetModuleHandle(nullptr), this);
  if (hwnd_) {
    PlaceAtCorner();
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  }
}

void EventWidget::DestroyPanel() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

// Ancla el panel a la esquina inferior derecha del monitor del área de trabajo
// y le redondea las esquinas (mismo lenguaje visual que el widget de Android).
void EventWidget::PlaceAtCorner() {
  if (!hwnd_) return;
  HMONITOR monitor = MonitorFromWindow(owner_ ? owner_ : hwnd_,
                                      MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  RECT work = {0, 0, 1280, 720};
  if (GetMonitorInfoW(monitor, &info)) work = info.rcWork;

  const int height = PanelHeight();
  const int x = work.right - kWidth - kMargin;
  int y = work.bottom - height - kMargin;
  if (y < work.top + kMargin) y = work.top + kMargin;
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, kWidth, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);

  HRGN region = CreateRoundRectRgn(0, 0, kWidth + 1, height + 1, 22, 22);
  SetWindowRgn(hwnd_, region, TRUE);  // el sistema toma la propiedad
}

void EventWidget::Update(const std::wstring& header,
                         const std::vector<Event>& events, bool visible,
                         bool dark, bool can_add) {
  if (!header.empty()) header_ = header;
  dark_ = dark;
  can_add_ = can_add;
  events_ = events;
  // La lista empieza de arriba: es información nueva.
  scroll_ = 0;
  if (!visible) {
    Hide();
    return;
  }
  EnsureWindow();
  if (hwnd_) {
    PlaceAtCorner();
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
}

void EventWidget::Hide() { DestroyPanel(); }

int EventWidget::EventAt(POINT p) const {
  // Las zonas salen del último Paint (ya llevan el desplazamiento aplicado),
  // así que el punto de cliente se compara tal cual.
  for (size_t i = 0; i < row_hits_.size() && i < events_.size(); ++i) {
    if (p.y >= row_hits_[i].first && p.y < row_hits_[i].second) {
      return events_[i].id;
    }
  }
  return 0;
}

void EventWidget::FocusOwner() {
  if (!owner_) return;
  if (IsIconic(owner_)) ShowWindow(owner_, SW_RESTORE);
  SetForegroundWindow(owner_);
}

void EventWidget::Paint(HDC dc) {
  const Palette& c = Colors();
  RECT client = {};
  GetClientRect(hwnd_, &client);

  // Tarjeta (el modo lo elige la app, no el sistema). SIN borde dibujado: la
  // esquina redondeada ya la recorta la región de la ventana y una línea
  // encima se cortaba en las curvas (se veía sucia).
  FillRectColor(dc, c.card, client);

  if (!header_font_) header_font_ = MakeFont(dc, 14, true);
  if (!badge_font_) badge_font_ = MakeFont(dc, 9, true);
  if (!title_font_) title_font_ = MakeFont(dc, 11, true);
  if (!time_font_) time_font_ = MakeFont(dc, 10, true);
  if (!body_font_) body_font_ = MakeFont(dc, 10, false);
  if (!day_font_) day_font_ = MakeFont(dc, 9, true);

  SetBkMode(dc, TRANSPARENT);

  const int left = kPadding;
  const int right = client.right - kPadding;

  // --- Encabezado: punto de acento + título + pastilla con el contador ---
  {
    HBRUSH dot = CreateSolidBrush(c.brand);
    HGDIOBJ old_db = SelectObject(dc, dot);
    HGDIOBJ old_dp = SelectObject(dc, GetStockObject(NULL_PEN));
    const int cy = kPadding + kHeaderH / 2;
    Ellipse(dc, left, cy - 5, left + 10, cy + 5);
    SelectObject(dc, old_db);
    SelectObject(dc, old_dp);
    DeleteObject(dot);
  }

  // De derecha a izquierda: botón "+", contador y, con lo que sobra, título.
  int trailing_right = right;
  const std::wstring badge = BadgeText();
  const int badge_w = badge.empty() ? 0 : TextWidth(dc, badge_font_, badge) + 24;

  // --- Botón "Agregar agenda" (solo si el rol puede crear agendas) ---
  add_box_ = RECT{0, 0, 0, 0};
  if (can_add_) {
    const int top = kPadding + (kHeaderH - kAddSize) / 2;
    RECT pill = {trailing_right - kAddSize, top, trailing_right, top + kAddSize};
    HPEN apen = CreatePen(PS_SOLID, 1, c.add_bg);
    HBRUSH abrush = CreateSolidBrush(c.add_bg);
    HGDIOBJ oa = SelectObject(dc, abrush);
    HGDIOBJ opa = SelectObject(dc, apen);
    RoundRect(dc, pill.left, pill.top, pill.right, pill.bottom, kAddSize,
              kAddSize);
    SelectObject(dc, oa);
    SelectObject(dc, opa);
    DeleteObject(abrush);
    DeleteObject(apen);
    // El "+", en el azul de la marca.
    const int cx = (pill.left + pill.right) / 2;
    const int cy = (pill.top + pill.bottom) / 2;
    RECT hbar = {cx - 8, cy - 1, cx + 9, cy + 2};
    RECT vbar = {cx - 1, cy - 8, cx + 2, cy + 9};
    FillRectColor(dc, c.brand, hbar);
    FillRectColor(dc, c.brand, vbar);
    add_box_ = pill;
    trailing_right = pill.left - kAddGap;
  }

  if (!badge.empty()) {
    const int bh = 26;
    const int top = kPadding + (kHeaderH - bh) / 2;
    RECT pill = {trailing_right - badge_w, top, trailing_right, top + bh};
    HPEN bpen = CreatePen(PS_SOLID, 1, c.badge_bg);
    HBRUSH bbrush = CreateSolidBrush(c.badge_bg);
    HGDIOBJ ob = SelectObject(dc, bbrush);
    HGDIOBJ op = SelectObject(dc, bpen);
    RoundRect(dc, pill.left, pill.top, pill.right, pill.bottom, bh, bh);
    SelectObject(dc, ob);
    SelectObject(dc, op);
    DeleteObject(bbrush);
    DeleteObject(bpen);
    DrawTextIn(dc, badge_font_, c.brand, pill, badge,
               DT_CENTER | DT_SINGLELINE | DT_VCENTER);
    trailing_right = pill.left - 8;
  }

  RECT header_box = {left + 18, kPadding, trailing_right, kPadding + kHeaderH};
  DrawLine(dc, header_font_, c.brand, header_box, header_);

  // --- Separador bajo el encabezado ---
  const int divider_y = kPadding + kHeaderH + kDividerGap;
  HairLine(dc, c.divider, left, right, divider_y);

  // --- Listado (con desplazamiento si no cabe) ---
  const int content_top = divider_y + kContentGap;
  const int content_bottom = client.bottom - kPadding;
  const int view_h = std::max(0, content_bottom - content_top);

  HRGN clip = CreateRectRgn(left - 2, content_top, client.right, content_bottom);
  SelectClipRgn(dc, clip);
  DeleteObject(clip);

  // Zonas de clic de cada fila (se recalculan en cada pintado).
  row_hits_.assign(events_.size(), std::make_pair(0, 0));

  if (events_.empty()) {
    RECT empty_box = {left, content_top, right, content_top + kEmptyH};
    DrawLine(dc, body_font_, c.muted, empty_box, L"Sin eventos próximos");
    SelectClipRgn(dc, nullptr);
    return;
  }

  // La barra de desplazamiento (fina, a la derecha) le roba un poco de ancho.
  const int content_right = right - (MaxScroll() > 0 ? 6 : 0);

  int y = content_top - scroll_;
  for (size_t i = 0; i < events_.size(); ++i) {
    const Event& e = events_[i];
    const int row_top = y;
    if (i > 0) {
      if (y > content_top - 4 && y < content_bottom) {
        HairLine(dc, c.separator, left, content_right, y + kSepH / 2);
      }
      y += kSepH;
    }
    if (e.show_day && !e.day.empty()) {
      RECT day_box = {left + 4, y, content_right, y + kDayH - 5};
      DrawLine(dc, day_font_, c.brand, day_box, e.day);
      y += kDayH;
    }

    // ---- Tarjeta del evento: tinte tenue del color de SU servicio + barra de
    // acento a la izquierda. Así dos eventos distintos se separan a simple
    // vista sin gritar (el mismo lenguaje del calendario de la app). ----
    const int card_top = y;
    const int card_bottom =
        card_top + kTitleH + (e.subtitle.empty() ? 0 : kSubH);
    const COLORREF service = ServiceColor(e.service);
    if (card_bottom > content_top && card_top < content_bottom) {
      const COLORREF tint =
          Blend(service, c.card, dark_ ? 0.18 : 0.11);
      const RECT card = {left, card_top, content_right, card_bottom};
      RoundedFill(dc, tint, card, kRowRadius);
      const RECT bar = {left + 1, card_top + 2, left + 1 + kBarW,
                        card_bottom - 2};
      RoundedFill(dc, service, bar, kBarW);
    }

    // Titular a la izquierda (dentro de la tarjeta) y HORA a la derecha.
    const int text_left = left + kBarW + kRowInset + 5;
    const int text_right = content_right - kRowInset;
    const std::wstring& when =
        (e.show_day && !e.time.empty()) ? e.time : e.when;
    const int when_w = TextWidth(dc, time_font_, when);
    RECT title_box = {text_left, card_top + 1, text_right - when_w - 10,
                      card_top + kTitleH};
    DrawLine(dc, title_font_, c.text, title_box, e.title);
    if (when_w > 0) {
      RECT when_box = {text_right - when_w, card_top + 1, text_right,
                       card_top + kTitleH};
      DrawTextIn(dc, time_font_, c.accent, when_box, when,
                 DT_RIGHT | DT_SINGLELINE | DT_VCENTER);
    }

    if (!e.subtitle.empty()) {
      RECT sub_box = {text_left, card_top + kTitleH, text_right,
                      card_top + kTitleH + kSubH - 3};
      DrawLine(dc, body_font_, c.muted, sub_box, e.subtitle);
    }
    y = card_bottom + kItemGap;

    // Toda la fila (rótulo de día incluido) es zona de clic.
    row_hits_[i] = std::make_pair(row_top, y);

    if (y - kItemGap > content_bottom) break;  // lo de abajo no se ve
  }

  // Barra de desplazamiento: solo cuando hay más eventos de los que caben.
  const int max_scroll = MaxScroll();
  if (max_scroll > 0 && view_h > 0) {
    const int total = ContentHeight();
    const int track_x = client.right - 6;
    RECT track = {track_x, content_top, track_x + 3, content_bottom};
    FillRectColor(dc, c.divider, track);
    int thumb_h = view_h * view_h / std::max(total, 1);
    if (thumb_h < 32) thumb_h = 32;
    const int travel = view_h - thumb_h;
    const int thumb_y =
        content_top + static_cast<int>(std::lround(
                          static_cast<double>(travel) * scroll_ / max_scroll));
    RECT thumb = {track_x - 1, thumb_y, track_x + 4, thumb_y + thumb_h};
    HBRUSH brush = CreateSolidBrush(c.brand);
    HGDIOBJ old_brush2 = SelectObject(dc, brush);
    HGDIOBJ old_pen2 = SelectObject(dc, GetStockObject(NULL_PEN));
    RoundRect(dc, thumb.left, thumb.top, thumb.right, thumb.bottom, 4, 4);
    SelectObject(dc, old_brush2);
    SelectObject(dc, old_pen2);
    DeleteObject(brush);
  }

  SelectClipRgn(dc, nullptr);
}

LRESULT CALLBACK EventWidget::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  EventWidget* self =
      reinterpret_cast<EventWidget*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    self = reinterpret_cast<EventWidget*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self) return self->HandleMessage(message, wparam, lparam);
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT EventWidget::HandleMessage(UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd_, &ps);
      Paint(dc);
      EndPaint(hwnd_, &ps);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;  // el fondo lo pinta WM_PAINT (evita parpadeo)
    // La rueda desplaza el listado. Windows también la manda a la ventana bajo
    // el cursor ("desplazar ventanas inactivas"), que es justo lo que queremos:
    // el panel nunca tiene el foco.
    case WM_MOUSEWHEEL: {
      const int notches = GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA;
      if (notches != 0) ScrollBy(-notches * kScrollStep);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      dragging_ = true;
      moved_ = false;
      POINT screen = PointFromLParam(lparam);
      ClientToScreen(hwnd_, &screen);
      drag_origin_ = screen;
      GetWindowRect(hwnd_, &drag_start_);
      SetCapture(hwnd_);
      return 0;
    }
    case WM_MOUSEMOVE: {
      if (!dragging_) return 0;
      POINT screen = PointFromLParam(lparam);
      ClientToScreen(hwnd_, &screen);
      const int dx = screen.x - drag_origin_.x;
      const int dy = screen.y - drag_origin_.y;
      if (std::abs(dx) > 3 || std::abs(dy) > 3) moved_ = true;
      SetWindowPos(hwnd_, HWND_TOPMOST, drag_start_.left + dx,
                   drag_start_.top + dy, 0, 0,
                   SWP_NOSIZE | SWP_NOACTIVATE);
      return 0;
    }
    case WM_LBUTTONUP: {
      if (dragging_) {
        dragging_ = false;
        ReleaseCapture();
        if (!moved_) {
          // Clic sin arrastre: el botón "+" abre el alta de evento; una fila
          // abre el detalle de ESA agenda; cualquier otro punto trae la app al
          // frente. Quien navega es Dart (callbacks en FlutterWindow).
          const POINT p = PointFromLParam(lparam);
          if (add_box_.right > add_box_.left && PtInRect(&add_box_, p)) {
            if (on_add_tap) on_add_tap();
          } else {
            const int id = EventAt(p);
            if (id > 0 && on_event_tap) {
              on_event_tap(id);
            } else {
              FocusOwner();
            }
          }
        }
      }
      return 0;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;  // no roba el foco al hacer clic
    default:
      break;
  }
  return DefWindowProc(hwnd_, message, wparam, lparam);
}
