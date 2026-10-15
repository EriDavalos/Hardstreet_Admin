import 'package:flutter/material.dart';

import '../web_sections.dart';

// ==================================================================
// HARD STREET ADMIN — MINIATURA DE UNA SECCIÓN DEL SITIO
// ==================================================================
// El módulo "Sitio web" muestra cada sección como una tarjeta con su
// PREVISUALIZACIÓN: un dibujo en miniatura de cómo se ve esa parte de la
// página con lo que hay escrito ahora (textos, imágenes y opciones).
//
// Es la MISMA información que aplica la web (`site.js`): los valores que
// llegan aquí ya vienen mezclados con los de fábrica, así que la miniatura
// nunca miente sobre lo que se va a publicar.
// ==================================================================

/// Miniatura de una sección. `values` e `images` vienen ya resueltos (lo
/// editado, o el valor de fábrica del HTML).
class SiteSectionPreview extends StatelessWidget {
  const SiteSectionPreview({
    super.key,
    required this.section,
    required this.values,
    required this.images,
    required this.props,
    this.gold = const Color(0xFFC9A96E),
    this.height = 132,
  });

  /// Clave de la sección (`hero`, `about`…).
  final String section;
  final Map<String, String> values;
  final Map<String, String> images;
  final Map<String, dynamic> props;
  final Color gold;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: _body(scheme),
    );
  }

  Widget _body(ColorScheme scheme) {
    switch (section) {
      case 'hero':
        return _hero();
      case 'about':
        return _about(scheme);
      case 'gallery':
        return _gallery(scheme);
      case 'parallax':
        return _parallax();
      case 'services':
        return _services(scheme);
      case 'packages':
        return _packages(scheme);
      case 'testimonials':
        return _testimonials(scheme);
      case 'contact':
        return _contact(scheme);
      case 'footer':
        return _footer(scheme);
      case 'brand':
        return _brand(scheme);
      default:
        return Center(
          child: Text(
            siteSectionTemplate(section)?.label ?? section,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        );
    }
  }

  // ---------------- piezas comunes ----------------

  /// Texto con su valor actual (o el de fábrica si no se ha tocado).
  String _v(String key) => values[key] ?? '';

  /// Titular de dos líneas (`|` separa la segunda, que va en dorado).
  List<Widget> _titleLines(String raw, {double size = 13}) {
    final parts = raw.split('|');
    return [
      _line(parts[0].trim(), size: size),
      if (parts.length > 1) _line(parts.sublist(1).join('|').trim(), size: size, color: gold),
    ];
  }

  Widget _line(String text, {double size = 13, Color color = Colors.white}) =>
      Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          height: 1.25,
          color: color,
          fontWeight: FontWeight.w700,
          fontFamily: 'serif',
        ),
      );

  /// Etiqueta pequeña en dorado (las que van arriba de cada título).
  Widget _eyebrow(String text) => Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: gold,
        ),
      );

  /// Línea gris que representa un párrafo.
  Widget _textLine(ColorScheme scheme, {double width = 1, double height = 5}) =>
      FractionallySizedBox(
        widthFactor: width,
        alignment: Alignment.centerLeft,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );

  /// Imagen: la de verdad si es una URL accesible; si no, un marcador.
  ///
  /// [height] es obligatorio cuando el hueco NO tiene alto acotado (por
  /// ejemplo dentro de una fila alineada arriba).
  Widget _imageBox(
    String path, {
    double width = 40,
    double? height,
    IconData icon = Icons.image_outlined,
  }) {
    final url = path.trim();
    final remote = url.startsWith('http://') || url.startsWith('https://');
    return Container(
      width: width,
      height: height ?? double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: remote
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Icon(icon, size: 18, color: Colors.white38),
              ),
            )
          : Center(child: Icon(icon, size: 18, color: Colors.white38)),
    );
  }

  // ---------------- cada sección ----------------

  Widget _hero() => Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B2233), Color(0xFF0B0E17)],
              ),
            ),
          ),
          Positioned(
            right: -20,
            bottom: -24,
            child: Icon(Icons.camera_alt_outlined,
                size: 90, color: gold.withValues(alpha: .10)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eyebrow(_v('hero_eyebrow')),
                const SizedBox(height: 4),
                ..._titleLines(_v('hero_title')),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: gold.withValues(alpha: .7)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _v('hero_cta'),
                    style: TextStyle(fontSize: 9, color: gold, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _about(ColorScheme scheme) {
    final stats = siteStats(props);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _imageBox(_v('about_image'), width: 66),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _eyebrow(_v('about_label')),
                const SizedBox(height: 3),
                ..._titleLines(_v('about_title'), size: 11),
                const SizedBox(height: 6),
                _textLine(scheme),
                const SizedBox(height: 4),
                _textLine(scheme, width: .8),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final s in stats.take(3)) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.value}+',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: gold,
                              ),
                            ),
                            Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 7.5, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallery(ColorScheme scheme) {
    final cats = siteGalleryCategories(props);
    final photos = <String>[
      for (final c in cats) ...c.items,
    ];
    final shows = photos.isEmpty ? <String>[] : photos.take(6).toList();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(_v('gallery_label')),
          const SizedBox(height: 2),
          _line(_v('gallery_title'), size: 11),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip('Todos', scheme, active: true),
              const SizedBox(width: 4),
              for (final c in cats.take(3)) ...[
                _chip(c.name, scheme),
                const SizedBox(width: 4),
              ],
              if (cats.isEmpty) _chip('Categorías del catálogo', scheme),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: i < shows.length && _isHttp(shows[i])
                          ? Image.network(
                              shows[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _photoFallback(),
                            )
                          : _photoFallback(),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoFallback() => const Center(
        child: Icon(Icons.photo_outlined, size: 14, color: Colors.white24),
      );

  bool _isHttp(String v) => v.startsWith('http://') || v.startsWith('https://');

  Widget _chip(String label, ColorScheme scheme, {bool active = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? gold.withValues(alpha: .18) : Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? gold.withValues(alpha: .6) : Colors.white.withValues(alpha: .12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.w700,
            color: active ? gold : Colors.white60,
          ),
        ),
      );

  Widget _parallax() => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF161C2A), Color(0xFF090B12)],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _titleLines(_v('parallax_text'), size: 12),
              ),
            ),
          ),
        ],
      );

  Widget _services(ColorScheme scheme) {
    final perSlide = (props['servicesPerSlide'] as num?)?.toInt() ?? 4;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(_v('services_label')),
          const SizedBox(height: 2),
          _line(_v('services_title'), size: 11),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: gold.withValues(alpha: .22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.auto_awesome_outlined, size: 13, color: gold),
                          const SizedBox(height: 4),
                          _textLine(scheme, width: .9, height: 4),
                          const SizedBox(height: 3),
                          _textLine(scheme, width: .6, height: 4),
                          const Spacer(),
                          Text(
                            '$perSlide características',
                            style: const TextStyle(fontSize: 7.5, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (i == 0) const SizedBox(width: 6),
                ],
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 14, color: gold.withValues(alpha: .6)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: gold.withValues(alpha: .6)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _packages(ColorScheme scheme) {
    final grouped = props['groupByCategory'] != false;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(_v('packages_label')),
          const SizedBox(height: 2),
          _line(_v('packages_title'), size: 11),
          if (grouped) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Boda', style: TextStyle(fontSize: 9, color: gold, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Expanded(child: _textLine(scheme, height: 2)),
                const SizedBox(width: 6),
                const Text('3 paquetes', style: TextStyle(fontSize: 7, color: Colors.white38)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(child: _miniCard(scheme, i)),
                  if (i < 2) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(ColorScheme scheme, int i) {
    final accent = [gold, const Color(0xFFD9A441), const Color(0xFF8FB0D4)][i];
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ['Premium', 'Gold', 'Basic'][i],
              style: TextStyle(fontSize: 6.5, fontWeight: FontWeight.w800, color: accent),
            ),
          ),
          const SizedBox(height: 5),
          _textLine(scheme, width: .85, height: 4),
          const SizedBox(height: 3),
          _textLine(scheme, width: .55, height: 4),
          const Spacer(),
          Text(
            'Desde',
            style: TextStyle(fontSize: 6.5, color: accent.withValues(alpha: .9)),
          ),
        ],
      ),
    );
  }

  Widget _testimonials(ColorScheme scheme) {
    final items = siteTestimonials(props);
    final first = items.isEmpty ? null : items.first;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _eyebrow(_v('testimonials_label')),
          const SizedBox(height: 2),
          Center(child: _line(_v('testimonials_title'), size: 11)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: gold.withValues(alpha: .22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, size: 13, color: gold.withValues(alpha: .8)),
                  const SizedBox(height: 3),
                  Text(
                    first?.text.isNotEmpty == true
                        ? first!.text
                        : 'Los comentarios que escribas aquí se muestran en el carrusel.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5, height: 1.35, color: Colors.white70),
                  ),
                  const Spacer(),
                  Text(
                    first?.name.isNotEmpty == true
                        ? first!.name
                        : '${items.length} comentarios',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: gold),
                  ),
                  if (first != null && first.role.isNotEmpty)
                    Text(
                      first.role,
                      style: const TextStyle(fontSize: 7, color: Colors.white38),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contact(ColorScheme scheme) {
    final whatsapp = '${props['whatsapp'] ?? ''}'.trim();
    final rows = <(IconData, String)>[
      (Icons.mail_outline, _v('contact_email')),
      (Icons.call_outlined, _v('contact_phone')),
      (Icons.place_outlined, _v('contact_address')),
      if (whatsapp.isNotEmpty) (Icons.chat_outlined, 'WhatsApp'),
    ];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(_v('contact_label')),
          const SizedBox(height: 2),
          _line(_v('contact_title'), size: 11),
          const SizedBox(height: 6),
          for (final r in rows.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Icon(r.$1, size: 10, color: gold),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      r.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8.5, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          Container(
            height: 16,
            decoration: BoxDecoration(
              border: Border.all(color: gold.withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                _v('contact_cta'),
                style: TextStyle(fontSize: 7.5, color: gold, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _imageBox(_v('footer_logo'),
                width: 26, height: 60, icon: Icons.branding_watermark_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _v('footer_about'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8, height: 1.4, color: Colors.white54),
                  ),
                  const Spacer(),
                  Container(height: 1, color: Colors.white.withValues(alpha: .08)),
                  const SizedBox(height: 5),
                  Text(
                    _v('footer_copyright'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 7, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _brand(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _imageBox(_v('logo'), width: 60, height: 46, icon: Icons.image_outlined),
                  const SizedBox(height: 6),
                  const Text('Barra', style: TextStyle(fontSize: 8, color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  _imageBox(_v('footer_logo'), width: 60, height: 46, icon: Icons.image_outlined),
                  const SizedBox(height: 6),
                  const Text('Pie', style: TextStyle(fontSize: 8, color: Colors.white54)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// El dorado del diseño (`#RRGGBB`) como color de Flutter.
///
/// Si el valor viene raro (o vacío), se usa el dorado de la marca: la
/// miniatura NUNCA se queda sin color.
Color sitePreviewGold(String hex) {
  var clean = hex.replaceAll('#', '').trim();
  if (clean.length == 3) {
    clean = clean.split('').map((c) => '$c$c').join();
  }
  final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
  if (value == null) return const Color(0xFFC9A96E);
  return Color(0xFF000000 | value);
}


