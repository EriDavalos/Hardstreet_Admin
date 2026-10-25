import 'package:flutter/material.dart';

import '../hs_format.dart';

// ==================================================================
// CONEXIÓN — ESQUEMA DE SERVIDORES DEL DRIVE
// ==================================================================
// El módulo Conexión enseña los servidores como una TABLA de base de datos
// (la de verdad: `drive_nodes`), con una columna por dato que importa:
//
//   servidor · estado · versión · prioridad · bibliotecas · espacio · ping ·
//   depende de · acciones
//
// Antes cada servidor era una tarjeta con lo mismo en dos renglones: con dos
// servidores había que bajar para comparar versiones o espacio. En una tabla
// los números quedan alineados y la comparación es de un vistazo.
//
// En pantalla angosta (celular) la tabla NO cabe: se dibujan tarjetas con los
// mismos datos, porque ahí lo que importa es leer un servidor, no compararlos.
// ==================================================================

const Color _okGreen = Color(0xFF2F9E5B);
const Color _warnAmber = Color(0xFFD97706);
const Color _offGrey = Color(0xFF6B7280);
const Color _idleBlue = Color(0xFF2F6BFF);

/// Un servidor tal como se PINTA: ya mezclados la base, el hub y la salud.
class NodeView {
  const NodeView({
    required this.id,
    required this.name,
    required this.url,
    required this.enabled,
    this.priority,
    this.notes = '',
    this.version = '',
    this.latencyMs,
    this.free,
    this.total,
    this.sharp,
    this.ffmpeg,
    this.online,
    this.error,
    this.blocked = false,
    this.blockedReason,
    this.dependsOnNames = const [],
  });

  final int id;
  final String name;
  final String url;
  final bool enabled;
  final int? priority;
  final String notes;
  final String version;

  /// Ping medido por el hub a ese servidor (null = no se sabe).
  final int? latencyMs;

  final double? free;
  final double? total;

  /// Bibliotecas instaladas: true/false si el hub lo informó, null = no se sabe.
  final bool? sharp;
  final bool? ffmpeg;

  /// ¿Responde? null = no se pudo comprobar (no hay hub al que preguntar).
  final bool? online;
  final String? error;

  /// Bloqueado por DEPENDER de un servidor que no responde.
  final bool blocked;
  final String? blockedReason;

  /// Nombres de los servidores de los que depende.
  final List<String> dependsOnNames;

  bool get alive => enabled && online == true && !blocked;

  /// Lo que dice la píldora de estado.
  String get stateLabel {
    if (blocked) return 'Mantenimiento';
    if (!enabled) return 'Apagado';
    if (online == null) return 'Sin comprobar';
    return online! ? 'En línea' : 'Sin respuesta';
  }

  String get stateDetail {
    if (blocked) return blockedReason ?? 'Depende de un servidor que no responde';
    if (!enabled) return 'El hub no guarda nada nuevo aquí.';
    if (online == null) return 'No se pudo comprobar si responde.';
    if (online!) return '';
    final text = (error ?? '').trim();
    return text.isEmpty ? 'No contesta: revisa que el servicio esté corriendo.' : 'No contesta: $text';
  }

  Color get color {
    if (blocked) return _warnAmber;
    if (!enabled) return _offGrey;
    if (online == null) return _idleBlue;
    return online! ? _okGreen : _warnAmber;
  }

  String get latencyLabel {
    final ms = latencyMs;
    if (ms == null) return '—';
    return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
  }

  String get diskLabel {
    final f = free;
    final t = total;
    if (f == null || t == null || t <= 0) return '—';
    return '${hsBytes(f)} / ${hsBytes(t)}';
  }

  double? get diskRatio {
    final f = free;
    final t = total;
    if (f == null || t == null || t <= 0) return null;
    return ((t - f) / t).clamp(0.0, 1.0);
  }
}

/// Tabla (escritorio) o tarjetas (celular) con los servidores del Drive.
class NodesSchemaTable extends StatelessWidget {
  const NodesSchemaTable({
    super.key,
    required this.nodes,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    this.busyId,
  });

  final List<NodeView> nodes;
  final void Function(NodeView) onEdit;
  final void Function(NodeView) onToggle;
  final void Function(NodeView) onDelete;
  final void Function(NodeView) onLogs;
  final void Function(NodeView) onRestart;
  final void Function(NodeView) onUpload;

  /// Servidor con una acción en curso (se marca con un girador).
  final int? busyId;

  static const double _minWidth = 1180;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1000;
    if (compact) return _cards(context);
    return _table(context);
  }

  // ---------------- ESCRITORIO: tabla ----------------

  Widget _table(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      _headerRow(scheme),
      for (final node in nodes) _dataRow(context, scheme, node),
      _footerRow(scheme),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _minWidth,
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            columnWidths: const {
              0: FlexColumnWidth(3.0), // servidor
              1: FlexColumnWidth(2.1), // estado
              2: FlexColumnWidth(1.15), // versión
              3: FlexColumnWidth(1.05), // prioridad
              4: FlexColumnWidth(1.9), // bibliotecas
              5: FlexColumnWidth(2.0), // espacio
              6: FlexColumnWidth(1.0), // ping
              7: FlexColumnWidth(2.2), // depende de
              8: FixedColumnWidth(58), // acciones
            },
            children: rows,
          ),
        ),
      ),
    );
  }

  TableRow _headerRow(ColorScheme scheme) {
    const labels = [
      'servidor',
      'estado',
      'versión',
      'prior.',
      'bibliotecas',
      'espacio',
      'ping',
      'depende de',
      '',
    ];
    return TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .5)),
      children: [
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: .9,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  TableRow _dataRow(BuildContext context, ColorScheme scheme, NodeView node) {
    return TableRow(
      decoration: BoxDecoration(
        color: node.blocked ? _warnAmber.withValues(alpha: .05) : null,
      ),
      children: [
        // --- servidor ---
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                node.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (node.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    node.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // --- estado ---
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatePill(label: node.stateLabel, color: node.color),
              // El motivo va debajo de la píldora: «no responde» sin decir por
              // qué no ayuda a arreglarlo (puerto cerrado, timeout, base…).
              if (node.stateDetail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    node.stateDetail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.25,
                      color: node.blocked ? _warnAmber : _offGrey,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // --- versión ---
        _cell(node.version.isEmpty ? '—' : 'v${node.version}', mono: true),
        // --- prioridad ---
        _cell(node.priority?.toString() ?? '—', mono: true),
        // --- bibliotecas ---
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _LibChip(label: 'sharp', ok: node.sharp),
              _LibChip(label: 'ffmpeg', ok: node.ffmpeg),
            ],
          ),
        ),
        // --- espacio ---
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.diskLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: node.diskRatio,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: (node.diskRatio ?? 0) >= .9 ? scheme.error : node.color,
                ),
              ),
            ],
          ),
        ),
        // --- ping ---
        _cell(node.latencyLabel, mono: true),
        // --- depende de ---
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Text(
            node.dependsOnNames.isEmpty ? '—' : node.dependsOnNames.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: node.dependsOnNames.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: node.dependsOnNames.isEmpty ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
        // --- acciones ---
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: _NodeMenu(
            node: node,
            busy: busyId == node.id,
            onEdit: onEdit,
            onToggle: onToggle,
            onDelete: onDelete,
            onLogs: onLogs,
            onRestart: onRestart,
            onUpload: onUpload,
          ),
        ),
      ],
    );
  }

  TableRow _footerRow(ColorScheme scheme) {
    final online = nodes.where((n) => n.alive).length;
    final blocked = nodes.where((n) => n.blocked).length;
    return TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .35)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Text(
            '${nodes.length} servidor${nodes.length == 1 ? '' : 'es'} · '
            '$online en línea${blocked == 0 ? '' : ' · $blocked en mantenimiento'}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 1; i < 9; i++) const SizedBox.shrink(),
      ],
    );
  }

  Widget _cell(String text, {bool mono = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: mono ? 'monospace' : null,
        fontSize: mono ? 11 : 12.5,
        fontWeight: mono ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );

  // ---------------- CELULAR: tarjetas ----------------

  Widget _cards(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final node in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: node.color.withValues(alpha: .38)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: node.color, width: 4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                node.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatePill(label: node.stateLabel, color: node.color),
                        _NodeMenu(
                          node: node,
                          busy: busyId == node.id,
                          onEdit: onEdit,
                          onToggle: onToggle,
                          onDelete: onDelete,
                          onLogs: onLogs,
                          onRestart: onRestart,
                          onUpload: onUpload,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DataBit(label: 'versión', value: node.version.isEmpty ? '—' : 'v${node.version}'),
                        _DataBit(label: 'prioridad', value: node.priority?.toString() ?? '—'),
                        _DataBit(label: 'ping', value: node.latencyLabel),
                        _DataBit(label: 'espacio', value: node.diskLabel),
                        _DataBit(
                          label: 'depende de',
                          value: node.dependsOnNames.isEmpty ? '—' : node.dependsOnNames.join(', '),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        _LibChip(label: 'sharp', ok: node.sharp),
                        const SizedBox(width: 5),
                        _LibChip(label: 'ffmpeg', ok: node.ffmpeg),
                      ],
                    ),
                  ),
                  if (node.stateDetail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(
                        node.stateDetail,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: node.blocked
                              ? _warnAmber
                              : (node.enabled && node.online == false
                                    ? scheme.error
                                    : scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${nodes.length} servidor${nodes.length == 1 ? '' : 'es'} · '
            '${nodes.where((n) => n.alive).length} en línea',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Menú «···» con TODAS las acciones de un servidor.
class _NodeMenu extends StatelessWidget {
  const _NodeMenu({
    required this.node,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
  });

  final NodeView node;
  final bool busy;
  final void Function(NodeView) onEdit;
  final void Function(NodeView) onToggle;
  final void Function(NodeView) onDelete;
  final void Function(NodeView) onLogs;
  final void Function(NodeView) onRestart;
  final void Function(NodeView) onUpload;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${node.name}',
      icon: const Icon(Icons.more_vert, size: 19),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit(node);
          case 'logs':
            onLogs(node);
          case 'restart':
            onRestart(node);
          case 'upload':
            onUpload(node);
          case 'toggle':
            onToggle(node);
          case 'delete':
            onDelete(node);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Editar'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logs',
          child: _MenuRow(icon: Icons.terminal_outlined, label: 'Ver terminal'),
        ),
        const PopupMenuItem(
          value: 'restart',
          child: _MenuRow(icon: Icons.restart_alt, label: 'Reiniciar servicio'),
        ),
        const PopupMenuItem(
          value: 'upload',
          child: _MenuRow(icon: Icons.upload_file_outlined, label: 'Subir al proyecto'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: _MenuRow(
            icon: node.enabled ? Icons.power_settings_new : Icons.power_outlined,
            label: node.enabled ? 'Apagar' : 'Encender',
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(icon: Icons.delete_outline, label: 'Quitar'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17),
      const SizedBox(width: 10),
      // Flexible: el menú mide 256 px y «Reiniciar servicio» con su icono no
      // cabe si el texto se queda con su ancho natural (desbordaba la fila).
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: .2,
      ),
    ),
  );
}

/// Chip de biblioteca: ✓ instalada, ✕ falta, • sin comprobar.
class _LibChip extends StatelessWidget {
  const _LibChip({required this.label, required this.ok});
  final String label;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok == null ? scheme.onSurfaceVariant : (ok! ? _okGreen : _warnAmber);
    final icon = ok == null ? Icons.help_outline : (ok! ? Icons.check : Icons.close);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _DataBit extends StatelessWidget {
  const _DataBit({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 9.5,
            letterSpacing: .6,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ==================================================================
// TERMINAL DEL SERVIDOR (solo lectura)
// ==================================================================
// Enseña el log del servicio (`journalctl -u hardstreet-drive`) y deja
// reiniciarlo. NO es una consola: no se escriben comandos, para que un botón
// de la pantalla no pueda convertirse en acceso libre al servidor.
// ==================================================================

class NodeTerminalSheet extends StatefulWidget {
  const NodeTerminalSheet({
    super.key,
    required this.serverName,
    required this.load,
    required this.onRestart,
    this.service = 'hardstreet-drive',
  });

  final String serverName;

  /// Carga el log (la página la hace contra el hub).
  final Future<String> Function() load;

  /// Reinicia el servicio del servidor.
  final Future<String> Function() onRestart;

  final String service;

  @override
  State<NodeTerminalSheet> createState() => _NodeTerminalSheetState();
}

class _NodeTerminalSheetState extends State<NodeTerminalSheet> {
  String _log = '';
  String? _error;
  bool _loading = true;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await widget.load();
      if (!mounted) return;
      setState(() {
        _log = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _restart() async {
    setState(() => _restarting = true);
    String message;
    try {
      message = await widget.onRestart();
    } catch (e) {
      message = '$e';
    }
    if (!mounted) return;
    setState(() => _restarting = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terminal · ${widget.serverName}',
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'journalctl -u ${widget.service}  ·  solo lectura',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Container(
                width: double.infinity,
                color: const Color(0xFF10151C),
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _error != null
                              ? _error!
                              : (_log.isEmpty ? '(sin líneas: el servicio no ha escrito nada)' : _log),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: compact ? 11 : 11.8,
                            height: 1.45,
                            color: _error != null ? const Color(0xFFFCA5A5) : const Color(0xFFD6E2EE),
                          ),
                        ),
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _restarting ? null : _restart,
                    icon: _restarting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reiniciar servicio'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
