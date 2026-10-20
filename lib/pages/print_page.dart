import 'package:flutter/material.dart';

import '../hs_api.dart';
import '../print_export.dart';
import '../print_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hs_toast.dart';
import '../widgets/print_editor.dart';

// ==================================================================
// MÓDULO IMPRESIONES
// ==================================================================
// Lista los ENVÍOS que hicieron los clientes desde «Mi paquete», agrupados
// por servicio:
//
//   Servicio · cliente · N fotos · Enviado/Terminado
//
// Al expandir se ven las fotos. Se pueden seleccionar todas las de un
// servicio, todas o ninguna; con la selección se abre el MÓDULO DEL FORMATO
// (recorte, borde y descarga). «Terminar» bloquea el formato y «Reabrir»
// devuelve el envío al cliente para que pueda cambiar sus fotos.
// ==================================================================

class PrintRequestData {
  const PrintRequestData({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.packageName,
    required this.clientName,
    required this.status,
    required this.formatId,
    required this.formatName,
    required this.border,
    required this.photos,
    required this.sentAt,
    this.crops = const {},
  });

  final int id;
  final int serviceId;
  final String serviceName;
  final String packageName;
  final String clientName;
  final String status;
  final int? formatId;
  final String formatName;
  final int border;
  final List<String> photos;
  final DateTime? sentAt;

  /// Encuadre guardado de cada foto: { ruta: PrintCrop }.
  final Map<String, PrintCrop> crops;

  bool get finished => status == 'finished';

  static PrintRequestData? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return null;
    return PrintRequestData(
      id: id,
      serviceId: (json['serviceId'] as num?)?.toInt() ?? 0,
      serviceName: (json['serviceName'] ?? 'Servicio').toString().trim(),
      packageName: (json['packageName'] ?? '').toString().trim(),
      clientName: (json['clientName'] ?? 'Sin cliente').toString().trim(),
      status: (json['status'] ?? 'sent').toString().trim(),
      formatId: (json['formatId'] as num?)?.toInt(),
      formatName: (json['formatName'] ?? '').toString().trim(),
      border: (json['border'] as num?)?.toInt() ?? 0,
      photos: ((json['photos'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((p) => p.trim().isNotEmpty)
          .toList(),
      sentAt: DateTime.tryParse((json['sentAt'] ?? '').toString()),
      crops: _cropsFromJson(json['crops']),
    );
  }

  /// Posiciones que guardó el estudio (tolerante a respuestas viejas).
  static Map<String, PrintCrop> _cropsFromJson(Object? raw) {
    final out = <String, PrintCrop>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final path = e.key.toString().trim();
      final crop = PrintCrop.fromJson(e.value);
      if (path.isNotEmpty && crop != null) out[path] = crop;
    }
    return out;
  }
}

class PrintPage extends StatefulWidget {
  const PrintPage({super.key});

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  bool _loading = true;
  String? _error;
  List<PrintRequestData> _requests = const [];
  List<PrintFormat> _formats = const [];

  /// Fotos marcadas por envío: { requestId: { ruta, ... } }.
  final Map<int, Set<String>> _selected = {};
  final Set<int> _expanded = {};

  /// 0 = todos, 1 = pendientes, 2 = terminados.
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<PrintRequestData> get _visible {
    if (_filter == 1) return _requests.where((r) => !r.finished).toList();
    if (_filter == 2) return _requests.where((r) => r.finished).toList();
    return _requests;
  }

  int get _photoTotal => _requests.fold(0, (n, r) => n + r.photos.length);

  int get _selectedCount =>
      _selected.values.fold(0, (n, set) => n + set.length);

  bool get _allSelected =>
      _requests.isNotEmpty &&
      _requests.every((r) => _selected[r.id]?.length == r.photos.length);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HsApi.printRequests();
      if (!mounted) return;
      final requests = data.requests
          .map(PrintRequestData.fromJson)
          .whereType<PrintRequestData>()
          .toList();
      final formats = data.formats
          .map(PrintFormat.fromJson)
          .whereType<PrintFormat>()
          .toList();
      // Descarta selecciones de envíos o fotos que ya no existen.
      final valid = <int, Set<String>>{};
      for (final r in requests) {
        final keep = (_selected[r.id] ?? const <String>{})
            .where(r.photos.contains)
            .toSet();
        if (keep.isNotEmpty) valid[r.id] = keep;
      }
      setState(() {
        _requests = requests;
        _formats = formats;
        _selected
          ..clear()
          ..addAll(valid);
        _expanded.removeWhere((id) => !requests.any((r) => r.id == id));
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        for (final r in _requests) {
          if (r.photos.isNotEmpty) _selected[r.id] = r.photos.toSet();
        }
      }
    });
  }

  void _toggleRequest(PrintRequestData r, {bool? on}) {
    setState(() {
      final set = _selected[r.id] ?? <String>{};
      final all = r.photos.isNotEmpty && set.length == r.photos.length;
      final next = on ?? !all;
      if (next) {
        _selected[r.id] = r.photos.toSet();
      } else {
        _selected.remove(r.id);
      }
    });
  }

  void _togglePhoto(PrintRequestData r, String path) {
    setState(() {
      final set = _selected.putIfAbsent(r.id, () => <String>{});
      if (!set.remove(path)) set.add(path);
      if (set.isEmpty) _selected.remove(r.id);
    });
  }

  Future<void> _openEditor({PrintRequestData? only}) async {
    final involved = <int, PrintRequestData>{};
    final paths = <String>[];
    final seen = <String>{};
    if (only != null) {
      final chosen = _selected[only.id] ?? only.photos.toSet();
      for (final p in chosen) {
        if (seen.add(p)) paths.add(p);
      }
      if (paths.isNotEmpty) involved[only.id] = only;
    } else {
      for (final r in _requests) {
        final chosen = _selected[r.id] ?? const <String>{};
        for (final p in chosen) {
          if (seen.add(p)) paths.add(p);
        }
        if (chosen.isNotEmpty) involved[r.id] = r;
      }
    }
    if (paths.isEmpty) {
      HsToast.info('Elige al menos una foto');
      return;
    }
    final locked = involved.values.every((r) => r.finished);
    final firstFinished = involved.values.where((r) => r.finished).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final reference = firstFinished.isNotEmpty
        ? firstFinished.first
        : involved.values.first;

    // Encuadre que ya estaba guardado (de los envíos implicados). Se pasa al
    // editor para restaurar la posición de cada foto al abrirlo.
    final initialCrops = <String, PrintCrop>{
      for (final r in involved.values)
        for (final p in r.photos)
          if (r.crops[p] != null) p: r.crops[p]!,
    };

    // Posiciones que se guardan en CADA envío (solo sus propias fotos).
    Map<String, dynamic> cropsOf(
      PrintRequestData r,
      Map<String, PrintCrop> crops,
    ) => {
      for (final p in r.photos)
        if (crops[p] != null) p: crops[p]!.toJson(),
    };

    var savedConfig = false;
    final changed = await showPrintFormatsDialog(
      context,
      paths: paths,
      formats: _formats,
      initialFormatId: reference.formatId,
      initialBorder: reference.border,
      initialCrops: initialCrops,
      locked: locked,
      onSaveConfig: (format, border, crops) async {
        for (final r in involved.values) {
          await HsApi.savePrintRequestConfig(
            requestId: r.id,
            formatId: format.id,
            border: border,
            crops: cropsOf(r, crops),
          );
        }
        savedConfig = true;
      },
      onCreateFormat: (name, width, height, unit) async {
        try {
          final json = await HsApi.savePrintFormat(
            name: name,
            width: width,
            height: height,
            unit: unit,
          );
          final format = PrintFormat.fromJson(json);
          if (format != null && mounted) {
            setState(() {
              _formats = [..._formats.where((f) => f.id != format.id), format];
            });
          }
          return format;
        } catch (_) {
          return null;
        }
      },
      onDeleteFormat: (format) => HsApi.deletePrintFormat(format.id),
      onFinish: (format, border, crops) async {
        for (final r in involved.values) {
          if (r.finished) continue;
          await HsApi.finishPrintRequest(
            requestId: r.id,
            formatId: format.id,
            border: border,
            crops: cropsOf(r, crops),
          );
        }
        if (mounted) setState(_selected.clear);
      },
      onReopen: locked
          ? () async {
              for (final r in involved.values) {
                if (!r.finished) continue;
                await HsApi.reopenPrintRequest(r.id);
              }
              if (mounted) setState(_selected.clear);
            }
          : null,
    );
    if ((changed || savedConfig) && mounted) await _load();
  }

  Future<void> _reopen(PrintRequestData r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir selección'),
        content: Text(
          'El envío de ${r.clientName} · ${r.serviceName} vuelve a quedar '
          'abierto: el cliente podrá cambiar sus fotos y tendrá que enviarlas '
          'otra vez.\n\n'
          '${r.photos.length} ${r.photos.length == 1 ? 'foto' : 'fotos'} '
          'seguirán aquí hasta que vuelva a enviar.',
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
    try {
      await HsApi.reopenPrintRequest(r.id);
      if (mounted) await _load();
    } catch (_) {
      // El aviso de error ya salió de la API.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _requests.where((r) => !r.finished).length;
    final finished = _requests.where((r) => r.finished).length;

    return PageContainer(
      module: 'print',
      title: 'Impresiones',
      description:
          'Fotos que los clientes enviaron a impresión: se agrupan por '
          'servicio, se recortan al formato elegido y se descargan.',
      icon: Icons.print_outlined,
      onRefresh: _load,
      stats: [
        StatPill(
          icon: Icons.inbox_outlined,
          label: '$_photoTotal ${_photoTotal == 1 ? 'foto' : 'fotos'}',
        ),
        StatPill(
          icon: Icons.pending_actions_outlined,
          label: '$pending por imprimir',
        ),
        StatPill(icon: Icons.task_alt_rounded, label: '$finished terminadas'),
      ],
      child: _body(scheme),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 120);
    if (_error != null) {
      return Card(
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
    }
    if (_requests.isEmpty) {
      return const EmptyState(
        icon: Icons.print_outlined,
        title: 'Todavía no hay envíos a impresión',
        message:
            'Cuando un cliente elija sus fotos en «Mi paquete» y toque '
            '«Enviar a impresión», aparecerán aquí agrupadas por servicio.',
      );
    }
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(scheme),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const EmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'Sin envíos con ese filtro',
            message: 'Cambia el filtro para ver los demás trabajos.',
          )
        else
          for (final r in visible) ...[
            _requestCard(scheme, r),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _toolbar(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Todos')),
                ButtonSegment(value: 1, label: Text('Pendientes')),
                ButtonSegment(value: 2, label: Text('Terminados')),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _filter = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            // Dos acciones DISTINTAS: "Seleccionar todo" suma fotos y
            // "Quitar selección" deja la selección vacía. Antes la primera
            // cambiaba a "Deseleccionar", que hacía exactamente lo mismo que
            // la segunda y confundía.
            OutlinedButton.icon(
              onPressed: _allSelected ? null : _toggleAll,
              icon: const Icon(Icons.select_all_rounded, size: 17),
              label: const Text('Seleccionar todo'),
            ),
            if (_selectedCount > 0)
              TextButton.icon(
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.clear_all_rounded, size: 17),
                label: Text('Quitar selección ($_selectedCount)'),
              ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _selectedCount == 0 ? null : _openEditor,
              icon: const Icon(Icons.crop_rounded, size: 17),
              label: Text(
                _selectedCount == 0
                    ? 'Abrir formatos'
                    : 'Abrir formatos ($_selectedCount)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(ColorScheme scheme, PrintRequestData r) {
    final selected = _selected[r.id] ?? const <String>{};
    final all = r.photos.isNotEmpty && selected.length == r.photos.length;
    final expanded = _expanded.contains(r.id);
    final statusColor = r.finished ? AppColors.dataFree : AppColors.warn;
    final statusLabel = r.finished ? 'Terminado' : 'Enviado';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(r.id);
              } else {
                _expanded.add(r.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    tristate: false,
                    onChanged: r.photos.isEmpty
                        ? null
                        : (_) => _toggleRequest(r, on: !all),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 21,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.serviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          [
                            r.clientName,
                            if (r.packageName.isNotEmpty) r.packageName,
                            '${r.photos.length} '
                                '${r.photos.length == 1 ? 'foto' : 'fotos'}',
                            if (r.sentAt != null) _date(r.sentAt!),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (r.formatName.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _Tag(
                      text: '${r.formatName} · ${r.border} %',
                      color: AppColors.brand,
                    ),
                  ],
                  const SizedBox(width: 8),
                  _Tag(text: statusLabel, color: statusColor),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    selected.isEmpty
                        ? 'Toca las fotos que quieras imprimir.'
                        : '${selected.length} de ${r.photos.length} seleccionadas',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: r.photos.isEmpty
                        ? null
                        : () => _toggleRequest(r, on: !all),
                    icon: Icon(
                      all
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 16,
                    ),
                    label: Text(
                      all
                          ? 'Quitar todas de este envío'
                          : 'Seleccionar todas de este envío',
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openEditor(only: r),
                    icon: const Icon(Icons.crop_rounded, size: 16),
                    label: const Text('Formatos'),
                  ),
                  // Reabrir funciona con CUALQUIER envío activo: tanto el ya
                  // terminado como el que solo está enviado. Antes solo se
                  // podía reabrir el terminado y no había forma de devolver
                  // la selección al cliente si se había enviado por error.
                  FilledButton.tonalIcon(
                    onPressed: () => _reopen(r),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Reabrir selección'),
                  ),
                ],
              ),
            ),
            if (r.photos.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Text(
                  'Este envío no tiene fotos.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 132,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: r.photos.length,
                itemBuilder: (context, i) => _photoTile(scheme, r, r.photos[i]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _photoTile(ColorScheme scheme, PrintRequestData r, String path) {
    final checked = _selected[r.id]?.contains(path) ?? false;
    final url = printPreviewUrl(path, width: 480);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .25),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: checked
              ? AppColors.brand
              : scheme.outlineVariant.withValues(alpha: .5),
          width: checked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _togglePhoto(r, path),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? AppColors.brand : Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  checked ? Icons.check_rounded : Icons.circle_outlined,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
