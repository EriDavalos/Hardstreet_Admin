import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../card_html.dart';
import '../open_html.dart';
import '../site_design.dart';
import 'common.dart';
import 'hs_modal.dart';

// ==================================================================
// DISEÑADOR DE TARJETAS DE PAQUETE
// ==================================================================
// A la izquierda se ajusta el diseño; a la derecha se ve EN VIVO cómo quedará
// la tarjeta (y la fila) en la web. Lo que se guarda aquí es el documento que
// el sitio aplica al cargar (GET /api/site → `gallery/assets/site.js`), así que
// lo que se ve en este preview es lo que se ve en la página.
//
//   * pestaña GLOBAL  → forma, densidad, tipografía y qué elementos se muestran
//   * pestañas por TIER (Premium / Gold / Basic) → su paleta
//
// El diálogo solo DISEÑA: devuelve el [SiteDesign] y quien lo abre lo guarda.
// ==================================================================

/// Paletas listas para elegir de un toque: acento / acento claro / fondo.
const List<List<String>> kDesignPresets = [
  ['#C9A96E', '#F0D48A', '#0B0E17'], // oro de la marca
  ['#D9A441', '#F2C66B', '#120E05'], // ámbar cálido
  ['#8FB0D4', '#B9D0E6', '#0B111A'], // acero frío
  ['#7C5CFF', '#C4B5FD', '#120C2B'], // violeta
  ['#10B981', '#6EE7B7', '#04231A'], // esmeralda
  ['#EF4444', '#FCA5A5', '#2A0A0A'], // rojo
  ['#EC4899', '#F9A8D4', '#2B0719'], // rosa
  ['#3B82F6', '#93C5FD', '#08172F'], // azul
  ['#F59E0B', '#FCD34D', '#2A1B02'], // ámbar
  ['#14B8A6', '#5EEAD4', '#04211F'], // turquesa
];

/// Colores de la PALETA (se eligen de un toque): neutros, los dorados de la
/// marca y los matices habituales, ya oscurecidos donde hace falta para que el
/// texto claro se lea encima.
const List<String> kColorSwatches = [
  // Neutros
  '#000000', '#0B0E17', '#1F2937', '#374151', '#6B7280', '#9CA3AF',
  '#D1D5DB', '#FFFFFF',
  // Dorados de la marca
  '#C9A96E', '#F0D48A', '#D9A441', '#F2C66B', '#8B6F3E', '#5A4526',
  // Rojos y rosas
  '#EF4444', '#FCA5A5', '#B91C1C', '#7F1D1D', '#EC4899', '#F9A8D4',
  // Naranjas y amarillos
  '#F59E0B', '#FCD34D', '#EA580C', '#9A3412', '#FACC15',
  // Verdes
  '#10B981', '#6EE7B7', '#047857', '#065F46', '#22C55E', '#84CC16',
  // Azules
  '#3B82F6', '#93C5FD', '#1D4ED8', '#1E3A8A', '#0EA5E9', '#38BDF8',
  // Morados
  '#7C5CFF', '#C4B5FD', '#5B21B6', '#3B0764', '#A855F7', '#D8B4FE',
  // Turquesa y cían oscuro
  '#14B8A6', '#5EEAD4', '#0E7490', '#164E63',
];

const Map<String, String> kTierLabels = {
  'premium': 'Premium',
  'gold': 'Gold',
  'basic': 'Basic',
};

/// Abre el diseñador. Devuelve el diseño elegido (o null si se canceló).
Future<SiteDesign?> showPackageDesigner(
  BuildContext context, {
  required SiteDesign design,
}) => showHsModal<SiteDesign>(
  context: context,
  builder: (_) => _PackageDesigner(initial: design),
);

/// Las dos capas de degradado que oscurecen la FOTO DE FONDO de una tarjeta,
/// con el color del velo ([colorHex], negro de fábrica) y la fuerza del diseño
/// ([amount], 0..1).
///
/// Son las MISMAS de la web (`site.js` → `hsPhotoFade`): la foto se pinta a
/// todo color y encima van estas capas, que tapan más de un lado —donde van el
/// nombre, los servicios y el precio— y menos del otro. [from] elige de dónde
/// viene el velo: `bottom` (por defecto), `top`, `left`, `right` o una esquina
/// (`topLeft`…). [angle] (0..359, grados CSS) es el ajuste fino: si no es -1,
/// manda sobre la dirección.
List<LinearGradient> hsPhotoFadeGradients(
  String colorHex,
  double amount, {
  String from = 'bottom',
  double angle = -1,
}) {
  final dark = hsHexColor(colorHex, Colors.black);
  final f = amount.clamp(0.0, 1.0);
  Color a(double x) => dark.withValues(alpha: x.clamp(0.0, 1.0));
  // El degradado se construye SIEMPRE en el mismo eje y se gira al ángulo CSS
  // del diseño. Antes cada dirección armaba su propio `begin`/`end` y luego se
  // giraba: con un ángulo libre y una dirección distinta de `bottom`, el panel
  // y la web giraban en sentidos distintos. Ahora el número es el mismo
  // (`hsFadeCssDeg`, compartido con el HTML y con la web).
  LinearGradient at(
    double deg,
    List<Color> colors,
    List<double> stops,
  ) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
    transform: GradientRotation((deg - 180) * math.pi / 180),
  );
  final main = at(
    hsFadeCssDeg(from, angle),
    [a(f * .15), a(f * .6), a(f)],
    const [0, .5, 1],
  );
  // Capa secundaria: PERPENDICULAR a la principal (tapón de contorno).
  final side = at(
    hsFadeSideCssDeg(from, angle),
    [a(f * .55), a(f * .22), a(0)],
    const [0, .55, 1],
  );
  return [main, side];
}

/// SOMBRA de la foto de fondo: un degradado NEGRO que sube desde abajo (0 = sin
/// sombra, `null`). Es independiente del velo, que puede ser de cualquier color.
///
/// Se ajusta como las PARADAS de un degradado de Photoshop: [start] es dónde el
/// negro deja de ser sólido y [end] dónde se apaga del todo (0..1, desde abajo).
/// La web pinta exactamente la misma capa (`site.js` → `.pkg-photo-bg::before`).
LinearGradient? hsPhotoShadowGradient(
  double amount, {
  double start = .08,
  double end = .72,
}) {
  final s = amount.clamp(0.0, 1.0);
  if (s <= 0) return null;
  final a = start.clamp(0.0, .95);
  final b = end.clamp(a + .05, 1.0);
  final black = Colors.black.withValues(alpha: s);
  return LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [black, black, Colors.black.withValues(alpha: 0)],
    stops: [0, a, b],
  );
}

/// Fondo de la tarjeta en el estilo `fade`: el color plano del diseño.
Color hsCardBgColor(SiteCardDesign c) => hsHexColor(c.cardBgFrom);

/// Degradado del fondo de la tarjeta en el estilo `fade` (null = color plano).
///
/// El ángulo es el CSS del diseño: 0 = hacia arriba, 90 = a la derecha. Se
/// construye en el eje vertical y se gira, igual que el velo, para que el panel
/// y la web pinten el mismo degradado.
LinearGradient? hsCardBgGradient(SiteCardDesign c) {
  if (!c.cardBgGradient) return null;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [hsHexColor(c.cardBgFrom), hsHexColor(c.cardBgTo)],
    transform: GradientRotation((c.cardBgAngle - 180) * math.pi / 180),
  );
}

/// Desvanece la FOTO del estilo `fade` hacia el fondo de la tarjeta.
///
/// La foto se ve entera hasta [start] y termina de desaparecer en [end], en la
/// dirección del diseño ([from] o [angle]): lo que queda detrás es el color (o
/// el degradado) del fondo, así que la transición es limpia, sin velo encima.
/// La web hace lo mismo con `mask-image` y los MISMOS números.
Widget hsPhotoFadeMask({
  required Widget child,
  String from = 'bottom',
  double angle = -1,
  double start = .15,
  double end = .85,
}) {
  final a = start.clamp(0.0, .95);
  final b = end.clamp(a + .05, 1.0);
  return ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (rect) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [0, a, b],
      transform: GradientRotation(
        (hsFadeCssDeg(from, angle) - 180) * math.pi / 180,
      ),
    ).createShader(rect),
    child: child,
  );
}

/// El degradado de la foto de fondo (velo + sombra opcional), ya listo para
/// poner en un `Stack` (no intercepta el puntero: la tarjeta sigue siendo
/// tocable).
Widget hsPhotoFadeOverlay(
  String colorHex,
  double amount, {
  String from = 'bottom',
  double angle = -1,
  double shadow = 0,
  double shadowStart = .08,
  double shadowEnd = .72,
}) => IgnorePointer(
  child: Stack(
    fit: StackFit.expand,
    children: [
      // La sombra va DEBAJO del velo: el velo (con su color) sigue manando.
      if (hsPhotoShadowGradient(shadow, start: shadowStart, end: shadowEnd)
          case final g?)
        DecoratedBox(decoration: BoxDecoration(gradient: g)),
      for (final g in hsPhotoFadeGradients(
        colorHex,
        amount,
        from: from,
        angle: angle,
      ))
        DecoratedBox(decoration: BoxDecoration(gradient: g)),
    ],
  ),
);

/// `#RRGGBB` → Color (con respaldo para que un valor raro nunca reviente).
Color hsHexColor(String hex, [Color fallback = Colors.grey]) {
  final s = hex.replaceAll('#', '').trim();
  final full = s.length == 3 ? s.split('').map((c) => '$c$c').join() : s;
  final v = int.tryParse(full, radix: 16);
  if (v == null || full.length != 6) return fallback;
  return Color(0xFF000000 | v);
}

/// Color → `#RRGGBB` (lo que guarda el diseño).
String hsColorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _PackageDesigner extends StatefulWidget {
  const _PackageDesigner({required this.initial});

  final SiteDesign initial;

  @override
  State<_PackageDesigner> createState() => _PackageDesignerState();
}

class _PackageDesignerState extends State<_PackageDesigner> {
  late SiteDesign _d = widget.initial;

  /// Pestaña activa: 'global' o la clave de un tier.
  String _tab = 'global';

  /// Tier de la vista previa. Arranca en Premium y sigue a la pestaña que se
  /// abra: al ajustar Gold se ve GOLD (antes el preview salía siempre en
  /// Premium y en Gold/Basic no se veía ningún cambio).
  String _previewTier = 'premium';

  /// Cuántas veces se pidió reproducir la animación de entrada (cada toque la
  /// vuelve a lanzar en la vista previa).
  int _animRun = 0;

  /// Abre la tarjeta (el HTML real, con su CSS) en el navegador del sistema.
  Future<void> _openInBrowser() async {
    final ok = await hsOpenHtmlInBrowser(_cardHtml());
    if (ok || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir el navegador con la tarjeta'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width > 980;

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.style_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Diseñador de tarjetas',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _d = SiteDesign.defaults),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Diseño original'),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            _hr(scheme),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 400, child: _controls(scheme)),
                        VerticalDivider(width: 1, color: _line(scheme)),
                        Expanded(child: _preview(scheme)),
                      ],
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Diseño'),
                              Tab(text: 'Vista previa'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [_controls(scheme), _preview(scheme)],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            _hr(scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al guardar, la página web lo aplica al instante '
                      '(no hay que publicar el sitio).',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_d),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Guardar diseño'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hr(ColorScheme s) => Divider(height: 1, color: _line(s));

  Color _line(ColorScheme s) => s.outlineVariant.withValues(alpha: .5);

  // ---------------------------------------------------------------
  // Controles
  // ---------------------------------------------------------------

  Widget _controls(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tabChip('global', 'Global'),
            for (final e in kTierLabels.entries) _tabChip(e.key, e.value),
          ],
        ),
        const SizedBox(height: 16),
        if (_tab == 'global')
          ..._globalControls(scheme)
        else
          ..._tierControls(scheme, _tab),
      ],
    );
  }

  Widget _tabChip(String key, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == key;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      key: ValueKey('design-tab-$key'),
      onTap: () => setState(() {
        _tab = key;
        // Ajustar la paleta de un tier lo enseña en la vista previa al momento.
        if (key != 'global') _previewTier = key;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: .16)
              : scheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: .6)
                : _line(scheme),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  List<Widget> _globalControls(ColorScheme scheme) {
    final c = _d.card;
    void update(SiteCardDesign next) =>
        setState(() => _d = _d.copyWith(card: next));

    return [
      _group('Marca'),
      Row(
        children: [
          Expanded(
            child: _ColorField(
              label: 'Dorado',
              value: _d.gold,
              onChanged: (v) => setState(() => _d = _d.copyWith(gold: v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ColorField(
              label: 'Dorado claro',
              value: _d.goldLight,
              onChanged: (v) => setState(() => _d = _d.copyWith(goldLight: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _group('Catálogo'),
      _slider(
        'Columnas',
        c.columns.toDouble(),
        1,
        4,
        (v) => update(c.copyWith(columns: v.round())),
        divisions: 3,
        valueLabel: '${c.columns}',
      ),
      _slider(
        'Separación',
        c.gap,
        0,
        80,
        (v) => update(c.copyWith(gap: v)),
        valueLabel: '${c.gap.round()} px',
      ),
      const SizedBox(height: 18),
      _group('Tarjeta'),
      _slider(
        'Redondeo',
        c.radius,
        0,
        40,
        (v) => update(c.copyWith(radius: v)),
        valueLabel: '${c.radius.round()} px',
      ),
      _slider(
        'Borde',
        c.borderWidth,
        0,
        6,
        (v) => update(c.copyWith(borderWidth: v)),
        valueLabel: '${c.borderWidth.round()} px',
      ),
      _slider(
        'Relleno',
        c.padding,
        8,
        56,
        (v) => update(c.copyWith(padding: v)),
        valueLabel: '${c.padding.round()} px',
      ),
      _switch(
        'Línea superior',
        c.lineTop,
        (v) => update(c.copyWith(lineTop: v)),
      ),
      _switch(
        'Se eleva al pasar el mouse',
        c.hoverLift,
        (v) => update(c.copyWith(hoverLift: v)),
      ),
      _switch(
        'Sombra al pasar el mouse',
        c.shadow,
        (v) => update(c.copyWith(shadow: v)),
      ),
      const SizedBox(height: 18),
      _group('Tipografía del nombre'),
      _switch(
        'Serif (Playfair)',
        c.serifNames,
        (v) => update(c.copyWith(serifNames: v)),
      ),
      _switch(
        'MAYÚSCULAS',
        c.uppercaseNames,
        (v) => update(c.copyWith(uppercaseNames: v)),
      ),
      const SizedBox(height: 18),
      _group('Qué se muestra'),
      _switch(
        'Categoría',
        c.showCategory,
        (v) => update(c.copyWith(showCategory: v)),
      ),
      _switch(
        'Subtítulo',
        c.showSubtitle,
        (v) => update(c.copyWith(showSubtitle: v)),
      ),
      _switch(
        'Cuántos servicios',
        c.showServiceCount,
        (v) => update(c.copyWith(showServiceCount: v)),
      ),
      _switch(
        'Lista de servicios',
        c.showServices,
        (v) => update(c.copyWith(showServices: v)),
      ),
      _switch('Precio', c.showPrice, (v) => update(c.copyWith(showPrice: v))),
      _switch('Botón', c.showCta, (v) => update(c.copyWith(showCta: v))),
      const SizedBox(height: 6),
      _slider(
        'Servicios listados',
        c.servicesLimit.toDouble(),
        0,
        12,
        (v) => update(c.copyWith(servicesLimit: v.round())),
        divisions: 12,
        valueLabel: c.servicesLimit == 0 ? 'todos' : '${c.servicesLimit}',
      ),
      const SizedBox(height: 18),
      _group('Foto del paquete'),
      _optionChips(
        'Dónde va',
        const {
          'none': 'Sin foto',
          'top': 'Banda arriba',
          'bg': 'De fondo',
          'fade': 'Fondo degradado',
        },
        c.imageMode,
        (v) => update(c.copyWith(imageMode: v)),
        prefix: 'design-image',
      ),
      if (c.imageMode == 'top')
        _slider(
          'Alto de la banda',
          c.imageHeight,
          60,
          320,
          (v) => update(c.copyWith(imageHeight: v)),
          valueLabel: '${c.imageHeight.round()} px',
        ),
      if (c.imageMode == 'bg') ...[
        _slider(
          'Oscurecido de la foto (fuerza)',
          c.imageFade,
          0,
          1,
          (v) => update(c.copyWith(imageFade: v)),
          divisions: 20,
          valueLabel: '${(c.imageFade * 100).round()}%',
        ),
        _group('Degradado de la foto'),
        ..._photoShadowControls(c, update),
        _fadeAngleRow(c),
        const SizedBox(height: 10),
        _fadeColorRow(c),
        const SizedBox(height: 10),
        _fadePreview(c),
      ],
      if (c.imageMode == 'fade') ...[
        _group('Desvanecido de la foto'),
        _slider(
          'La foto se ve hasta',
          c.imageFadeStart.clamp(0, .95),
          0,
          .95,
          (v) => update(
            c.copyWith(
              imageFadeStart: v,
              // No puede terminar antes de empezar.
              imageFadeEnd: c.imageFadeEnd < v + .05
                  ? (v + .05).clamp(0, 1)
                  : c.imageFadeEnd,
            ),
          ),
          divisions: 19,
          valueLabel: '${(c.imageFadeStart * 100).round()}%',
        ),
        _slider(
          'Desaparece del todo en',
          c.imageFadeEnd.clamp(c.imageFadeStart + .05, 1),
          .05,
          1,
          (v) => update(c.copyWith(imageFadeEnd: v)),
          divisions: 19,
          valueLabel: '${(c.imageFadeEnd * 100).round()}%',
        ),
        _fadeAngleRow(
          c,
          title: 'Hacia dónde desaparece',
          hint: 'Gira el punto hacia el lado por el que la foto se funde con el '
              'fondo. 0° por arriba, 90° por la derecha, 180° por abajo.',
        ),
        const SizedBox(height: 6),
        _group('Fondo de la tarjeta'),
        _switch(
          'Fondo en degradado',
          c.cardBgGradient,
          (v) => update(c.copyWith(cardBgGradient: v)),
        ),
        if (c.cardBgGradient)
          _slider(
            'Ángulo del fondo',
            c.cardBgAngle.clamp(0, 359),
            0,
            359,
            (v) => update(c.copyWith(cardBgAngle: v)),
            divisions: 24,
            valueLabel: '${c.cardBgAngle.round()}°',
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _ColorField(
                label: c.cardBgGradient ? 'Fondo (color 1)' : 'Color de fondo',
                value: c.cardBgFrom,
                onChanged: (v) => update(c.copyWith(cardBgFrom: v)),
              ),
            ),
            if (c.cardBgGradient) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _ColorField(
                  label: 'Fondo (color 2)',
                  value: c.cardBgTo,
                  onChanged: (v) => update(c.copyWith(cardBgTo: v)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _cardBgPreview(c),
      ],
      Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se usa la foto del paquete (la que se le pone en Datos, y '
                  'que puede ser una foto del Drive). Si un paquete NO tiene '
                  'foto, su tarjeta se ve limpia —sin foto ni relleno—, igual '
                  'que en este panel. De fondo, la foto se ve con el degradado '
                  'de arriba para que el texto se lea.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      _group('Animación de entrada'),
      _optionChips(
        'Cómo aparecen',
        const {
          'up': 'Subir',
          'fade': 'Aparecer',
          'zoom': 'Zoom',
          'none': 'Sin animación',
        },
        c.animMode,
        (v) => update(c.copyWith(animMode: v)),
        prefix: 'design-anim',
      ),
      if (c.animMode != 'none') ...[
        _slider(
          'Duración',
          c.animMs.toDouble(),
          100,
          1600,
          (v) => update(c.copyWith(animMs: v.round())),
          divisions: 15,
          valueLabel: '${c.animMs} ms',
        ),
        _slider(
          'Retardo entre tarjetas',
          c.animStagger.toDouble(),
          0,
          400,
          (v) => update(c.copyWith(animStagger: v.round())),
          divisions: 16,
          valueLabel: c.animStagger == 0
              ? 'todas a la vez'
              : '${c.animStagger} ms',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _animRun++),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Ver la animación'),
          ),
        ),
      ],
      const SizedBox(height: 18),
      _group('Textos'),
      Row(
        children: [
          Expanded(
            child: _TextField(
              label: 'Rótulo del precio',
              value: c.priceLabel,
              onChanged: (v) => update(c.copyWith(priceLabel: v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TextField(
              label: 'Botón',
              value: c.ctaLabel,
              onChanged: (v) => update(c.copyWith(ctaLabel: v)),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _tierControls(ColorScheme scheme, String key) {
    final t = _d.tierOf(key);
    return [
      _group('Paleta · ${kTierLabels[key] ?? key}'),
      _switch(
        'Badge relleno (degradado)',
        t.badgeFilled,
        (v) => _d = _d.withTier(key, t.copyWith(badgeFilled: v)),
      ),
      _slider(
        'Fuerza del borde',
        t.borderAlpha,
        0,
        1,
        (v) => _d = _d.withTier(key, t.copyWith(borderAlpha: v)),
        divisions: 10,
        valueLabel: '${(t.borderAlpha * 100).round()}%',
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _ColorField(
              label: 'Acento',
              value: t.accent,
              onChanged: (v) => _d = _d.withTier(key, t.copyWith(accent: v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ColorField(
              label: 'Acento claro',
              value: t.accentSoft,
              onChanged: (v) =>
                  _d = _d.withTier(key, t.copyWith(accentSoft: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _ColorField(
        label: 'Fondo de la tarjeta',
        value: t.dark,
        onChanged: (v) => _d = _d.withTier(key, t.copyWith(dark: v)),
      ),
      const SizedBox(height: 18),
      _group('Paletas de degradado'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in kDesignPresets)
            Tooltip(
              message: 'Degradado ${p[0]} → ${p[1]}',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  _d = _d.withTier(
                    key,
                    t.copyWith(accent: p[0], accentSoft: p[1], dark: p[2]),
                  );
                }),
                child: Container(
                  width: 54,
                  height: 34,
                  decoration: BoxDecoration(
                    // La muestra ES el degradado del badge: acento → acento
                    // claro, igual que lo pinta la tarjeta.
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [hsHexColor(p[0]), hsHexColor(p[1])],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hsHexColor(p[2]), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: hsHexColor(p[0]).withValues(alpha: .35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 18),
      _group('Aplicar a los demás tiers'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in kTierLabels.keys)
            if (k != key)
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _d = _d.withTier(k, t.copyWith());
                }),
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: Text(
                  'Igual que ${kTierLabels[key]} → ${kTierLabels[k]}',
                ),
              ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------
  // Vista previa
  // ---------------------------------------------------------------

  Widget _preview(ColorScheme scheme) {
    final c = _d.card;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: .25),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Así se verá en la web',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // La tarjeta y la fila enseñan SIEMPRE el mismo tier: el que se está
          // ajustando. Así una paleta de Gold o de Basic se ve al momento.
          Text(
            'Muestra (card y fila con el mismo tier)',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          // Se acomoda en varias líneas: en columnas angostas los tres chips y
          // los dos botones no caben en una sola fila.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in kTierLabels.entries)
                _previewTierChip(e.key, e.value),
              if (!kIsWeb)
                TextButton.icon(
                  key: const ValueKey('design-open-browser'),
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Ver en el navegador'),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _animRun++),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Repetir'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: c.imageMode == 'bg' && c.imageShadow > 0
                  // Con el desvanecido encendido, sus dos paradas se mueven
                  // ARRASTRÁNDOLAS sobre la tarjeta (como en Photoshop).
                  ? _ShadowStops(
                      start: c.imageShadowStart,
                      end: c.imageShadowEnd,
                      onChanged: (s, e) => setState(
                        () => _d = _d.copyWith(
                          card: _d.card.copyWith(
                            imageShadowStart: s,
                            imageShadowEnd: e,
                          ),
                        ),
                      ),
                      child: _animatedPreview(_previewCard()),
                    )
                  : c.imageMode == 'fade'
                  // Las dos paradas del DESVANECIDO también se arrastran:
                  // dónde se ve la foto y dónde termina de fundirse con el
                  // fondo.
                  ? _ShadowStops(
                      start: c.imageFadeStart,
                      end: c.imageFadeEnd,
                      keyStart: const ValueKey('design-fade-start'),
                      keyEnd: const ValueKey('design-fade-end'),
                      labelStart: 'se ve',
                      labelEnd: 'desaparece',
                      onChanged: (s, e) => setState(
                        () => _d = _d.copyWith(
                          card: _d.card.copyWith(
                            imageFadeStart: s,
                            imageFadeEnd: e,
                          ),
                        ),
                      ),
                      child: _animatedPreview(_previewCard()),
                    )
                  : _animatedPreview(_previewCard()),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Fila (vista compacta del catálogo)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _previewRow(),
          const SizedBox(height: 16),
          Text(
            'Columnas del catálogo: ${c.columns} · '
            'servicios listados: ${c.servicesLimit == 0 ? 'todos' : c.servicesLimit} · '
            'borde: ${c.borderWidth <= 0 ? 'sin borde' : '${c.borderWidth.round()} px'} · '
            'foto: ${_imageLabel(c.imageMode)} · '
            'entrada: ${_animLabel(c)}',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// La tarjeta de muestra como HTML (mismos valores que la web).
  String _cardHtml() {
    final s = _sample;
    return hsPackageCardHtml(
      card: _d.card,
      tier: _d.tierOf(_previewTier),
      gold: _d.gold,
      sample: CardHtmlSample(
        tierKey: _previewTier,
        tierLabel: kTierLabels[_previewTier] ?? _previewTier,
        name: s.name,
        category: s.category,
        categoryIcon: hsCategoryEmoji(s.category),
        price: s.price,
        services: _sampleServices,
      ),
    );
  }

  String _imageLabel(String mode) => switch (mode) {
    'top' => 'banda arriba',
    'bg' => 'de fondo',
    'fade' => 'fondo con degradado',
    _ => 'sin foto',
  };

  String _animLabel(SiteCardDesign c) => c.animMode == 'none'
      ? 'sin animación'
      : '${switch (c.animMode) {
              'fade' => 'aparecer',
              'zoom' => 'zoom',
              _ => 'subir',
            }} ${c.animMs} ms'
            '${c.animStagger == 0 ? '' : ' · +${c.animStagger} ms por tarjeta'}';

  Widget _previewTierChip(String key, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _previewTier == key;
    final accent = hsHexColor(_d.tierOf(key).accent);
    return InkWell(
      key: ValueKey('design-preview-tier-$key'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _previewTier = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: selected ? .22 : .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: selected ? .75 : .3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rehace la entrada de la tarjeta en la vista previa (mismos modos que la
  /// web), para poder verla sin cambiar ningún ajuste.
  Widget _animatedPreview(Widget child) {
    final c = _d.card;
    final mode = c.animMode;
    final ms = c.animMs.clamp(0, 4000);
    if (mode == 'none' || ms == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('design-anim-$mode-$ms-$_animRun'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, mode == 'up' ? 24 * (1 - t) : 0),
          child: Transform.scale(
            scale: mode == 'zoom' ? .94 + .06 * t : 1,
            child: inner,
          ),
        ),
      ),
      child: child,
    );
  }

  static const _sampleServices = [
    'Cobertura',
    'Álbum impreso',
    'Video',
    'Galería online',
  ];

  /// Muestra de cada tier: la tarjeta y la fila se pintan con datos de SU tier.
  static const Map<String, ({String name, String category, String price})>
  _samples = {
    'premium': (name: 'Boda Full', category: 'Bodas', price: r'$25,000'),
    'gold': (name: 'XV Años Gold', category: 'XV Años', price: r'$18,000'),
    'basic': (name: 'Sesión Básica', category: 'Retrato', price: r'$6,500'),
  };

  ({String name, String category, String price}) get _sample =>
      _samples[_previewTier] ?? _samples['premium']!;

  /// Colores de velo listos para elegir de un toque (el negro de fábrica
  /// primero: es el que mejor lee el texto sobre una foto).
  static const List<String> _fadeColors = [
    '#000000',
    '#0B0E17',
    '#1B2A4A',
    '#3A1E0B',
    '#C9A96E',
    '#FFFFFF',
  ];

  /// Cambia el color del velo en el diseño.
  void _setFadeColor(String hex) => setState(
    () => _d = _d.copyWith(card: _d.card.copyWith(imageFadeColor: hex)),
  );

  // (La rosa de 8 direcciones se retiró: el CÍRCULO de abajo ya fija la
  // dirección exacta, así que tener los dos era repetir el mismo ajuste.)

  /// Sombra de la foto, con dos PARADAS móviles como un degradado de Photoshop:
  /// fuerza del negro, dónde empieza a desvanecerse y dónde se apaga del todo.
  List<Widget> _photoShadowControls(
    SiteCardDesign c,
    void Function(SiteCardDesign) update,
  ) => [
    _slider(
      'Sombra de la foto (fuerza)',
      c.imageShadow,
      0,
      1,
      (v) => update(c.copyWith(imageShadow: v)),
      divisions: 20,
      valueLabel: c.imageShadow == 0
          ? 'sin sombra'
          : '${(c.imageShadow * 100).round()}%',
    ),
    if (c.imageShadow > 0) ...[
      _slider(
        'Dónde empieza el desvanecido',
        c.imageShadowStart.clamp(0, .95),
        0,
        .95,
        (v) => update(
          c.copyWith(
            imageShadowStart: v,
            // La sombra no puede terminar antes de empezar.
            imageShadowEnd: c.imageShadowEnd < v + .05
                ? (v + .05).clamp(0, 1)
                : c.imageShadowEnd,
          ),
        ),
        divisions: 19,
        valueLabel: '${(c.imageShadowStart * 100).round()}%',
      ),
      _slider(
        'Dónde se apaga del todo',
        c.imageShadowEnd.clamp(c.imageShadowStart + .05, 1),
        .05,
        1,
        (v) => update(c.copyWith(imageShadowEnd: v)),
        divisions: 19,
        valueLabel: '${(c.imageShadowEnd * 100).round()}%',
      ),
    ],
  ];

  /// Dirección del velo, con el CÍRCULO y sus grados (único control: la rosa de
  /// direcciones de antes se retiró porque repetía lo mismo).
  Widget _fadeAngleRow(
    SiteCardDesign c, {
    String title = 'Dirección del velo',
    String hint =
        'Gira el punto: 0° tapa por arriba, 90° por la derecha, '
        '180° por abajo. El punto tenue es la dirección de siempre.',
  }) {
    final scheme = Theme.of(context).colorScheme;
    final preset = (kFadeFromDeg[c.imageFadeFrom] ?? 180).round();
    final shown = c.imageFadeAngle < 0
        ? preset
        : c.imageFadeAngle.round().clamp(0, 359);
    void setAngle(int deg) => setState(() {
      _d = _d.copyWith(
        card: _d.card.copyWith(imageFadeAngle: deg.toDouble() % 360),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AngleDial(
              key: const ValueKey('design-fade-angle'),
              degrees: shown,
              ghost: preset,
              onChanged: setAngle,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Color del velo: muestras para tocar y, si hace falta, uno propio.
  Widget _fadeColorRow(SiteCardDesign c) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Color del velo',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              c.imageFadeColor.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ColorField(
          label: 'Un color propio',
          value: c.imageFadeColor,
          onChanged: _setFadeColor,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in _fadeColors)
              Tooltip(
                message: 'Velo $hex',
                child: InkWell(
                  key: ValueKey('design-fade-color-$hex'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => _setFadeColor(hex.toUpperCase()),
                  child: Container(
                    width: 34,
                    height: 30,
                    decoration: BoxDecoration(
                      color: hsHexColor(hex, Colors.black),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color:
                            c.imageFadeColor.toUpperCase() == hex.toUpperCase()
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width:
                            c.imageFadeColor.toUpperCase() == hex.toUpperCase()
                            ? 2.5
                            : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Vista previa del degradado: una foto de muestra con el MISMO velo que
  /// llega a la web (`site.js` → `hsPhotoFade`), así se prueba sin adivinar.
  Widget _fadePreview(SiteCardDesign c) {
    return ClipRRect(
      key: const ValueKey('design-fade-preview'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 116,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // "Foto" de muestra: una escena con cielo y suelo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF8FA9C4),
                    Color(0xFF6B7F94),
                    Color(0xFF2B3540),
                  ],
                ),
              ),
            ),
            hsPhotoFadeOverlay(
              c.imageFadeColor,
              c.imageFade,
              from: c.imageFadeFrom,
              angle: c.imageFadeAngle,
              shadow: c.imageShadow,
              shadowStart: c.imageShadowStart,
              shadowEnd: c.imageShadowEnd,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Text(
                    'Así se ve el texto sobre la foto',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sube la fuerza si no se lee · Vista previa',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'VISTA PREVIA',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: .8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra del FONDO del estilo `fade`: el color (o el degradado) que se verá
  /// donde la foto ya desapareció. Es el mismo que pintan la tarjeta y la web.
  Widget _cardBgPreview(SiteCardDesign c) {
    final scheme = Theme.of(context).colorScheme;
    final gradient = hsCardBgGradient(c);
    return Container(
      key: const ValueKey('design-card-bg'),
      height: 54,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gradient == null ? hsCardBgColor(c) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        c.cardBgGradient
            ? 'Fondo: ${c.cardBgFrom.toUpperCase()} → '
                  '${c.cardBgTo.toUpperCase()} · ${c.cardBgAngle.round()}°'
            : 'Fondo: ${c.cardBgFrom.toUpperCase()}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: .9),
        ),
      ),
    );
  }

  /// Marcador de la FOTO del paquete. El panel no carga las fotos del sitio
  /// (son rutas de la web), así que aquí se enseña DÓNDE va y cuánto ocupa.
  Widget _photoFill(Color accent) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: .28),
          Colors.black.withValues(alpha: .35),
        ],
      ),
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_outlined,
          size: 22,
          color: accent.withValues(alpha: .9),
        ),
        const SizedBox(height: 4),
        Text(
          'Foto del paquete',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: accent.withValues(alpha: .9),
          ),
        ),
      ],
    ),
  );

  Widget _photoBand(Color accent, double height) => SizedBox(
    height: height,
    width: double.infinity,
    child: _photoFill(accent),
  );

  /// Miniatura de la foto para la fila: solo el icono (el rótulo no cabe).
  Widget _photoThumb(Color accent) => Container(
    width: 46,
    height: 52,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: .26),
          Colors.black.withValues(alpha: .35),
        ],
      ),
    ),
    child: Icon(
      Icons.image_outlined,
      size: 17,
      color: accent.withValues(alpha: .9),
    ),
  );

  /// Envuelve el contenido de la tarjeta o la fila con la foto de fondo: la
  /// foto se ve y ENCIMA va el velo del diseño (el mismo de la web y del
  /// módulo Paquetes), que es lo que deja leer el texto sin apagar la foto.
  Widget _withBackgroundPhoto(Color accent, Widget content) {
    final c = _d.card;
    if (c.imageMode == 'fade') {
      // La foto (aquí su marcador) se desvanece hacia el fondo de la tarjeta,
      // que pinta el contenedor: no hay velo encima.
      return Stack(
        children: [
          Positioned.fill(
            child: hsPhotoFadeMask(
              from: c.imageFadeFrom,
              angle: c.imageFadeAngle,
              start: c.imageFadeStart,
              end: c.imageFadeEnd,
              child: _photoFill(accent),
            ),
          ),
          content,
        ],
      );
    }
    if (c.imageMode != 'bg') return content;
    return Stack(
      children: [
        Positioned.fill(child: _photoFill(accent)),
        Positioned.fill(
          child: hsPhotoFadeOverlay(
            c.imageFadeColor,
            c.imageFade,
            from: c.imageFadeFrom,
            angle: c.imageFadeAngle,
            shadow: c.imageShadow,
            shadowStart: c.imageShadowStart,
            shadowEnd: c.imageShadowEnd,
          ),
        ),
        content,
      ],
    );
  }

  Widget _previewCard() {
    final c = _d.card;
    final t = _d.tierOf(_previewTier);
    final sample = _sample;
    final accent = hsHexColor(t.accent);
    final accentSoft = hsHexColor(t.accentSoft);
    final shown = c.servicesLimit == 0
        ? _sampleServices.length
        : _sampleServices.length.clamp(0, c.servicesLimit);
    // En el estilo `fade` el fondo lo elige el diseño (color o degradado).
    final bgGradient = c.imageMode == 'fade' ? hsCardBgGradient(c) : null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgGradient != null
            ? null
            : c.imageMode == 'fade'
            ? hsCardBgColor(c)
            : hsHexColor(t.dark),
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(c.radius),
        border: Border.all(
          color: c.borderWidth <= 0
              ? Colors.transparent
              : accent.withValues(alpha: t.borderAlpha),
          width: c.borderWidth,
        ),
      ),
      child: _withBackgroundPhoto(
        accent,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La foto va en banda ARRIBA, antes de la línea del flyer.
            if (c.imageMode == 'top') _photoBand(accent, c.imageHeight),
            if (c.lineTop)
              Container(
                height: 2.2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      accentSoft,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(c.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: t.badgeFilled
                          ? LinearGradient(colors: [accent, accentSoft])
                          : null,
                      color: t.badgeFilled
                          ? null
                          : accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6),
                      border: t.badgeFilled
                          ? null
                          : Border.all(color: accent.withValues(alpha: .35)),
                    ),
                    child: Text(
                      _previewTier.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: t.badgeFilled ? hsHexColor(t.dark) : accentSoft,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (c.showCategory) ...[
                    Row(
                      children: [
                        Text(
                          hsCategoryIcon(sample.category),
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sample.category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w700,
                            color: accent.withValues(alpha: .85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    c.uppercaseNames ? sample.name.toUpperCase() : sample.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                      fontFamily: c.serifNames ? 'serif' : null,
                    ),
                  ),
                  if (c.showSubtitle) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Cobertura completa del evento',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withValues(alpha: .55),
                      ),
                    ),
                  ],
                  if (c.showServices) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: .07),
                    ),
                    const SizedBox(height: 10),
                    if (c.showServiceCount)
                      Text(
                        '${_sampleServices.length} servicios incluidos',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: .45),
                        ),
                      ),
                    const SizedBox(height: 6),
                    ..._sampleServices
                        .take(shown)
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withValues(
                                        alpha: .78,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    if (shown < _sampleServices.length)
                      Text(
                        '+${_sampleServices.length - shown} más…',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: .4),
                        ),
                      ),
                  ],
                  if (c.showPrice || c.showCta) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (c.showPrice)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.priceLabel,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 1.5,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white.withValues(alpha: .45),
                                  ),
                                ),
                                Text(
                                  sample.price,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                    fontFamily: 'serif',
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          const Spacer(),
                        if (c.showCta)
                          // El CTA es el MISMO de la tarjeta del panel: pastilla
                          // con el tinte del acento (antes era un botón con
                          // borde y MAYÚSCULAS, la diferencia más visible).
                          FilledButton(
                            onPressed: () {},
                            style: FilledButton.styleFrom(
                              backgroundColor: accent.withValues(alpha: .18),
                              foregroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: Text(c.ctaLabel),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow() {
    final c = _d.card;
    final t = _d.tierOf(_previewTier);
    final accent = hsHexColor(t.accent);
    final sample = _sample;
    final bgGradient = c.imageMode == 'fade' ? hsCardBgGradient(c) : null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgGradient != null
            ? null
            : c.imageMode == 'fade'
            ? hsCardBgColor(c)
            : hsHexColor(t.dark),
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(c.radius.clamp(6, 20)),
        border: Border.all(
          color: c.borderWidth <= 0
              ? Colors.transparent
              : accent.withValues(alpha: t.borderAlpha),
          width: c.borderWidth,
        ),
      ),
      child: _withBackgroundPhoto(
        accent,
        Row(
          children: [
            Container(width: 3, height: 72, color: accent),
            // La foto, cuando va en banda, se asoma también en la fila.
            if (c.imageMode == 'top')
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _photoThumb(accent),
              ),
            const SizedBox(width: 14),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                hsCategoryIcon(sample.category),
                style: const TextStyle(fontSize: 17),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                      color: accent.withValues(alpha: .9),
                    ),
                  ),
                  Text(
                    c.uppercaseNames ? sample.name.toUpperCase() : sample.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: c.serifNames ? 'serif' : null,
                    ),
                  ),
                ],
              ),
            ),
            if (c.showPrice) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    c.priceLabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.white.withValues(alpha: .45),
                    ),
                  ),
                  Text(
                    sample.price,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      fontFamily: 'serif',
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
            ],
            if (c.showCta)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Controles base
  // ---------------------------------------------------------------

  /// Chips de opciones exclusivas (foto, animación): un toque, una elección.
  Widget _optionChips(
    String label,
    Map<String, String> options,
    String value,
    ValueChanged<String> onChanged, {
    String prefix = '',
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in options.entries)
              InkWell(
                key: ValueKey('$prefix-${e.key}'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: value == e.key
                        ? scheme.primary.withValues(alpha: .16)
                        : scheme.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: value == e.key
                          ? scheme.primary.withValues(alpha: .6)
                          : _line(scheme),
                    ),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: value == e.key
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: value == e.key
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _group(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
    String? valueLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              ),
              Text(
                valueLabel ?? value.round().toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 12.5)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Campo de color: muestra el color, permite escribir `#RRGGBB` y elegir de la
/// paleta. Sin dependencias externas.
class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  /// Abre la PALETA y aplica lo elegido aquí y en el diseño (sin esto, el
  /// cuadrito de color era un adorno: no se podía tocar y "no salía la paleta").
  Future<void> _openPalette() async {
    final picked = await showHsColorPalette(
      context,
      value: widget.value,
      title: widget.label,
    );
    if (picked == null) return;
    widget.onChanged(picked);
    setState(() {
      _c.text = picked;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    });
  }

  @override
  void didUpdateWidget(covariant _ColorField old) {
    super.didUpdateWidget(old);
    // Si el valor cambió por fuera (preset, otro campo), se refleja aquí.
    if (widget.value != old.value && widget.value != _c.text) {
      _c.text = widget.value;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Tooltip(
              message: 'Abrir la paleta de colores',
              child: InkWell(
                key: ValueKey('design-color-swatch-${widget.label}'),
                borderRadius: BorderRadius.circular(9),
                onTap: _openPalette,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: hsHexColor(widget.value),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _line(scheme)),
                    boxShadow: [
                      BoxShadow(
                        color: hsHexColor(widget.value).withValues(alpha: .35),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _c,
                decoration: InputDecoration(
                  isDense: true,
                  suffixIcon: IconButton(
                    key: ValueKey('design-color-palette-${widget.label}'),
                    tooltip: 'Paleta de colores',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openPalette,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                  ),
                ),
                onChanged: (v) => widget.onChanged(v.trim()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _line(ColorScheme s) => s.outlineVariant.withValues(alpha: .7);
}

// ==================================================================
// PALETA DE COLORES
// ==================================================================

/// Abre la PALETA de colores y devuelve el hex elegido (`#RRGGBB`), o null si
/// se canceló. Se usa desde todos los campos de color del diseñador.
Future<String?> showHsColorPalette(
  BuildContext context, {
  required String value,
  String title = 'Elegir color',
}) => showHsModal<String>(
  context: context,
  builder: (_) => _ColorPaletteDialog(title: title, initial: value),
);

class _ColorPaletteDialog extends StatefulWidget {
  const _ColorPaletteDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_ColorPaletteDialog> createState() => _ColorPaletteDialogState();
}

class _ColorPaletteDialogState extends State<_ColorPaletteDialog> {
  late HSVColor _hsv = HSVColor.fromColor(
    hsHexColor(widget.initial, Colors.black),
  );
  late final TextEditingController _c = TextEditingController(
    text: hsColorHex(_hsv.toColor()),
  );

  String get _hex => hsColorHex(_hsv.toColor());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(HSVColor next) {
    setState(() {
      _hsv = next;
      _c.text = hsColorHex(next.toColor());
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.palette_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.title, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // El color que se está eligiendo, en grande y con su hex.
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      decoration: const InputDecoration(
                        labelText: 'Código',
                        isDense: true,
                        hintText: '#C9A96E',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: _typed,
                      onChanged: (v) {
                        // Se aplica al escribir un hex completo (7 caracteres).
                        if (v.trim().length == 7) _typed(v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Muestras',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final hex in kColorSwatches) _swatch(hex, scheme),
                ],
              ),
              const SizedBox(height: 18),
              _gradientSlider(
                'Matiz',
                _hsv.hue,
                0,
                360,
                const [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
                (v) => _set(_hsv.withHue(v)),
                '${_hsv.hue.round()}°',
              ),
              _gradientSlider(
                'Saturación',
                _hsv.saturation,
                0,
                1,
                [
                  HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
                  HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
                ],
                (v) => _set(_hsv.withSaturation(v)),
                '${(_hsv.saturation * 100).round()}%',
              ),
              _gradientSlider(
                'Brillo',
                _hsv.value,
                0,
                1,
                [
                  Colors.black,
                  HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
                ],
                (v) => _set(_hsv.withValue(v)),
                '${(_hsv.value * 100).round()}%',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hex),
          child: const Text('Usar color'),
        ),
      ],
    );
  }

  /// Un hex escrito a mano: si es válido, se adopta.
  void _typed(String raw) {
    final t = raw.trim();
    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(t)) return;
    final c = hsHexColor(t, Colors.transparent);
    if (c == Colors.transparent && !t.toUpperCase().endsWith('000000')) return;
    _set(HSVColor.fromColor(c));
  }

  /// Muestra de la paleta: un toque la elige y cierra.
  Widget _swatch(String hex, ColorScheme scheme) {
    final color = hsHexColor(hex, Colors.black);
    final selected = hex.toUpperCase() == _hex.toUpperCase();
    return Tooltip(
      message: hex,
      child: InkWell(
        key: ValueKey('design-palette-$hex'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).pop(hex.toUpperCase()),
        child: Container(
          width: 32,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }

  /// Slider con la BARRA de degradado detrás (matiz, saturación, brillo).
  Widget _gradientSlider(
    String label,
    double value,
    double min,
    double max,
    List<Color> colors,
    ValueChanged<double> onChanged,
    String valueLabel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 11.5)),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(colors: colors),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .6),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: scheme.onSurface.withValues(alpha: .12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// DIAL DEL ÁNGULO
// ==================================================================

/// Círculo con el ÁNGULO del velo: se arrastra el punto del borde (o se toca
/// dentro) y los grados se leen en el centro. 0° tapa arriba, 90° a la derecha
/// y 180° abajo, los mismos grados que guarda el diseño y aplica la web.
class _AngleDial extends StatefulWidget {
  const _AngleDial({
    super.key,
    required this.degrees,
    required this.ghost,
    required this.onChanged,
  });

  /// Ángulo actual (0..359).
  final int degrees;

  /// Dirección de siempre (la del diseño guardado): se marca en tenue para
  /// saber hacia dónde miraba antes de girar el punto.
  final int ghost;

  final ValueChanged<int> onChanged;

  @override
  State<_AngleDial> createState() => _AngleDialState();
}

class _AngleDialState extends State<_AngleDial> {
  static const double _size = 148;

  /// Grados CSS del punto tocado: 0 arriba, 90 a la derecha…
  void _pick(Offset local) {
    const center = Offset(_size / 2, _size / 2);
    final v = local - center;
    // El centro no tiene dirección: tocarlo no manda el ángulo a 0.
    if (v.distance < 16) return;
    final deg = (math.atan2(v.dx, -v.dy) * 180 / math.pi + 360) % 360;
    widget.onChanged(deg.round() % 360);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _size,
      height: _size,
      // El arrastre se sigue con `Listener` (recibe TODOS los eventos del
      // puntero, también cuando el dedo va en vertical) y el `GestureDetector`
      // se queda con el gesto para que la lista de controles NO se desplace
      // mientras se gira el punto.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition),
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        child: Listener(
          onPointerDown: (e) => _pick(e.localPosition),
          onPointerMove: (e) => _pick(e.localPosition),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(_size, _size),
                painter: _AngleDialPainter(
                  degrees: widget.degrees,
                  ghost: widget.ghost,
                  accent: scheme.primary,
                  ring: scheme.outlineVariant.withValues(alpha: .55),
                  muted: scheme.onSurfaceVariant,
                ),
              ),
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.degrees}°',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'arrastra',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asas para mover A MANO las dos paradas del desvanecido negro sobre la
/// tarjeta de la vista previa: se arrastran hacia arriba o hacia abajo y el
/// degradado se rehace al momento (como los tiradores de un degradado de
/// Photoshop). «inicio» es dónde el negro deja de ser sólido y «fin» dónde se
/// apaga del todo.
class _ShadowStops extends StatefulWidget {
  const _ShadowStops({
    required this.start,
    required this.end,
    required this.onChanged,
    required this.child,
    this.keyStart = const ValueKey('design-shadow-start'),
    this.keyEnd = const ValueKey('design-shadow-end'),
    this.labelStart = 'inicio',
    this.labelEnd = 'fin',
  });

  final double start;
  final double end;
  final void Function(double start, double end) onChanged;
  final Widget child;

  /// Nombres de las asas (el desvanecido de la foto usa las mismas).
  final Key keyStart;
  final Key keyEnd;
  final String labelStart;
  final String labelEnd;

  @override
  State<_ShadowStops> createState() => _ShadowStopsState();
}

class _ShadowStopsState extends State<_ShadowStops> {
  final GlobalKey _box = GlobalKey();

  /// Alto REAL de la tarjeta (para pasar de píxeles a fracción).
  double get _height {
    final h = _box.currentContext?.size?.height;
    return (h == null || h <= 0) ? 560 : h;
  }

  void _drag({required bool isStart, required double dy}) {
    final delta = dy / _height;
    if (isStart) {
      widget.onChanged(
        (widget.start - delta).clamp(0.0, widget.end - .05),
        widget.end,
      );
    } else {
      widget.onChanged(
        widget.start,
        (widget.end - delta).clamp(widget.start + .05, 1.0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _box,
      children: [
        widget.child,
        // La capa de asas ocupa la tarjeta entera; el `Align` traduce la
        // fracción (0 abajo, 1 arriba) a la posición en el alto de la tarjeta.
        Positioned.fill(
          child: Stack(
            children: [
              Align(
                alignment: Alignment(0, 1 - 2 * widget.end),
                child: _handle(
                  key: widget.keyEnd,
                  label: widget.labelEnd,
                  onDrag: (dy) => _drag(isStart: false, dy: dy),
                ),
              ),
              Align(
                alignment: Alignment(0, 1 - 2 * widget.start),
                child: _handle(
                  key: widget.keyStart,
                  label: widget.labelStart,
                  onDrag: (dy) => _drag(isStart: true, dy: dy),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _handle({
    required Key key,
    required String label,
    required void Function(double dy) onDrag,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // La línea delata dónde queda la parada sobre la tarjeta.
              Expanded(
                child: Container(
                  height: 1.5,
                  color: scheme.primary.withValues(alpha: .55),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 6, right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .62),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .75),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.drag_handle_rounded,
                      size: 13,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AngleDialPainter extends CustomPainter {
  _AngleDialPainter({
    required this.degrees,
    required this.ghost,
    required this.accent,
    required this.ring,
    required this.muted,
  });

  final int degrees;
  final int? ghost;
  final Color accent;
  final Color ring;
  final Color muted;

  Offset _dir(int deg) {
    final rad = deg * math.pi / 180;
    return Offset(math.sin(rad), -math.cos(rad));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 12;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
    // Marcas cada 15°, más largas en los ejes (0/90/180/270).
    for (var a = 0; a < 360; a += 15) {
      final long = a % 45 == 0;
      final dir = _dir(a);
      canvas.drawLine(
        c + dir * (r - (long ? 9 : 5)),
        c + dir * (r - 1),
        Paint()
          ..strokeWidth = long ? 2 : 1
          ..color = ring,
      );
    }
    // Preset de la dirección, en tenue (solo cuando el ángulo es libre).
    final g = ghost;
    if (g != null) {
      canvas.drawCircle(
        c + _dir(g) * r,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = muted.withValues(alpha: .55),
      );
    }
    // Radio y mango del ángulo actual.
    final knob = c + _dir(degrees) * (r - 2);
    canvas.drawLine(
      c,
      knob,
      Paint()
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: .45),
    );
    canvas.drawCircle(knob, 9, Paint()..color = accent.withValues(alpha: .22));
    canvas.drawCircle(knob, 5.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_AngleDialPainter old) =>
      old.degrees != degrees ||
      old.ghost != ghost ||
      old.accent != accent ||
      old.ring != ring;
}

/// Campo de texto controlado (para textos que pueden cambiar desde fuera).
class _TextField extends StatefulWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _TextField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _c.text) {
      _c.text = widget.value;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _c,
    decoration: InputDecoration(labelText: widget.label, isDense: true),
    onChanged: widget.onChanged,
  );
}
