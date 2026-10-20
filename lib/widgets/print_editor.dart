import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../print_export.dart';
import '../print_models.dart';
import '../theme.dart';
import 'hs_toast.dart';
import 'print_preview.dart';

// ==================================================================
// MÓDULO DEL FORMATO DE IMPRESIÓN
// ==================================================================
// Se abre con las fotos seleccionadas (de uno o varios servicios) y deja:
//
//   * elegir el formato (o crear uno nuevo: "12x18", "5x7", "1x1"…);
//   * subir el «Grosor de borde» (la foto se encoge, el marco no);
//   * ajustar el recorte de CADA foto (arrastrar + zoom);
//   * «Descargar» (Listo): PNG de una foto o ZIP con todas;
//   * «Guardar»: conserva formato, borde y POSICIONES sin cerrar el envío;
//   * «Terminar»: bloquea el formato del envío; después aparece «Reabrir».
//
// Tanto Guardar como Terminar escriben en el servidor, así el estudio puede
// retomar el trabajo otro día con cada foto en el mismo encuadre.
// ==================================================================

/// Abre el módulo del formato. Devuelve true si se cerró un envío o se
/// reabrió (la página recarga).
Future<bool> showPrintFormatsDialog(
  BuildContext context, {
  required List<String> paths,
  required List<PrintFormat> formats,
  required int? initialFormatId,
  required int initialBorder,
  Map<String, PrintCrop> initialCrops = const {},
  required bool locked,
  required Future<PrintFormat?> Function(
    String name,
    double width,
    double height,
    String unit,
  )
  onCreateFormat,
  Future<void> Function(PrintFormat format)? onDeleteFormat,
  required Future<void> Function(
    PrintFormat format,
    int border,
    Map<String, PrintCrop> crops,
  )
  onSaveConfig,
  required Future<void> Function(
    PrintFormat format,
    int border,
    Map<String, PrintCrop> crops,
  )
  onFinish,
  Future<void> Function()? onReopen,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    // Clic fuera = cerrar (regla de todos los modales del panel).
    barrierDismissible: true,
    builder: (_) => _PrintFormatsDialog(
      paths: paths,
      formats: formats,
      initialFormatId: initialFormatId,
      initialBorder: initialBorder,
      initialCrops: initialCrops,
      locked: locked,
      onCreateFormat: onCreateFormat,
      onDeleteFormat: onDeleteFormat,
      onSaveConfig: onSaveConfig,
      onFinish: onFinish,
      onReopen: onReopen,
    ),
  );
  return changed ?? false;
}

class _PrintFormatsDialog extends StatefulWidget {
  const _PrintFormatsDialog({
    required this.paths,
    required this.formats,
    required this.initialFormatId,
    required this.initialBorder,
    this.initialCrops = const {},
    required this.locked,
    required this.onCreateFormat,
    required this.onSaveConfig,
    required this.onFinish,
    required this.onReopen,
    this.onDeleteFormat,
  });

  final List<String> paths;
  final List<PrintFormat> formats;
  final int? initialFormatId;
  final int initialBorder;
  final Map<String, PrintCrop> initialCrops;
  final bool locked;
  final Future<PrintFormat?> Function(
    String name,
    double width,
    double height,
    String unit,
  )
  onCreateFormat;
  final Future<void> Function(PrintFormat format)? onDeleteFormat;
  final Future<void> Function(
    PrintFormat format,
    int border,
    Map<String, PrintCrop> crops,
  )
  onSaveConfig;
  final Future<void> Function(
    PrintFormat format,
    int border,
    Map<String, PrintCrop> crops,
  )
  onFinish;
  final Future<void> Function()? onReopen;

  @override
  State<_PrintFormatsDialog> createState() => _PrintFormatsDialogState();
}

class _PrintFormatsDialogState extends State<_PrintFormatsDialog> {
  late List<PrintFormat> _formats = List<PrintFormat>.of(widget.formats);
  late PrintFormat? _format = _pickInitialFormat();
  late double _border = widget.initialBorder.toDouble().clamp(0, 30);

  late final Map<String, PrintCrop> _crops = {
    for (final p in widget.paths)
      if (widget.initialCrops[p] != null) p: widget.initialCrops[p]!,
  };
  final Map<String, Future<ui.Image>> _images = {};

  bool _busy = false;
  bool _saving = false;
  double _progress = 0;

  /// Nombre de la foto que se está preparando (para el progreso visible).
  String? _currentName;

  PrintFormat? _pickInitialFormat() {
    final id = widget.initialFormatId;
    if (id != null) {
      for (final f in _formats) {
        if (f.id == id) return f;
      }
    }
    return _formats.isEmpty ? null : _formats.first;
  }

  @override
  void dispose() {
    for (final future in _images.values) {
      future.then((img) => img.dispose()).catchError((_) {});
    }
    super.dispose();
  }

  PrintCrop _cropOf(String path) => _crops[path] ?? const PrintCrop();

  Future<ui.Image> _imageOf(String path) =>
      _images[path] ??= loadPrintPreview(path);

  Future<void> _addFormat() async {
    final created = await showDialog<PrintFormat>(
      context: context,
      builder: (_) => _NewFormatDialog(onCreate: widget.onCreateFormat),
    );
    if (created == null) return;
    setState(() {
      _formats = [..._formats.where((f) => f.id != created.id), created];
      _format = created;
    });
  }

  Future<void> _deleteFormat(PrintFormat format) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar formato'),
        content: Text(
          '¿Quitar el formato ${format.name}? Los trabajos ya terminados '
          'conservan su nombre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onDeleteFormat?.call(format);
    } catch (_) {
      return; // el aviso de error ya lo mostró la API
    }
    if (!mounted) return;
    setState(() {
      _formats = [..._formats.where((f) => f.id != format.id)];
      if (_format?.id == format.id) {
        _format = _formats.isEmpty ? null : _formats.first;
      }
    });
  }

  Future<void> _adjust(String path, ui.Image image) async {
    if (_format == null) return;
    final crop = await showPrintCropDialog(
      context,
      image: image,
      format: _format!,
      initial: _cropOf(path),
    );
    if (crop == null) return;
    setState(() => _crops[path] = crop);
  }

  /// "Listo": recorta TODAS las fotos al formato y las guarda (foto o ZIP).
  Future<void> _download() async {
    final format = _format;
    if (format == null) {
      HsToast.error('Elige un formato de impresión');
      return;
    }
    if (_busy) return;

    final single = widget.paths.length == 1;
    final zipName = _zipName(format);
    // En escritorio se pregunta el destino UNA vez, antes de recortar.
    String? targetPath;
    if (printNeedsSaveDialog) {
      final location = await _askTarget(
        single ? printFileName(widget.paths.first, format) : zipName,
      );
      if (location == null) return;
      targetPath = location;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _currentName = null;
    });
    try {
      final files = <({String name, Uint8List bytes})>[];
      final names = uniquePrintNames(
        widget.paths.map((p) => printFileName(p, format)),
      );
      for (var i = 0; i < widget.paths.length; i++) {
        final path = widget.paths[i];
        if (mounted) {
          setState(() => _currentName = path.split(RegExp(r'[\\/]')).last);
        }
        final image = await loadPrintOriginal(path);
        try {
          final bytes = await renderPrintPhoto(
            image: image,
            format: format,
            crop: _cropOf(path),
            borderPercent: _border,
          );
          files.add((name: names[i], bytes: bytes));
        } finally {
          image.dispose();
        }
        if (mounted) setState(() => _progress = (i + 1) / widget.paths.length);
      }
      if (files.isEmpty) throw 'No se pudo generar ninguna foto';
      if (single) {
        await savePrintBytes(
          files.first.bytes,
          files.first.name,
          targetPath: targetPath,
        );
      } else {
        final zip = zipPrintPhotos(files);
        await savePrintBytes(zip, zipName, targetPath: targetPath);
      }
      if (!mounted) return;
      HsToast.success(
        single
            ? 'Foto lista para imprimir'
            : '${files.length} fotos listas para imprimir',
        details: single
            ? 'Formato ${format.name}'
            : 'ZIP · formato ${format.name}',
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _currentName = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentName = null;
      });
      HsToast.error('No se pudieron generar las fotos', details: '$e');
    }
  }

  /// Guarda formato, borde y posiciones SIN cerrar el envío.
  Future<void> _saveConfig() async {
    final format = _format;
    if (format == null || _busy || _saving) return;
    setState(() => _saving = true);
    try {
      // La notificación verde («Configuración guardada») la muestra la propia
      // API con el número de posiciones: no se duplica aquí.
      await widget.onSaveConfig(format, _border.round(), _crops);
    } catch (_) {
      // La API ya avisó del error con su propio mensaje.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _zipName(PrintFormat format) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final name = format.name.replaceAll(RegExp(r'[^\w\d]+'), '');
    return 'impresiones_${name}_$stamp.zip';
  }

  /// Diálogo Guardar (escritorio). Devuelve la ruta elegida.
  Future<String?> _askTarget(String suggested) async {
    final location = await getSaveLocation(suggestedName: suggested);
    return location?.path;
  }

  Future<void> _finish() async {
    final format = _format;
    if (format == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminar impresión'),
        content: Text(
          'El trabajo queda cerrado con el formato ${format.name} y borde '
          '${_border.round()} %. El cliente ya no podrá cambiar sus fotos '
          'hasta que lo reabras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Terminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.onFinish(format, _border.round(), _crops);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopen() async {
    final fn = widget.onReopen;
    if (fn == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir impresión'),
        content: const Text(
          'El envío vuelve a quedar abierto: el cliente podrá cambiar sus '
          'fotos y tendrá que enviarlas otra vez. El formato deja de estar '
          'bloqueado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 720;
    final format = _format;
    return Dialog(
      insetPadding: phone ? EdgeInsets.zero : const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(phone ? 0 : 20),
      ),
      child: ConstrainedBox(
        constraints: phone
            ? BoxConstraints.tight(size)
            : BoxConstraints(
                maxWidth: 1060,
                maxHeight: (size.height * .9).clamp(420.0, 940.0),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme),
            if (widget.locked) _lockedBanner(scheme),
            _formatBar(scheme, format),
            _borderBar(scheme),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _grid(scheme)),
                  if (_busy) Positioned.fill(child: _downloadOverlay(scheme)),
                ],
              ),
            ),
            _footer(scheme, format),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.print_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Formatos de impresión',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${widget.paths.length} '
                  '${widget.paths.length == 1 ? 'foto seleccionada' : 'fotos seleccionadas'}'
                  ' · ajusta el recorte y descarga',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _lockedBanner(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warn.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 17, color: AppColors.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Trabajo terminado: el formato está bloqueado. Puedes descargarlo '
              'de nuevo o reabrirlo para cambiarlo.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatBar(ColorScheme scheme, PrintFormat? format) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Formato',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (!widget.locked)
                TextButton.icon(
                  onPressed: _busy ? null : _addFormat,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Agregar formato'),
                ),
            ],
          ),
          const SizedBox(height: 2),
          if (_formats.isEmpty)
            Text(
              'No hay formatos todavía: agrega el primero (por ejemplo 5x7).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final f in _formats)
                  _FormatChip(
                    format: f,
                    selected: format?.id == f.id,
                    onTap: widget.locked || _busy
                        ? null
                        : () => setState(() => _format = f),
                    onDelete: widget.locked || _busy
                        ? null
                        : () => _deleteFormat(f),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _borderBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.border_outer_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Grosor de borde',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Slider(
              value: _border,
              min: 0,
              max: 30,
              divisions: 30,
              label: '${_border.round()} %',
              onChanged: widget.locked || _busy
                  ? null
                  : (v) => setState(() => _border = v),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${_border.round()} %',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Progreso visible mientras se generan las fotos: qué foto va, cuántas
  /// faltan y el porcentaje. Antes solo había una barra fina al pie y no se
  /// sabía si el trabajo seguía vivo en un lote de 40 fotos.
  Widget _downloadOverlay(ColorScheme scheme) {
    final total = widget.paths.length;
    final done = (_progress * total).round().clamp(0, total);
    final pct = (_progress * 100).round();
    return ColoredBox(
      color: scheme.surface.withValues(alpha: .82),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preparando las fotos',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          total == 1
                              ? 'Recortando a ${_format?.name ?? 'formato'}'
                              : '$done de $total · $pct %',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 7,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              if (_currentName != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _currentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    if (widget.paths.isEmpty) {
      return Center(
        child: Text(
          'No hay fotos seleccionadas.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final format = _format;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 230,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: widget.paths.length,
      itemBuilder: (context, i) {
        final path = widget.paths[i];
        final name = path.split('/').last;
        return Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .20),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<ui.Image>(
                  future: _imageOf(path),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    }
                    final image = snap.data;
                    if (image == null || format == null) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return GestureDetector(
                      onTap: widget.locked || _busy
                          ? null
                          : () => _adjust(path, image),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                            child: Center(
                              child: PrintFrame(
                                image: image,
                                format: format,
                                crop: _cropOf(path),
                                borderPercent: _border,
                                grid: true,
                              ),
                            ),
                          ),
                          if (!widget.locked)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Material(
                                color: Colors.black.withValues(alpha: .55),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Ajustar recorte',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.crop_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _adjust(path, image),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _footer(ColorScheme scheme, PrintFormat? format) {
    final canUse = format != null && !_busy && !_saving;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          if (format != null)
            Text(
              '${format.name} · ${format.sizeLabel}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: canUse && !widget.locked ? _saveConfig : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar'),
          ),
          OutlinedButton.icon(
            onPressed: canUse ? _download : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_busy ? 'Descargando…' : 'Listo · Descargar'),
          ),
          if (widget.locked)
            FilledButton.icon(
              onPressed: widget.onReopen == null || _busy ? null : _reopen,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Reabrir'),
            )
          else
            FilledButton.icon(
              onPressed: canUse ? _finish : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Terminar'),
            ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.format,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final PrintFormat format;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: format.sizeLabel,
      child: InputChip(
        selected: selected,
        onPressed: onTap,
        onDeleted: onDelete,
        deleteIcon: const Icon(Icons.close_rounded, size: 15),
        label: Text(
          format.name,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
        selectedColor: AppColors.brand.withValues(alpha: .16),
        side: BorderSide(
          color: selected
              ? AppColors.brand.withValues(alpha: .65)
              : scheme.outlineVariant.withValues(alpha: .6),
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Alta de formato: nombre + medidas + unidad, con vista de la proporción.
class _NewFormatDialog extends StatefulWidget {
  const _NewFormatDialog({required this.onCreate});

  final Future<PrintFormat?> Function(
    String name,
    double width,
    double height,
    String unit,
  )
  onCreate;

  @override
  State<_NewFormatDialog> createState() => _NewFormatDialogState();
}

class _NewFormatDialogState extends State<_NewFormatDialog> {
  final _name = TextEditingController();
  final _width = TextEditingController(text: '5');
  final _height = TextEditingController(text: '7');
  String _unit = 'in';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _suggestName() {
    final w = double.tryParse(_width.text.replaceAll(',', '.'));
    final h = double.tryParse(_height.text.replaceAll(',', '.'));
    if (w == null || h == null || w <= 0 || h <= 0) return;
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    final suggested = '${n(w)}x${n(h)}';
    if (_name.text.trim().isEmpty) {
      setState(() => _name.text = suggested);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final w = double.tryParse(_width.text.replaceAll(',', '.'));
    final h = double.tryParse(_height.text.replaceAll(',', '.'));
    final name = _name.text.trim().isEmpty
        ? '${w?.toStringAsFixed(0)}x${h?.toStringAsFixed(0)}'
        : _name.text.trim();
    if (w == null || h == null || w <= 0 || h <= 0 || name.isEmpty) {
      HsToast.error('Escribe el nombre y las medidas del formato');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.onCreate(name, w, h, _unit);
      if (!mounted) return;
      if (saved == null) throw 'No se pudo guardar el formato';
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        HsToast.error('No se pudo guardar', details: '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Nuevo formato de impresión'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('print-format-name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: '5x7, 12x18, 1x1…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('print-format-width'),
                    controller: _width,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _suggestName(),
                    decoration: const InputDecoration(labelText: 'Ancho'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×'),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('print-format-height'),
                    controller: _height,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _suggestName(),
                    decoration: const InputDecoration(labelText: 'Alto'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'in', label: Text('Pulgadas')),
                ButtonSegment(value: 'cm', label: Text('Centímetros')),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            const SizedBox(height: 10),
            Text(
              'La proporción del formato decide el recorte de las fotos. '
              'Las medidas se guardan solo para mostrarlas.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded, size: 18),
          label: const Text('Agregar'),
        ),
      ],
    );
  }
}
