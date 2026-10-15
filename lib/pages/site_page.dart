import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../app_platform.dart';
import '../drive_base.dart';
import '../drive_scope.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../theme.dart';
import '../web_content.dart';
import '../web_sections.dart';
import '../widgets/common.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';
import '../widgets/site_section_preview.dart';

// ==================================================================
// MÓDULO SITIO WEB — diseñador por SECCIONES (por ahora SOLO WINDOWS)
// ==================================================================
// La portada está partida en secciones (Portada, Sobre nosotros, Galería,
// Divisor, Lo que ofrecemos, Paquetes, Testimonios, Contacto, Pie y Marca).
// Cada sección es una TARJETA con su MINIATURA (cómo se ve en la página con lo
// que hay escrito ahora) y, debajo, sus campos:
//
//   * Textos e imágenes → ganchos del HTML (`data-hs`, `data-hs-img`).
//   * Opciones propias   → `props` de la sección: los números de "Sobre
//     nosotros", las fotos de cada categoría de la galería, los comentarios de
//     los clientes, el WhatsApp…
//
// Las PLANTILLAS (qué campos tiene cada sección y con qué valores viene de
// fábrica) viven en `web_sections.dart`; el catálogo de ganchos, en
// `web_content.dart`. Agregar una sección nueva al sitio = agregar su plantilla
// y sus ganchos en el HTML: el módulo la pinta sola.
//
// Todo lo que se guarda va a `site_config.landing` (PUT /api/admin/site) y la
// web lo aplica EN VIVO al cargar (`gallery/assets/site.js`): no hay que volver
// a publicar el sitio.
//
// ¿QUÉ SE GUARDA? Depende de la base:
//   * base VACÍA → sólo los campos CAMBIADOS; lo que se deje como viene de
//     fábrica sigue leyéndose del HTML del sitio. El módulo lo AVISA y ofrece
//     "Guardar lo actual en la base" (sube TODO el contenido actual).
//   * base CON CONTENIDO → la base manda: cada guardado manda el documento
//     COMPLETO (textos, imágenes, opciones, orden y visibilidad), porque lo que
//     no viajara en ese guardado desaparecería del sitio.
// ==================================================================

/// ¿Se puede usar el módulo en esta plataforma? (por ahora, Windows)
bool siteModuleSupported() => isWindowsPlatform;

/// Lo que el módulo necesita saber ADEMÁS del contenido guardado: las
/// categorías del catálogo (para armar la galería) y el dorado del diseño.
class SiteContext {
  const SiteContext({
    this.categories = const [],
    this.gold = '#C9A96E',
    this.stored = false,
  });

  /// Categorías de paquetes: clave CSS + nombre.
  final List<({String key, String name})> categories;
  final String gold;

  /// ¿La base de datos ya tiene guardado el contenido de la portada?
  ///
  /// Si NO (fila vacía o migración sin aplicar), la web está usando lo que
  /// trae su propio HTML: el módulo lo avisa y ofrece subirlo a la base.
  final bool stored;
}

/// Acceso al contenido del sitio (textos, imágenes y opciones por sección).
abstract class SiteContentApi {
  Future<SiteContent> load();
  Future<void> save(SiteContent content);

  /// Categorías del catálogo y dorado del diseño (con respaldo si fallan).
  Future<SiteContext> context();
}

/// La implementación real: GET/PUT /api/admin/site (documento `landing`).
class HsSiteContentApi implements SiteContentApi {
  const HsSiteContentApi();

  @override
  Future<SiteContent> load() async =>
      SiteContent.fromJsonText((await HsApi.siteDesign()).landing);

  @override
  Future<void> save(SiteContent content) => HsApi.saveSiteContent(content);

  @override
  Future<SiteContext> context() async {
    // Las categorías son del catálogo de paquetes (packages_categories) y el
    // dorado, del diseño de las tarjetas: los dos son opcionales, así que si
    // fallan se sigue con lo de fábrica en vez de romper el módulo.
    List<({String key, String name})> categories = const [];
    var gold = '#C9A96E';
    var stored = false;
    try {
      final cats = await HsApi.packageCategories();
      categories = [
        for (final c in cats)
          if ('${c['name'] ?? ''}'.trim().isNotEmpty)
            (key: siteCategoryKey('${c['name']}'), name: '${c['name']}'.trim()),
      ];
    } catch (_) {
      // Sin categorías se puede editar todo lo demás.
    }
    try {
      final site = await HsApi.siteDesign();
      gold = site.design.gold;
      // Con la base vacía la web se pinta con su HTML; con contenido guardado,
      // la base manda (y por eso cada guardado vuelve a mandar todo).
      stored = site.landing != null && site.landing!.isNotEmpty;
    } catch (_) {
      // Sin diseño, el dorado de la marca.
    }
    return SiteContext(categories: categories, gold: gold, stored: stored);
  }
}

class SitePage extends StatefulWidget {
  const SitePage({
    super.key,
    this.api = const HsSiteContentApi(),
    this.supported,
  });

  /// Cómo se lee y se guarda el contenido (en pruebas, un doble).
  final SiteContentApi api;

  /// Fuerza si el módulo es usable (por defecto, según la plataforma).
  final bool? supported;

  @override
  State<SitePage> createState() => _SitePageState();
}

class _SitePageState extends State<SitePage> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  /// Lo último que se guardó (para saber si hay cambios sin guardar).
  SiteContent _saved = SiteContent.empty;

  /// Controles de edición (texto e imagen) por clave de gancho.
  final Map<String, TextEditingController> _texts = {};
  final Map<String, TextEditingController> _images = {};

  /// Opciones de cada sección (ya mezcladas con las de fábrica).
  final Map<String, Map<String, dynamic>> _props = {};

  /// Secciones que se pueden mover, en el orden que el usuario ve.
  List<String> _order = [];

  /// Visibilidad elegida por sección.
  final Map<String, bool> _visible = {};

  /// Tarjetas abiertas (las que muestran sus campos).
  final Set<String> _open = <String>{};

  /// Categorías del catálogo (para la galería) y dorado del diseño.
  List<({String key, String name})> _categories = const [];
  String _gold = '#C9A96E';

  /// ¿La base de datos ya tiene el contenido de la portada?
  ///
  /// Con la base vacía se guarda SÓLO lo cambiado (lo demás lo sigue leyendo
  /// del HTML del sitio); en cuanto hay contenido guardado, la base manda y
  /// cada guardado vuelve a mandar el documento COMPLETO (si no, lo que no se
  /// tocara en esa sesión desaparecería).
  bool _stored = false;

  Color get _goldColor => sitePreviewGold(_gold);

  @override
  void initState() {
    super.initState();
    for (final f in kSiteTexts) {
      _texts[f.key] = TextEditingController();
    }
    for (final f in kSiteImages) {
      _images[f.key] = TextEditingController();
    }
    _resetProps();
    _resetSections();
    _load();
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final c in _images.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Opciones de todas las secciones, con sus valores de fábrica.
  void _resetProps() {
    for (final t in kSiteSectionTemplates) {
      _props[t.key] = _mutableProps(t.key, null);
    }
  }

  /// Opciones de una sección COPIADAS (listas mutables).
  ///
  /// Los valores de fábrica son `const`: si se editaran tal cual, se estaría
  /// escribiendo sobre la plantilla. Aquí se clona lo que sea una lista para
  /// que los editores (números, testimonios, galería) trabajen sobre copias.
  Map<String, dynamic> _mutableProps(String key, Map<String, dynamic>? raw) {
    final merged = siteSectionProps(key, raw);
    return <String, dynamic>{
      for (final e in merged.entries) e.key: _cloneValue(e.value),
    };
  }

  /// Copia PROFUNDA de un valor de opción (listas y mapas incluidos).
  ///
  /// Los valores de fábrica son `const`: si se editaran tal cual, se estaría
  /// escribiendo sobre la plantilla (y Dart lo prohibe). Aquí todo lo que sea
  /// lista o mapa se clona para que los editores trabajen sobre copias.
  Object? _cloneValue(Object? v) {
    if (v is List) return [for (final e in v) _cloneValue(e)];
    if (v is Map) {
      return <String, dynamic>{
        for (final e in v.entries) '${e.key}': _cloneValue(e.value),
      };
    }
    return v;
  }

  void _resetSections() {
    _order = kOrderableSectionTemplates.map((t) => t.key).toList();
    _visible
      ..clear()
      ..addEntries(
          kSiteSectionTemplates.map((t) => MapEntry(t.key, t.defaultVisible)));
  }

  // ---------------------------------------------------------------
  // Datos
  // ---------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await widget.api.load();
      final ctx = await widget.api.context();
      if (!mounted) return;
      setState(() {
        for (final f in kSiteTexts) {
          _texts[f.key]!.text = content.textOf(f.key) ?? '';
        }
        for (final f in kSiteImages) {
          _images[f.key]!.text = content.imageOf(f.key) ?? '';
        }
        _categories = ctx.categories;
        _gold = ctx.gold;
        _stored = ctx.stored;
        // Opciones: lo guardado pisa los valores de fábrica (y lo que no venga
        // se queda como viene, así una sección nueva nunca aparece vacía).
        for (final t in kSiteSectionTemplates) {
          _props[t.key] =
              _mutableProps(t.key, content.sections[t.key]?.props);
        }
        // Orden: primero las que tienen orden EXPLÍCITO (el documento guarda el
        // orden de todas, pero si llegara incompleto las colocadas a mano no se
        // descolocan), y luego las demás como vienen en el HTML.
        final stored = content.sections;
        final factory = {
          for (var i = 0; i < kOrderableSectionTemplates.length; i++)
            kOrderableSectionTemplates[i].key: i,
        };
        _order = kOrderableSectionTemplates.map((t) => t.key).toList()
          ..sort((a, b) {
            final oa = stored[a]?.order;
            final ob = stored[b]?.order;
            if (oa != null || ob != null) {
              final ra = oa ?? 1000 + factory[a]!;
              final rb = ob ?? 1000 + factory[b]!;
              if (ra != rb) return ra.compareTo(rb);
            }
            return factory[a]!.compareTo(factory[b]!);
          });
        _visible
          ..clear()
          ..addEntries(kSiteSectionTemplates.map((t) => MapEntry(
              t.key, stored[t.key]?.visible ?? t.defaultVisible)));
        // Recién cargado no hay nada "sin guardar": lo guardado se recuerda tal
        // como lo MANDARÍAMOS (con todas las secciones).
        _saved = _document(full: _stored);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el contenido del sitio';
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------
  // El documento que se guarda
  // ---------------------------------------------------------------

  /// El documento que se manda a la API.
  ///
  /// * `full: false` (base VACÍA) → sólo lo CAMBIADO: un valor vacío (o igual
  ///   al de fábrica) se omite y el sitio sigue leyendo su HTML.
  /// * `full: true` (la base ya tiene contenido, o se está importando) → TODO
  ///   el contenido actual: textos, imágenes, opciones, orden y visibilidad.
  ///   Es lo que hace que la web se pinte con lo que hay en la base.
  SiteContent _document({bool full = false}) {
    final texts = <String, String>{};
    for (final f in kSiteTexts) {
      final v = _texts[f.key]!.text.trim().isEmpty ? f.def : _texts[f.key]!.text.trim();
      if (full || v != f.def) texts[f.key] = v;
    }
    final images = <String, String>{};
    for (final f in kSiteImages) {
      final v = _images[f.key]!.text.trim().isEmpty ? f.def : _images[f.key]!.text.trim();
      if (full || v != f.def) images[f.key] = v;
    }
    final sections = <String, SiteSectionState>{};
    for (var i = 0; i < _order.length; i++) {
      final key = _order[i];
      final props = full
          ? {...siteSectionDefaults(key), ...(_props[key] ?? const {})}
          : _changedProps(key);
      sections[key] = SiteSectionState(
        visible: _visible[key] ?? true,
        order: i + 1,
        props: props,
      );
    }
    // Las secciones fijas (pie y marca) sólo viajan si se tocó su contenido.
    for (final t in kSiteSectionTemplates.where((t) => !t.orderable)) {
      final props = full
          ? {...siteSectionDefaults(t.key), ...(_props[t.key] ?? const {})}
          : _changedProps(t.key);
      if (props.isNotEmpty) {
        sections[t.key] = SiteSectionState(
          visible: _visible[t.key] ?? true,
          order: 0,
          props: props,
        );
      }
    }
    return SiteContent(texts: texts, images: images, sections: sections);
  }

  /// Opciones de una sección que DIFIEREN de las de fábrica.
  Map<String, dynamic> _changedProps(String key) {
    final current = _props[key] ?? const <String, dynamic>{};
    final defaults = siteSectionDefaults(key);
    final out = <String, dynamic>{};
    for (final e in current.entries) {
      final def = defaults[e.key];
      // Lista vacía o texto vacío = "sin cambios" (así no se guarda basura).
      final v = e.value;
      if (v is List && v.isEmpty && (def is List && def.isEmpty)) continue;
      if (v is String && v.trim().isEmpty && def is String && def.isEmpty) {
        continue;
      }
      if (jsonEncode(v) == jsonEncode(def)) continue;
      out[e.key] = v;
    }
    return out;
  }

  bool get _dirty => !_document(full: _stored).sameAs(_saved);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.save(_document(full: _stored));
      HsToast.success('Sitio web actualizado',
          details: 'La portada ya muestra los cambios.');
      await _load();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    } catch (_) {
      HsToast.error('No se pudo guardar el contenido del sitio');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sube a la base de datos TODO el contenido actual de la portada.
  ///
  /// Con la base vacía la web se pinta con su propio HTML (los valores de
  /// fábrica); a partir de aquí la base MANDA: los textos, las imágenes y las
  /// opciones se leen de ahí y cada guardado manda el documento completo.
  Future<void> _importToDb() async {
    final ok = await showHsModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Guardar el contenido en la base de datos?'),
        content: const Text(
          'Se guardan los textos, las imágenes y las opciones de TODAS las '
          'secciones tal como están ahora (incluidos los que todavía no has '
          'tocado). A partir de ahí la web se pinta con lo que hay en la base: '
          'los cambios se ven al instante, sin volver a publicar el sitio.\n\n'
          'Ten en cuenta que, con la base llena, lo que cambies en el HTML del '
          'sitio ya no se verá hasta actualizarlo también aquí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar en la base'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await widget.api.save(_document(full: true));
      HsToast.success('Contenido guardado en la base de datos',
          details: 'La web ya lo lee de ahí: se aplica al instante.');
      await _load();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    } catch (_) {
      HsToast.error('No se pudo guardar el contenido en la base de datos');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreAll() async {
    final ok = await showHsModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Volver al contenido original?'),
        content: const Text(
          'Los textos, las imágenes y las opciones de las secciones regresan a '
          'como vienen en el sitio. Todavía no se guarda: presiona "Guardar '
          'cambios".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      for (final c in _texts.values) {
        c.text = '';
      }
      for (final c in _images.values) {
        c.text = '';
      }
      _resetProps();
      _resetSections();
    });
  }

  void _move(String key, int delta) {
    final i = _order.indexOf(key);
    if (i < 0) return;
    final target = i + delta;
    if (target < 0 || target >= _order.length) return;
    setState(() {
      final item = _order.removeAt(i);
      _order.insert(target, item);
    });
  }

  void _setProp(String section, String key, Object? value) {
    setState(() {
      final props = _props.putIfAbsent(
          section, () => {...siteSectionDefaults(section)});
      props[key] = value;
    });
  }

  /// La lista MUTABLE de una opción (por ejemplo `stats`).
  ///
  /// Devuelve SIEMPRE la misma lista que está en `_props`: los editores la
  /// modifican y el `setState` vuelve a pintar la sección (y su miniatura).
  List<Map<String, dynamic>> _propList(String section, String key) {
    final props = _props.putIfAbsent(section, () => _mutableProps(section, null));
    // Si ya se armó una vez, es la MISMA lista: agregar o quitar filas se
    // recuerda entre repintados (si no, lo agregado desaparecía al instante).
    if (props[key] is List<Map<String, dynamic>>) {
      return props[key] as List<Map<String, dynamic>>;
    }
    final out = <Map<String, dynamic>>[];
    final raw = props[key];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) out.add({for (final m in e.entries) m.key: m.value});
      }
    }
    props[key] = out;
    return out;
  }

  // ---------------------------------------------------------------
  // Valores para la miniatura
  // ---------------------------------------------------------------

  /// Textos de una sección ya resueltos (lo editado, o el de fábrica).
  Map<String, String> _values(String section) => {
        for (final f in kSiteTexts.where((f) => f.sectionKey == section))
          f.key: _texts[f.key]!.text.trim().isEmpty
              ? f.def
              : _texts[f.key]!.text.trim(),
      };

  Map<String, String> _imageValues(String section) => {
        for (final f in kSiteImages.where((f) => f.sectionKey == section))
          f.key: _images[f.key]!.text.trim().isEmpty
              ? f.def
              : _images[f.key]!.text.trim(),
      };

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = _visible.entries.where((e) => !e.value).length;
    final doc = _document(full: _stored);
    // Con la base llena se cuenta todo lo que hay guardado; con la base vacía,
    // lo que se ha cambiado respecto a lo de fábrica.
    final fields = doc.texts.length + doc.images.length;
    final changed = _stored
        ? fields
        : fields +
            doc.sections.values
                .map((s) => s.props.length)
                .fold(0, (a, b) => a + b);

    return PageContainer(
      title: 'Sitio web',
      description: 'Diseña la página por secciones: cada una con su '
          'miniatura, sus textos, sus imágenes y sus opciones. Lo que guardes '
          'se aplica en la web al instante, sin volver a publicar el sitio.',
      icon: Icons.language_rounded,
      stats: [
        StatPill(
            icon: Icons.edit_note_outlined,
            label: _stored
                ? '$changed campos en la base'
                : '$changed campos editados'),
        StatPill(
            icon: Icons.visibility_off_outlined,
            label: hidden == 1 ? '1 sección oculta' : '$hidden secciones ocultas'),
        StatPill(
            icon: Icons.view_carousel_outlined,
            label: '${kSiteSectionTemplates.length} secciones'),
        StatPill(
            icon: _stored ? Icons.cloud_done_outlined : Icons.description_outlined,
            label: _stored ? 'En la base de datos' : 'En el HTML del sitio'),
      ],
      actions: [
        HsActionButton(
          icon: Icons.refresh,
          label: 'Recargar',
          primary: false,
          onPressed: _loading ? null : _load,
        ),
        HsActionButton(
          icon: Icons.save_outlined,
          label: 'Guardar cambios',
          onPressed: (_loading || _saving || !_dirty) ? null : _save,
        ),
      ],
      child: !(widget.supported ?? siteModuleSupported())
          ? const EmptyState(
              icon: Icons.desktop_windows_outlined,
              title: 'Disponible solo en Windows',
              message: 'Por ahora el diseñador de la página web se abre desde la '
                  'app de escritorio del panel.',
            )
          : _loading
              ? const ListSkeleton(lines: 4, cardHeight: 150)
              : _error != null
                  ? _errorCard(scheme)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _intro(scheme),
                        const SizedBox(height: 14),
                        // Con la base vacía se avisa (y se ofrece subir lo que
                        // ya hay): si no, la web sigue leyendo su HTML.
                        if (!_stored) ...[
                          _dbNotice(scheme),
                          const SizedBox(height: 14),
                        ],
                        ..._sectionsList(scheme),
                        const SizedBox(height: 18),
                        _footer(scheme),
                      ],
                    ),
    );
  }

  /// Aviso (con su botón) cuando la base de datos todavía está vacía.
  Widget _dbNotice(ColorScheme scheme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warn.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warn.withValues(alpha: .30)),
        ),
        child: Row(
          children: [
            const Icon(Icons.storage_rounded, size: 18, color: AppColors.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'La base de datos todavía no tiene el contenido',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'La web está mostrando lo que trae el sitio (su HTML). '
                    'Guarda el contenido actual en la base para que la web lo '
                    'lea de ahí.',
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _importToDb,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Guardar lo actual en la base'),
            ),
          ],
        ),
      );

  Widget _intro(ColorScheme scheme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Toca "Editar" en una sección para cambiar sus textos, sus '
                'imágenes y sus opciones. Arriba aparece primero en la página: '
                'usa las flechas para cambiar el orden y el interruptor para '
                'mostrarla u ocultarla.',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  Widget _errorCard(ColorScheme scheme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

  /// Las tarjetas: las movibles en su orden y, al final, las fijas.
  List<Widget> _sectionsList(ColorScheme scheme) {
    final out = <Widget>[];
    for (var i = 0; i < _order.length; i++) {
      final key = _order[i];
      final t = siteSectionTemplate(key);
      if (t == null) continue;
      out.add(_sectionCard(
        scheme,
        t,
        position: i,
        total: _order.length,
      ));
      out.add(const SizedBox(height: 12));
    }
    for (final t in kSiteSectionTemplates.where((t) => !t.orderable)) {
      out.add(_sectionCard(scheme, t, position: null));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  /// Una SECCIÓN: cabecera, miniatura y (si está abierta) sus campos.
  Widget _sectionCard(
    ColorScheme scheme,
    SiteSectionTemplate t, {
    required int? position,
    int total = 0,
  }) {
    final open = _open.contains(t.key);
    final visible = _visible[t.key] ?? t.defaultVisible;
    final edited = sitePropsChanged(t.key, _props[t.key] ?? const {}) +
        kSiteTexts
            .where((f) => f.sectionKey == t.key)
            .where((f) => _texts[f.key]!.text.trim().isNotEmpty)
            .length +
        kSiteImages
            .where((f) => f.sectionKey == t.key)
            .where((f) => _images[f.key]!.text.trim().isNotEmpty)
            .length;

    // Es un Material (y no un Container con decoration) porque adentro hay
    // interruptores y casillas: ellos pintan su fondo y su onda sobre el
    // Material más cercano, así que el color de la tarjeta tiene que SER ese
    // Material (si no, se pintarían por detrás y quedarían invisibles).
    return Material(
      // Clave estable por sección: las pruebas (y los atajos) la usan para
      // saber de qué tarjeta es cada cosa.
      key: ValueKey('site-section-${t.key}'),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: open
              ? scheme.primary.withValues(alpha: .55)
              : scheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Cabecera: nombre, estado y acciones ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.primary.withValues(alpha: .25)),
                  ),
                  child: Icon(t.icon, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _tag(scheme, 'Plantilla', Icons.dashboard_customize_outlined),
                          if (position != null) ...[
                            const SizedBox(width: 6),
                            _tag(scheme, '${position + 1}', Icons.swap_vert_rounded),
                          ],
                          if (edited > 0) ...[
                            const SizedBox(width: 6),
                            _tag(scheme, '$edited editado${edited == 1 ? '' : 's'}',
                                Icons.edit_outlined, color: AppColors.ok),
                          ],
                          if (!visible) ...[
                            const SizedBox(width: 6),
                            _tag(scheme, 'Oculta', Icons.visibility_off_outlined,
                                color: AppColors.warn),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (position != null) ...[
                  IconButton(
                    tooltip: 'Subir',
                    visualDensity: VisualDensity.compact,
                    onPressed: position == 0 ? null : () => _move(t.key, -1),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Bajar',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        position == total - 1 ? null : () => _move(t.key, 1),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ),
                  Tooltip(
                    message: visible ? 'Ocultar sección' : 'Mostrar sección',
                    child: Switch.adaptive(
                      value: visible,
                      onChanged: (v) => setState(() => _visible[t.key] = v),
                    ),
                  ),
                ],
                TextButton.icon(
                  onPressed: () => setState(() {
                    if (open) {
                      _open.remove(t.key);
                    } else {
                      _open.add(t.key);
                    }
                  }),
                  icon: Icon(
                    open ? Icons.expand_less_rounded : Icons.edit_outlined,
                    size: 17,
                  ),
                  label: Text(open ? 'Cerrar' : 'Editar'),
                ),
              ],
            ),
          ),
          // ---- Miniatura de cómo se ve la sección ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SiteSectionPreview(
              section: t.key,
              values: _values(t.key),
              images: _imageValues(t.key),
              props: _props[t.key] ?? const {},
              gold: _goldColor,
            ),
          ),
          if (open) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _fields(scheme, t),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(ColorScheme scheme, String label, IconData icon, {Color? color}) {
    final tint = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tint),
          ),
        ],
      ),
    );
  }

  // ---------------- Campos de una sección ----------------

  List<Widget> _fields(ColorScheme scheme, SiteSectionTemplate t) {
    final out = <Widget>[];
    final texts = kSiteTexts.where((f) => f.sectionKey == t.key).toList();
    final images = kSiteImages.where((f) => f.sectionKey == t.key).toList();

    if (texts.isNotEmpty) {
      out.add(_groupHeader('TEXTOS'));
      for (final f in texts) {
        out.add(_textField(scheme, f));
      }
    }
    if (images.isNotEmpty) {
      out.add(_groupHeader('IMÁGENES'));
      for (final f in images) {
        out.add(_imageField(scheme, f));
      }
    }
    for (final p in t.props) {
      out.add(_groupHeader(p.label.toUpperCase()));
      if (p.hint != null) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            p.hint!,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ));
      }
      switch (p.kind) {
        case SitePropKind.stats:
          out.add(_statsEditor(scheme, t.key));
        case SitePropKind.testimonials:
          out.add(_testimonialsEditor(scheme, t.key));
        case SitePropKind.gallery:
          out.add(_galleryEditor(scheme, t.key));
        case SitePropKind.toggle:
          out.add(_toggleEditor(scheme, t.key, p));
        case SitePropKind.number:
          out.add(_numberEditor(scheme, t.key, p));
        case SitePropKind.text:
          out.add(_propTextField(scheme, t.key, p));
      }
      out.add(const SizedBox(height: 4));
    }
    if (out.isEmpty) {
      out.add(Text(
        'Esta sección no tiene campos editables: sólo se muestra u oculta.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      ));
    }
    return out;
  }

  Widget _groupHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _textField(ColorScheme scheme, SiteTextField f) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _texts[f.key],
                minLines: f.multiline ? 3 : 1,
                maxLines: f.multiline ? 6 : 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: f.label,
                  hintText: f.def,
                  helperText: f.lines
                      ? (f.hint ?? 'La segunda línea va resaltada')
                      : f.hint,
                  helperMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _restoreButton(
              active: _texts[f.key]!.text.trim().isNotEmpty,
              tooltip: 'Volver al texto original',
              onTap: () => setState(() => _texts[f.key]!.text = ''),
            ),
          ],
        ),
      );

  Widget _imageField(ColorScheme scheme, SiteImageField f) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _images[f.key],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: f.label,
                  hintText: f.def,
                  helperText: f.background
                      ? 'Ruta, URL o una foto del Drive (fondo de la sección)'
                      : 'Ruta, URL o una foto del Drive',
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Elegir una foto del Drive',
              onPressed: () => _pickImagesFor(_images[f.key]!),
              icon: const Icon(Icons.folder_open_rounded, size: 18),
            ),
            _restoreButton(
              active: _images[f.key]!.text.trim().isNotEmpty,
              tooltip: 'Volver a la imagen original',
              onTap: () => setState(() => _images[f.key]!.text = ''),
            ),
            const SizedBox(width: 10),
            _thumb(_images[f.key]!.text.trim().isEmpty
                ? f.def
                : _images[f.key]!.text.trim()),
          ],
        ),
      );

  /// Miniatura: sólo se puede ver la imagen si es una URL accesible.
  Widget _thumb(String path) {
    final scheme = Theme.of(context).colorScheme;
    final isUrl = path.startsWith('http://') || path.startsWith('https://');
    return Container(
      width: 64,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: isUrl
          ? Image.network(
              path,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _thumbFallback(scheme),
            )
          : _thumbFallback(scheme),
    );
  }

  Widget _thumbFallback(ColorScheme scheme) => Center(
        child: Icon(Icons.image_outlined, size: 18, color: scheme.onSurfaceVariant),
      );

  Widget _restoreButton({
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: active ? onTap : null,
        icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
      );

  // ---- Opciones: números, testimonios, galería, interruptores… ----

  /// Pares valor + etiqueta (los números de "Sobre nosotros").
  Widget _statsEditor(ColorScheme scheme, String section) {
    final list = _propList(section, 'stats');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: TextFormField(
                    key: ValueKey('$section-stat-$i-value'),
                    initialValue: '${list[i]['value'] ?? ''}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Número'),
                    onChanged: (v) {
                      list[i]['value'] = int.tryParse(v.trim()) ?? 0;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('$section-stat-$i-label'),
                    initialValue: '${list[i]['label'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Etiqueta'),
                    onChanged: (v) {
                      list[i]['label'] = v.trim();
                      setState(() {});
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar este número',
                  onPressed: () => setState(() => list.removeAt(i)),
                  icon: Icon(Icons.remove_circle_outline, size: 18, color: scheme.error),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => list.add({'value': 0, 'label': ''})),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Agregar número'),
          ),
        ),
      ],
    );
  }

  /// Comentarios de clientes (nombre, servicio y texto).
  Widget _testimonialsEditor(ColorScheme scheme, String section) {
    final list = _propList(section, 'items');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'La página muestra los testimonios de siempre hasta que escribas '
              'los tuyos aquí.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
        for (var i = 0; i < list.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('$section-tst-$i-name'),
                        initialValue: '${list[i]['name'] ?? ''}',
                        decoration: const InputDecoration(labelText: 'Cliente'),
                        onChanged: (v) {
                          list[i]['name'] = v.trim();
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('$section-tst-$i-role'),
                        initialValue: '${list[i]['role'] ?? ''}',
                        decoration:
                            const InputDecoration(labelText: 'Evento o servicio'),
                        onChanged: (v) {
                          list[i]['role'] = v.trim();
                          setState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar este comentario',
                      onPressed: () => setState(() => list.removeAt(i)),
                      icon: Icon(Icons.remove_circle_outline,
                          size: 18, color: scheme.error),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('$section-tst-$i-text'),
                  initialValue: '${list[i]['text'] ?? ''}',
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Comentario'),
                  onChanged: (v) {
                    list[i]['text'] = v.trim();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
                () => list.add({'name': '', 'role': '', 'text': ''})),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Agregar comentario'),
          ),
        ),
      ],
    );
  }

  /// Galería: fotos por categoría del catálogo (del Drive o por URL).
  Widget _galleryEditor(ColorScheme scheme, String section) {
    final categories = siteGalleryCategories(_props[section] ?? const {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Usa las categorías del catálogo de paquetes. Cada una con sus fotos: '
          'se muestran sólo las categorías que tengan al menos una foto. Sin '
          'ninguna, la página sigue mostrando su galería pública.',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (_categories.isEmpty)
          Text(
            'No se pudieron leer las categorías del catálogo.',
            style: TextStyle(fontSize: 12, color: scheme.error),
          ),
        for (final cat in _categories)
          _galleryCategoryTile(scheme, section, cat.key, cat.name, categories),
      ],
    );
  }

  Widget _galleryCategoryTile(
    ColorScheme scheme,
    String section,
    String key,
    String name,
    List<({String key, String name, List<String> items})> current,
  ) {
    final found = current.where((c) => c.key == key).toList();
    final items = found.isEmpty ? <String>[] : found.first.items;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                items.isEmpty
                    ? 'sin fotos'
                    : '${items.length} foto${items.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              if (items.isNotEmpty)
                IconButton(
                  tooltip: 'Quitar todas las fotos de esta categoría',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setGalleryItems(section, key, name, const []),
                  icon: Icon(Icons.delete_outline, size: 17, color: scheme.error),
                ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < items.length; i++)
                  Stack(
                    children: [
                      _thumb(items[i]),
                      Positioned(
                        right: -6,
                        top: -8,
                        child: IconButton(
                          tooltip: 'Quitar esta foto',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setGalleryItems(
                            section,
                            key,
                            name,
                            [...items]..removeAt(i),
                          ),
                          icon: const Icon(Icons.cancel, size: 15),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final picked = await _pickImages();
                  if (picked.isEmpty) return;
                  _setGalleryItems(section, key, name, [...items, ...picked]);
                },
                icon: const Icon(Icons.folder_open_rounded, size: 17),
                label: const Text('Elegir del Drive'),
              ),
              TextButton.icon(
                onPressed: () => _addGalleryPhotoByUrl(section, name),
                icon: const Icon(Icons.link_rounded, size: 17),
                label: const Text('Pegar URL'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Guarda las fotos de UNA categoría (y borra la categoría si se vacía).
  void _setGalleryItems(
    String section,
    String key,
    String name,
    List<String> items,
  ) {
    setState(() {
      final props = _props.putIfAbsent(
          section, () => {...siteSectionDefaults(section)});
      final raw = props['categories'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(e.cast<String, dynamic>());
        }
      }
      final clean = items.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      final i = list.indexWhere((c) => '${c['key']}' == key);
      if (clean.isEmpty) {
        if (i >= 0) list.removeAt(i);
      } else if (i >= 0) {
        list[i] = {'key': key, 'name': name, 'items': clean};
      } else {
        list.add({'key': key, 'name': name, 'items': clean});
      }
      props['mode'] = list.isEmpty ? 'public' : 'custom';
      props['categories'] = list;
    });
  }

  Future<void> _addGalleryPhotoByUrl(String section, String categoryName) async {
    final value = await _askUrl(
      title: 'Foto para "$categoryName"',
      label: 'Ruta o URL de la foto (images/foto.jpg, https://…)',
    );
    if (value == null || value.trim().isEmpty) return;
    final key = siteCategoryKey(categoryName);
    final current = siteGalleryCategories(_props[section] ?? const {})
        .where((c) => c.key == key)
        .toList();
    final items = current.isEmpty ? <String>[] : current.first.items;
    _setGalleryItems(section, key, categoryName, [...items, value.trim()]);
  }

  Widget _toggleEditor(
      ColorScheme scheme, String section, SitePropField p) {
    final value = _props[section]?[p.key] != false;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (v) => _setProp(section, p.key, v),
      title: Text(p.label, style: const TextStyle(fontSize: 13.5)),
    );
  }

  Widget _numberEditor(ColorScheme scheme, String section, SitePropField p) {
    final value = (_props[section]?[p.key] as num?)?.toInt() ??
        (siteSectionDefaults(section)[p.key] as num?)?.toInt() ??
        p.min;
    return Row(
      children: [
        IconButton(
          tooltip: 'Menos',
          onPressed: value <= p.min
              ? null
              : () => _setProp(section, p.key, value - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        Text('$value', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        IconButton(
          tooltip: 'Más',
          onPressed: value >= p.max
              ? null
              : () => _setProp(section, p.key, value + 1),
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          p.label,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _propTextField(ColorScheme scheme, String section, SitePropField p) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: ValueKey('$section-prop-${p.key}'),
          initialValue: '${_props[section]?[p.key] ?? ''}',
          decoration: InputDecoration(labelText: p.label),
          onChanged: (v) => _setProp(section, p.key, v.trim()),
        ),
      );

  // ---------------- Selector de fotos del Drive ----------------

  Future<List<String>> _pickImages() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return const [];
    }
    final picked = await showHsModal<List<String>>(
      context: context,
      builder: (_) => _DrivePhotoPicker(drive: drive),
    );
    return picked ?? const [];
  }

  Future<void> _pickImagesFor(TextEditingController controller) async {
    final picked = await _pickImages();
    if (picked.isEmpty) return;
    setState(() => controller.text = picked.first);
  }

  Future<String?> _askUrl({required String title, required String label}) =>
      showHsModal<String>(
        context: context,
        builder: (_) => _UrlDialog(title: title, label: label),
      );

  // ---------------- Pie ----------------

  Widget _footer(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Icon(_dirty ? Icons.edit_outlined : Icons.check_circle_outline,
              size: 18, color: _dirty ? scheme.primary : AppColors.ok),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _dirty
                  ? 'Hay cambios sin guardar.'
                  : 'Todo guardado. La web lo aplica al cargar, sin volver a publicar.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _restoreAll,
            icon: const Icon(Icons.settings_backup_restore_rounded, size: 17),
            label: const Text('Volver al original'),
          ),
          if (_saving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// Pregunta una URL (foto o enlace).
///
/// Es un widget con estado para que el campo se lleve su controlador: si el
/// controlador se liberara al cerrar, la animación de salida del diálogo
/// alcanzaría a repintar el campo y Dart se quejaría de un controlador ya
/// liberado.
class _UrlDialog extends StatefulWidget {
  const _UrlDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: _c,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_c.text),
            child: const Text('Agregar'),
          ),
        ],
      );
}

/// Selector de fotos del Drive: navega carpetas y marca imágenes.
///
/// Devuelve las URLs públicas de las fotos elegidas (`<servidor>/files/<ruta>`)
/// SIN el token de sesión: la portada es pública y no puede llevar dentro la
/// sesión de nadie.
class _DrivePhotoPicker extends StatefulWidget {
  const _DrivePhotoPicker({required this.drive});

  final DriveBase drive;

  @override
  State<_DrivePhotoPicker> createState() => _DrivePhotoPickerState();
}

class _DrivePhotoPickerState extends State<_DrivePhotoPicker> {
  List<String> _rel = const [];
  List<DriveItem> _items = const [];
  final Set<String> _picked = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.drive.listFolderItems(_rel);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = 'No se pudo abrir la carpeta: $e';
        _loading = false;
      });
    }
  }

  /// URL pública de una foto (`<drive>/files/<ruta>`), sin token.
  String _urlFor(DriveItem item) {
    final segments = [..._rel, item.name]
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    return '${AppConstants.apiBase.replaceAll(RegExp(r'/$'), '')}/files/$segments';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = _items.where((i) => i.isFolder).toList();
    final photos = _items.where((i) => !i.isFolder).toList();
    return AlertDialog(
      title: const Text('Fotos del Drive'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_rel.isNotEmpty)
                  IconButton(
                    tooltip: 'Subir un nivel',
                    onPressed: () {
                      setState(() => _rel = _rel.sublist(0, _rel.length - 1));
                      _load();
                    },
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  ),
                Expanded(
                  child: Text(
                    _rel.isEmpty ? 'Mi Drive' : _rel.join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  '${_picked.length} elegida${_picked.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Las fotos se enlazan desde el servidor del Drive '
              '(${AppConstants.apiBase}): para verlas en la página tienen que '
              'poder abrirse sin iniciar sesión.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, textAlign: TextAlign.center))
                      : ListView(
                          children: [
                            for (final f in folders)
                              ListTile(
                                dense: true,
                                leading: Icon(Icons.folder_rounded, color: scheme.primary),
                                title: Text(f.name, style: const TextStyle(fontSize: 13)),
                                onTap: () {
                                  setState(() => _rel = [..._rel, f.name]);
                                  _load();
                                },
                              ),
                            for (final p in photos)
                              CheckboxListTile(
                                dense: true,
                                value: _picked.contains(_urlFor(p)),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _picked.add(_urlFor(p));
                                  } else {
                                    _picked.remove(_urlFor(p));
                                  }
                                }),
                                secondary: SizedBox(
                                  width: 44,
                                  height: 34,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      widget.drive.thumbSource(p, width: 120),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => _thumbFallback(scheme),
                                    ),
                                  ),
                                ),
                                title: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_picked.toList()..sort()),
          child: Text('Agregar ${_picked.length}'),
        ),
      ],
    );
  }

  Widget _thumbFallback(ColorScheme scheme) => Center(
        child: Icon(Icons.image_outlined, size: 16, color: scheme.onSurfaceVariant),
      );
}

/// Permiso con el que se muestra/edita el módulo (nombre EXACTO en la BD).
const String kSiteModuleName = 'Sitio web';

/// ¿El rol puede GUARDAR el contenido del sitio?
bool canEditSite() =>
    HsAccess.instance.degraded || HsAccess.instance.can(kSiteModuleName, 'update');


