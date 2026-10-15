import 'package:flutter/material.dart';

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

const Map<String, String> kTierLabels = {
  'premium': 'Premium',
  'gold': 'Gold',
  'basic': 'Basic',
};

/// Abre el diseñador. Devuelve el diseño elegido (o null si se canceló).
Future<SiteDesign?> showPackageDesigner(
  BuildContext context, {
  required SiteDesign design,
}) =>
    showHsModal<SiteDesign>(
      context: context,
      builder: (_) => _PackageDesigner(initial: design),
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
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _d = SiteDesign.defaults),
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
                  Icon(Icons.cloud_done_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al guardar, la página web lo aplica al instante '
                      '(no hay que publicar el sitio).',
                      style:
                          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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

  Widget _hr(ColorScheme s) =>
      Divider(height: 1, color: _line(s));

  Color _line(ColorScheme s) =>
      s.outlineVariant.withValues(alpha: .5);

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
      onTap: () => setState(() => _tab = key),
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
      _slider('Separación', c.gap, 0, 80, (v) => update(c.copyWith(gap: v)),
          valueLabel: '${c.gap.round()} px'),
      const SizedBox(height: 18),
      _group('Tarjeta'),
      _slider('Redondeo', c.radius, 0, 40, (v) => update(c.copyWith(radius: v)),
          valueLabel: '${c.radius.round()} px'),
      _slider('Borde', c.borderWidth, 0, 6,
          (v) => update(c.copyWith(borderWidth: v)),
          valueLabel: '${c.borderWidth.round()} px'),
      _slider('Relleno', c.padding, 8, 56,
          (v) => update(c.copyWith(padding: v)),
          valueLabel: '${c.padding.round()} px'),
      _switch('Línea superior', c.lineTop,
          (v) => update(c.copyWith(lineTop: v))),
      _switch('Se eleva al pasar el mouse', c.hoverLift,
          (v) => update(c.copyWith(hoverLift: v))),
      _switch('Sombra al pasar el mouse', c.shadow,
          (v) => update(c.copyWith(shadow: v))),
      const SizedBox(height: 18),
      _group('Tipografía del nombre'),
      _switch('Serif (Playfair)', c.serifNames,
          (v) => update(c.copyWith(serifNames: v))),
      _switch('MAYÚSCULAS', c.uppercaseNames,
          (v) => update(c.copyWith(uppercaseNames: v))),
      const SizedBox(height: 18),
      _group('Qué se muestra'),
      _switch('Categoría', c.showCategory,
          (v) => update(c.copyWith(showCategory: v))),
      _switch('Subtítulo', c.showSubtitle,
          (v) => update(c.copyWith(showSubtitle: v))),
      _switch('Cuántos servicios', c.showServiceCount,
          (v) => update(c.copyWith(showServiceCount: v))),
      _switch('Lista de servicios', c.showServices,
          (v) => update(c.copyWith(showServices: v))),
      _switch('Precio', c.showPrice,
          (v) => update(c.copyWith(showPrice: v))),
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
      _switch('Badge relleno (degradado)', t.badgeFilled,
          (v) => _d = _d.withTier(key, t.copyWith(badgeFilled: v))),
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
              onChanged: (v) => _d = _d.withTier(key, t.copyWith(accentSoft: v)),
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
      _group('Paletas listas'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in kDesignPresets)
            Tooltip(
              message: 'Acento ${p[0]}',
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
                    color: hsHexColor(p[2]),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hsHexColor(p[0]), width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: hsHexColor(p[0]),
                        shape: BoxShape.circle,
                      ),
                    ),
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
                label: Text('Igual que ${kTierLabels[key]} → ${kTierLabels[k]}'),
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
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _previewCard(),
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
            'borde: ${c.borderWidth <= 0 ? 'sin borde' : '${c.borderWidth.round()} px'}',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static const _sampleServices = ['Cobertura', 'Álbum impreso', 'Video', 'Galería online'];

  Widget _previewCard() {
    final c = _d.card;
    final t = _d.tierOf('premium');
    final accent = hsHexColor(t.accent);
    final accentSoft = hsHexColor(t.accentSoft);
    final shown = c.servicesLimit == 0
        ? _sampleServices.length
        : _sampleServices.length.clamp(0, c.servicesLimit);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hsHexColor(t.dark),
        borderRadius: BorderRadius.circular(c.radius),
        border: Border.all(
          color: c.borderWidth <= 0
              ? Colors.transparent
              : accent.withValues(alpha: t.borderAlpha),
          width: c.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.lineTop)
            Container(
              height: 2.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, accentSoft, Colors.transparent],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(c.padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: t.badgeFilled
                        ? LinearGradient(colors: [accent, accentSoft])
                        : null,
                    color: t.badgeFilled ? null : accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6),
                    border: t.badgeFilled
                        ? null
                        : Border.all(color: accent.withValues(alpha: .35)),
                  ),
                  child: Text(
                    'PREMIUM',
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
                      Text(hsCategoryIcon('Bodas'),
                          style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Text(
                        'BODAS',
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
                  c.uppercaseNames ? 'BODA FULL' : 'Boda Full',
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
                  Divider(height: 1, color: Colors.white.withValues(alpha: .07)),
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
                  ..._sampleServices.take(shown).map(
                        (s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.check_rounded, size: 15, color: accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white.withValues(alpha: .78),
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
                                '\$25,000',
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
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentSoft,
                            side: BorderSide(color: accent.withValues(alpha: .75)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(c.ctaLabel.toUpperCase()),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewRow() {
    final c = _d.card;
    final t = _d.tierOf('gold');
    final accent = hsHexColor(t.accent);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hsHexColor(t.dark),
        borderRadius: BorderRadius.circular(c.radius.clamp(6, 20)),
        border: Border.all(
          color: c.borderWidth <= 0
              ? Colors.transparent
              : accent.withValues(alpha: t.borderAlpha),
          width: c.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 72, color: accent),
          const SizedBox(width: 14),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(hsCategoryIcon('XV Años'),
                style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'XV AÑOS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: accent.withValues(alpha: .9),
                  ),
                ),
                Text(
                  c.uppercaseNames ? 'XV AÑOS GOLD' : 'XV Años Gold',
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
                  '\$18,000',
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
              child: Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Controles base
  // ---------------------------------------------------------------

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
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

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
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hsHexColor(widget.value),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line(scheme)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _c,
                decoration: const InputDecoration(isDense: true),
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
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

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
