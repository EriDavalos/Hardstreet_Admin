import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../theme.dart';
import 'hs_modal.dart';

/// Selector de carpeta del Drive con el diseño del panel: cabecera con el
/// icono, migas de pan, carpetas como tarjetas y las acciones abajo.
///
/// Devuelve los segmentos ABSOLUTOS de la carpeta elegida (null al cancelar).
///
/// Con [roots] NO vacío el selector trabaja DENTRO del drive del cliente: la
/// carpeta compartida es la RAÍZ —no hay nada antes de ella y no se puede
/// subir más arriba—, se puede cambiar entre las carpetas compartidas y las
/// que se solapan con lo ya compartido salen bloqueadas.
///
/// El módulo Empresas lo usa para elegir la carpeta raíz de un estudio dentro
/// del Drive: mismo selector, otro texto y sin bloqueos de "ya compartida".
class DriveFolderPicker extends StatefulWidget {
  const DriveFolderPicker({
    super.key,
    required this.base,
    required this.initial,
    required this.load,
    required this.conflict,
    this.roots = const <String>[],
    this.title = 'Carpeta del Drive',
    this.subtitle,
    this.confirmLabel = 'Compartir esta carpeta',
    this.emptyHint =
        'Esta carpeta no tiene subcarpetas.\nPuedes compartirla tal cual '
        'con el botón de abajo.',
  });

  /// Carpeta que hace de RAÍZ ('' = el Drive completo desde su raíz).
  final String base;

  /// Ruta relativa a [base] donde se abre el selector.
  final List<String> initial;

  /// Lista las SUBcarpetas de una ruta (en segmentos ABSOLUTOS del Drive).
  final Future<List<String>> Function(List<String> path) load;

  /// ¿[absolutePath] se solapa con algo ya compartido? Devuelve con cuál.
  final String? Function(String absolutePath) conflict;

  /// Carpetas compartidas con el cliente (vacío = todo el Drive).
  final List<String> roots;

  /// Cabecera del diálogo.
  final String title;

  /// Aclaración bajo el título (null = la de "compartir").
  final String? subtitle;

  /// Texto del botón que confirma.
  final String confirmLabel;

  /// Texto de la carpeta vacía.
  final String emptyHint;

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  late String _base = widget.base;
  late List<String> _rel = List<String>.of(widget.initial);
  List<String> _folders = const [];
  bool _loading = true;
  String? _error;

  /// ¿Se está eligiendo dentro del drive del cliente?
  bool get _scoped => widget.roots.isNotEmpty;

  /// Segmentos de una ruta ('ReynaCoot/Fiesta' → ['ReynaCoot', 'Fiesta']).
  List<String> _segments(String path) => path.isEmpty
      ? const <String>[]
      : drivePathNormalize(path).split('/').where((s) => s.isNotEmpty).toList();

  /// Ruta ABSOLUTA de la carpeta abierta ([extra] mira una subcarpeta suya).
  List<String> _absolute([List<String>? extra]) => [
    ..._segments(_base),
    ...(extra ?? _rel),
  ];

  /// Ruta absoluta de la carpeta abierta, como texto (para el solapamiento).
  String get _here => _absolute().join('/');

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
      final list = await widget.load(_absolute());
      if (!mounted) return;
      setState(() {
        _folders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _folders = const [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(String name) {
    setState(() => _rel = [..._rel, name]);
    _load();
  }

  void _up() {
    if (_rel.isEmpty) return;
    setState(() => _rel = _rel.sublist(0, _rel.length - 1));
    _load();
  }

  /// Salta a una miga: 0 = la raíz del selector (la carpeta compartida o Mi
  /// Drive) y n = la n-ésima carpeta de [crumbs], que pasa a ser la abierta.
  void _jumpTo(int crumb) {
    final depth = crumb.clamp(0, _rel.length);
    if (depth == _rel.length) return;
    setState(() => _rel = _rel.sublist(0, depth));
    _load();
  }

  /// Cambia de carpeta compartida ("drive del cliente"): se vuelve a su raíz.
  void _switchTo(String root) {
    if (root == _base) return;
    setState(() {
      _base = root;
      _rel = <String>[];
      _folders = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = hsIsPhone(context);
    final conflict = widget.conflict(_here);
    // Migas: la carpeta compartida es la RAÍZ y en el Drive completo se navega
    // desde Mi Drive.
    final crumbs = <String>[
      if (_base.isEmpty) 'Mi Drive' else _segments(_base).last,
      ..._rel,
    ];
    // La raíz del Drive completo NO se comparte (sería todo el drive).
    final canPick = (_scoped || _rel.isNotEmpty) && conflict == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 14, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      title: _header(scheme),
      content: SizedBox(
        width: phone ? double.infinity : 430,
        height: phone ? double.infinity : 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.roots.length > 1) ...[
              _rootPicker(scheme),
              const SizedBox(height: 10),
            ],
            _crumbBar(scheme, crumbs),
            if (conflict != null) ...[
              const SizedBox(height: 8),
              _conflictNotice(scheme, conflict),
            ],
            const SizedBox(height: 10),
            // SUBIR: fuera del listado, para que siga ahí aunque la carpeta
            // abierta esté vacía o no se pueda leer (antes, al abrirse en una
            // carpeta sin subcarpetas, no había ninguna forma de retroceder).
            if (_rel.isNotEmpty) _upTile(scheme),
            Expanded(child: _body(scheme)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canPick ? () => Navigator.pop(context, _absolute()) : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  /// Cabecera: icono degradado + título y aclaración de qué se puede elegir.
  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brand, AppColors.brandDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: .30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.folder_open_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                widget.subtitle ??
                    (_scoped
                        ? 'Solo lo que está dentro del Drive del cliente'
                        : 'Elige cualquier carpeta del Drive'),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cambio de carpeta compartida: solo con más de una (si hay una, esa es el
  /// drive del cliente y no hace falta elegir).
  Widget _rootPicker(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DRIVE DEL CLIENTE',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .9,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in widget.roots)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: r == _base,
                    showCheckmark: false,
                    selectedColor: AppColors.brand,
                    side: BorderSide(
                      color: r == _base
                          ? AppColors.brand
                          : scheme.outlineVariant.withValues(alpha: .6),
                    ),
                    avatar: Icon(
                      Icons.folder_rounded,
                      size: 16,
                      color: r == _base ? Colors.white : AppColors.brand,
                    ),
                    label: Text(
                      drivePathNormalize(r).split('/').last,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: r == _base ? Colors.white : scheme.onSurface,
                      ),
                    ),
                    onSelected: (_) => _switchTo(r),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Migas de pan: la carpeta compartida primero y lo abierto dentro de ella.
  Widget _crumbBar(ColorScheme scheme, List<String> crumbs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(
            _scoped ? Icons.folder_shared_outlined : Icons.home_outlined,
            size: 16,
            color: AppColors.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // La carpeta actual (la última miga) siempre a la vista.
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    // Las migas anteriores se pueden TOCAR para volver de
                    // un salto (la carpeta actual no: ya estás en ella).
                    InkWell(
                      onTap: i == crumbs.length - 1
                          ? null
                          : () => _jumpTo(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Text(
                          crumbs[i],
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: i == crumbs.length - 1
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == crumbs.length - 1
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso de solapamiento: la carpeta está dentro de (o contiene a) algo ya
  /// compartido y por eso no se puede elegir.
  Widget _conflictNotice(ColorScheme scheme, String conflict) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '«$conflict» ya está compartida con este cliente y esta carpeta '
              'está dentro de aquella (o la contiene). Elige otra para no '
              'compartir dos veces lo mismo.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: scheme.error),
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.folder_off_outlined,
                  color: scheme.onSurfaceVariant,
                  size: 26,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      children: [for (final f in _folders) _folderTile(scheme, f)],
    );
  }

  /// Subir un nivel (nunca por encima de la carpeta compartida).
  Widget _upTile(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _up,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.arrow_upward,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Subir un nivel',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una carpeta: tarjeta con su icono. Las que se solapan con lo ya
  /// compartido salen bloqueadas y dicen por qué.
  Widget _folderTile(ColorScheme scheme, String name) {
    final clash = widget.conflict(_absolute([..._rel, name]).join('/'));
    final locked = clash != null;
    final tint = locked ? scheme.error : AppColors.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: locked ? null : () => _enter(name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: locked
                ? scheme.error.withValues(alpha: .35)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                locked ? Icons.lock_outline : Icons.folder_rounded,
                size: 18,
                color: tint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (locked)
                    Text(
                      'Ya compartida en «$clash»',
                      maxLines: 2,
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                ],
              ),
            ),
            if (!locked)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
