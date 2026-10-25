import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../hs_format.dart';

// ==================================================================
// CONEXIÓN — DIAGRAMA DE SERVIDORES DEL DRIVE
// ==================================================================
// Los servidores del Drive se ven como un DIAGRAMA de red, no como una tabla:
//
//        ┌──────────────┐
//        │  HUB central │
//        └──┬───┬───┬───┘
//     ┌─────┘   │   └─────┐
//   ┌─┴──┐   ┌──┴─┐   ┌──┴─┐
//   │ S1 │◄─►│ S2 │   │ S3 │     ← la línea entre S1 y S2 es una DEPENDENCIA
//   └────┘   └────┘   └────┘        (con flecha en cada punta si es mutua)
//
//   · El hub es el router central: de él sale una línea a CADA servidor.
//   · Cada servidor es una card con TODA su información (estado, versión,
//     prioridad, bibliotecas, espacio, ping y de quién depende).
//   · Si un servidor depende de otro, se dibuja una línea entre los dos; si
//     la dependencia es mutua, la línea lleva flecha en AMBOS extremos.
//   · Es interactivo: se puede hacer clic en un servidor para iluminar SUS
//     conexiones, arrastrarlo para reacomodar el diagrama y usar el menú «···»
//     para editarlo, ver su terminal, reiniciarlo o subirle archivos.
//
// En pantalla angosta (celular) el diagrama no cabe: se dibujan tarjetas con
// los mismos datos, una debajo de otra, con sus dependencias en texto.
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
    this.dependsOnIds = const [],
    this.memUsed,
    this.memTotal,
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

  /// Nombres e ids de los servidores de los que depende.
  final List<String> dependsOnNames;
  final List<int> dependsOnIds;

  /// RAM consumida y total del servidor (bytes). null = el nodo todavía no
  /// informa de su memoria o no se pudo comprobar.
  final double? memUsed;
  final double? memTotal;

  bool get alive => enabled && online == true && !blocked;

  /// Lo que dice la píldora de estado.
  String get stateLabel {
    if (blocked) return 'Mantenimiento';
    if (!enabled) return 'Apagado';
    if (online == null) return 'Sin comprobar';
    return online! ? 'En línea' : 'Sin respuesta';
  }

  String get stateDetail {
    if (blocked) {
      return blockedReason ?? 'Depende de un servidor que no responde';
    }
    if (!enabled) return 'El hub no guarda nada nuevo aquí.';
    if (online == null) return 'No se pudo comprobar si responde.';
    if (online!) return '';
    final text = (error ?? '').trim();
    return text.isEmpty
        ? 'No contesta: revisa que el servicio esté corriendo.'
        : 'No contesta: $text';
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

  /// «2.10 GB / 7.7 GB» de RAM consumida, o «—» si el nodo no lo cuenta.
  String get ramLabel {
    final used = memUsed;
    final total = memTotal;
    if (used == null || total == null || total <= 0) return '—';
    return '${hsBytes(used)} / ${hsBytes(total)}';
  }

  /// Proporción de RAM en uso (0..1) para la barrita; null = sin dato.
  double? get ramRatio {
    final used = memUsed;
    final total = memTotal;
    if (used == null || total == null || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }
}

/// El HUB del Drive: el router central del diagrama.
class HubView {
  const HubView({
    required this.url,
    this.online = true,
    this.version = '',
    this.latencyMs,
    this.onlineCount = 0,
    this.totalCount = 0,
    this.blocked = 0,
    this.note = '',
  });

  final String url;
  final bool online;
  final String version;
  final int? latencyMs;
  final int onlineCount;
  final int totalCount;

  /// Servidores bloqueados por dependencia (el hub está en mantenimiento).
  final int blocked;
  final String note;

  String get latencyLabel {
    final ms = latencyMs;
    if (ms == null) return '—';
    return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
  }

  Color get color {
    if (!online) return const Color(0xFFDC2626);
    if (blocked > 0 || (totalCount > 0 && onlineCount < totalCount)) {
      return _warnAmber;
    }
    return _okGreen;
  }
}

/// Aristas de DEPENDENCIA que dibuja el diagrama.
///
/// Devuelve un solo par por relación: si A depende de B y B de A, sale UNA
/// arista `mutual: true` (la línea lleva flecha en las dos puntas), nunca dos
/// líneas encimadas. Se descartan ids que no existen en la lista.
List<({int from, int to, bool mutual})> topologyDependencyEdges(
  List<NodeView> nodes,
) {
  final byId = {for (final n in nodes) n.id: n};
  final seen = <String>{};
  final out = <({int from, int to, bool mutual})>[];
  for (final node in nodes) {
    for (final depId in node.dependsOnIds) {
      final target = byId[depId];
      if (target == null || depId == node.id) continue;
      final mutual = target.dependsOnIds.contains(node.id);
      final key = mutual
          ? ([node.id, depId]..sort()).join('-')
          : '${node.id}>$depId';
      if (!seen.add(key)) continue;
      out.add((from: node.id, to: depId, mutual: mutual));
    }
  }
  return out;
}

const double _cardW = 268;
const double _cardH = 300;
const double _hubW = 312;
const double _hubH = 172;
const double _rowGap = 74;
const double _padX = 14;
const double _gapX = 26;

/// Diagrama interactivo de los servidores del Drive.
class NodesTopology extends StatefulWidget {
  const NodesTopology({
    super.key,
    required this.nodes,
    required this.hub,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
    this.onConfigureHub,
    this.busyId,
    this.picked = const {},
    this.selectMode = false,
    this.onPick,
  });

  final List<NodeView> nodes;
  final HubView hub;
  final void Function(NodeView) onEdit;
  final void Function(NodeView) onToggle;
  final void Function(NodeView) onDelete;
  final void Function(NodeView) onLogs;
  final void Function(NodeView) onRestart;
  final void Function(NodeView) onUpload;

  /// Servidor con una acción en curso (se marca con un girador).
  final int? busyId;

  /// Abre el modal de DEPENDENCIAS de un servidor.
  final void Function(NodeView) onDependencies;

  /// Abre la configuración del HUB (dirección del Drive).
  final VoidCallback? onConfigureHub;

  /// Servidores marcados para una acción en lote (subir el proyecto…).
  final Set<int> picked;

  /// Modo selección: tocar una card la marca en vez de solo iluminarla.
  final bool selectMode;
  final ValueChanged<NodeView>? onPick;

  /// Debajo de este ancho (el DEL DIAGRAMA, no el de la ventana) no cabe:
  /// se dibujan tarjetas. En computadora convive con el panel lateral.
  static const double compactWidth = 740;

  @override
  State<NodesTopology> createState() => _NodesTopologyState();
}

class _NodesTopologyState extends State<NodesTopology> {
  /// Desplazamientos manuales (arrastrar una card): id → delta.
  final Map<int, Offset> _moved = {};

  /// Servidor seleccionado: se iluminan SUS líneas (clic para quitar).
  int? _selected;

  @override
  void didUpdateWidget(covariant NodesTopology old) {
    super.didUpdateWidget(old);
    // Un servidor que ya no existe no puede seguir seleccionado ni movido.
    final ids = widget.nodes.map((n) => n.id).toSet();
    _moved.removeWhere((id, _) => !ids.contains(id));
    if (_selected != null && !ids.contains(_selected)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1180.0;
        // El ancho que importa es el QUE TIENE el diagrama (en computadora
        // convive con el panel lateral), no el de la ventana: así nunca se
        // dibujan cards demasiado angostas.
        if (width < NodesTopology.compactWidth) return _compactCards(context);
        final perRow = width >= 1120 ? 3 : 2;
        final usable = width - 2 * _padX - (perRow - 1) * _gapX;
        final cardW = math.min(_cardW, usable / perRow);
        final rows = widget.nodes.isEmpty
            ? 0
            : ((widget.nodes.length - 1) ~/ perRow) + 1;

        final hubTop = 6.0;
        final hub = Rect.fromLTWH((width - _hubW) / 2, hubTop, _hubW, _hubH);
        final rowsTop = hub.bottom + _rowGap;

        // Reparto en filas, cada una centrada (así el árbol se ve equilibrado
        // aunque en la última fila queden menos servidores).
        final cards = <int, Rect>{};
        for (var i = 0; i < widget.nodes.length; i++) {
          final node = widget.nodes[i];
          final row = i ~/ perRow;
          final inRow = math.min(perRow, widget.nodes.length - row * perRow);
          final rowWidth = inRow * cardW + (inRow - 1) * _gapX;
          final left = (width - rowWidth) / 2 + (i % perRow) * (cardW + _gapX);
          final top = rowsTop + row * (_cardH + _rowGap);
          final base = Rect.fromLTWH(left, top, cardW, _cardH);
          final delta = _moved[node.id] ?? Offset.zero;
          cards[node.id] = base.shift(delta);
        }

        final height = widget.nodes.isEmpty
            ? hub.bottom + 24
            : rowsTop + rows * (_cardH + _rowGap) - _rowGap + 34;

        return SizedBox(
          key: const ValueKey('drive-topology'),
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Fondo con puntos: da la sensación de lienzo/diagrama.
              Positioned.fill(
                child: CustomPaint(
                  painter: _CanvasDotsPainter(
                    color: scheme.outlineVariant.withValues(alpha: .45),
                  ),
                ),
              ),
              // Líneas: hub → servidor y dependencias entre servidores.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _TopologyPainter(
                      hub: hub,
                      cards: cards,
                      nodes: widget.nodes,
                      selectedId: _selected,
                      grid: scheme.outlineVariant,
                      accent: scheme.primary,
                    ),
                  ),
                ),
              ),
              // El hub, en el centro de arriba (el router de la red).
              Positioned.fromRect(
                rect: hub,
                child: _HubCard(
                  hub: widget.hub,
                  onConfigure: widget.onConfigureHub,
                ),
              ),
              // Si se movió alguna card, se puede volver al orden automático.
              if (_moved.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _moved.clear();
                      _selected = null;
                    }),
                    icon: const Icon(Icons.center_focus_strong, size: 16),
                    label: const Text('Reordenar'),
                  ),
                ),
              for (final node in widget.nodes)
                if (cards[node.id] != null)
                  Positioned.fromRect(
                    rect: cards[node.id]!,
                    child: _DraggableCard(
                      offset: _moved[node.id] ?? Offset.zero,
                      onMoved: (delta) => setState(() {
                        _moved[node.id] = delta;
                      }),
                      child: _NodeCard(
                        node: node,
                        busy: widget.busyId == node.id,
                        selected:
                            _selected == node.id ||
                            widget.picked.contains(node.id),
                        dimmed: _selected != null && _selected != node.id,
                        selectMode: widget.selectMode,
                        picked: widget.picked.contains(node.id),
                        onPick: () => widget.onPick?.call(node),
                        onTap: () => setState(
                          () =>
                              _selected = _selected == node.id ? null : node.id,
                        ),
                        onEdit: () => widget.onEdit(node),
                        onToggle: () => widget.onToggle(node),
                        onDelete: () => widget.onDelete(node),
                        onLogs: () => widget.onLogs(node),
                        onRestart: () => widget.onRestart(node),
                        onUpload: () => widget.onUpload(node),
                        onDependencies: () => widget.onDependencies(node),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- CELULAR: tarjetas, sin diagrama ----------------

  Widget _compactCards(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _HubCard(hub: widget.hub, onConfigure: widget.onConfigureHub),
        const SizedBox(height: 12),
        for (final node in widget.nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MobileNodeCard(
              node: node,
              busy: widget.busyId == node.id,
              onEdit: () => widget.onEdit(node),
              onToggle: () => widget.onToggle(node),
              onDelete: () => widget.onDelete(node),
              onLogs: () => widget.onLogs(node),
              onRestart: () => widget.onRestart(node),
              onUpload: () => widget.onUpload(node),
              onDependencies: () => widget.onDependencies(node),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${widget.nodes.length} servidor${widget.nodes.length == 1 ? '' : 'es'} · '
            '${widget.nodes.where((n) => n.alive).length} en línea',
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

/// Permite ARRASTRAR una card para reacomodar el diagrama.
class _DraggableCard extends StatefulWidget {
  const _DraggableCard({
    required this.child,
    required this.offset,
    required this.onMoved,
  });

  final Widget child;
  final Offset offset;
  final ValueChanged<Offset> onMoved;

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Cada actualización suma SU delta al desplazamiento actual: el padre
        // reconstruye con la posición nueva y el arrastre sigue pegado al
        // puntero (sin saltos ni acumulaciones dobles).
        onPanUpdate: (d) => widget.onMoved(widget.offset + d.delta),
        child: widget.child,
      ),
    );
  }
}

/// Card de un servidor dentro del diagrama (toda su ficha).
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.busy,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
    this.selectMode = false,
    this.picked = false,
    this.onPick,
  });

  final NodeView node;
  final bool busy;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onLogs;
  final VoidCallback onRestart;
  final VoidCallback onUpload;
  final VoidCallback onDependencies;

  /// Modo selección (subir el proyecto a varios servidores a la vez).
  final bool selectMode;
  final bool picked;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = node.color;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: dimmed ? .55 : 1,
      child: Tooltip(
        message: node.notes.isEmpty ? node.name : '${node.name}\n${node.notes}',
        waitDuration: const Duration(milliseconds: 600),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : accent.withValues(alpha: .45),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: scheme.primary.withValues(alpha: .22),
                  blurRadius: 18,
                  spreadRadius: 1,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filo con el color del estado: se reconoce de reojo.
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // En modo selección, la casilla manda: marcar aquí es
                          // elegir el servidor para la acción en lote.
                          if (selectMode)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: GestureDetector(
                                onTap: onPick,
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: Checkbox(
                                    key: ValueKey('node-pick-${node.id}'),
                                    value: picked,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (_) => onPick?.call(),
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: GestureDetector(
                              onTap: selectMode ? onPick : onTap,
                              child: Text(
                                node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
                            _NodeMenu(
                              node: node,
                              onEdit: onEdit,
                              onToggle: onToggle,
                              onDelete: onDelete,
                              onLogs: onLogs,
                              onRestart: onRestart,
                              onUpload: onUpload,
                              onDependencies: onDependencies,
                            ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          node.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Wrap y no Row: con la card más angosta (cuando convive
                      // con el panel lateral) los dos chips pueden no caber.
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatePill(label: node.stateLabel, color: accent),
                          _ChipBit(
                            icon: Icons.speed_rounded,
                            label: node.latencyLabel,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      // DESCRIPCIÓN del servidor: para qué se usa. Va aquí,
                      // en la card, no escondida en el tooltip o en «Editar».
                      if (node.notes.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            node.notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.25,
                              fontStyle: FontStyle.italic,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _DataBit(
                            label: 'versión',
                            value: node.version.isEmpty
                                ? '—'
                                : 'v${node.version}',
                          ),
                          const SizedBox(width: 14),
                          _DataBit(
                            label: 'prioridad',
                            value: node.priority?.toString() ?? '—',
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _LibChip(label: 'sharp', ok: node.sharp),
                          const SizedBox(width: 5),
                          _LibChip(label: 'ffmpeg', ok: node.ffmpeg),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: node.diskRatio,
                                  minHeight: 5,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  color: (node.diskRatio ?? 0) >= .9
                                      ? scheme.error
                                      : accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              node.diskLabel,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // RAM consumida (lo que pide el panel: ver si un nodo
                      // está ahogado sin entrar por SSH).
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Text(
                              'RAM',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 8,
                                letterSpacing: .4,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: node.ramRatio,
                                  minHeight: 4,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  color: (node.ramRatio ?? 0) >= .9
                                      ? scheme.error
                                      : _warnAmber,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              node.ramLabel,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (node.stateDetail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 2),
                          child: Text(
                            node.stateDetail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: node.blocked ? _warnAmber : _offGrey,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_tree_outlined,
                              size: 12,
                              color: node.dependsOnNames.isEmpty
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                node.dependsOnNames.isEmpty
                                    ? 'independiente'
                                    : 'depende de '
                                          '${node.dependsOnNames.join(', ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: node.dependsOnNames.isEmpty
                                      ? FontWeight.w400
                                      : FontWeight.w700,
                                  color: node.dependsOnNames.isEmpty
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta del HUB: el router central del diagrama.
class _HubCard extends StatelessWidget {
  const _HubCard({required this.hub, this.onConfigure});

  final HubView hub;

  /// Abre la configuración del HUB (dirección del Drive, respaldos). Las
  /// opciones del hub viven AQUÍ, no sueltas en la página.
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hub.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .16),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.hub_rounded, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HUB del Drive',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                    ),
                    Text(
                      hub.url.isEmpty ? 'sin dirección' : hub.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onConfigure != null)
                IconButton(
                  tooltip: 'Configurar hub',
                  key: const ValueKey('hub-configure'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onConfigure,
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipBit(
                icon: hub.online
                    ? Icons.check_circle_outline_rounded
                    : Icons.cloud_off_outlined,
                label: hub.online ? 'en línea' : 'sin respuesta',
                color: color,
              ),
              if (hub.version.isNotEmpty)
                _ChipBit(
                  icon: Icons.info_outline_rounded,
                  label: 'v${hub.version}',
                  color: scheme.onSurfaceVariant,
                ),
              _ChipBit(
                icon: Icons.speed_rounded,
                label: hub.latencyLabel,
                color: scheme.onSurfaceVariant,
              ),
              _ChipBit(
                icon: Icons.dns_outlined,
                label:
                    '${hub.onlineCount} de ${hub.totalCount} '
                    'servidor${hub.totalCount == 1 ? '' : 'es'}',
                color: hub.totalCount > 0 && hub.onlineCount < hub.totalCount
                    ? _warnAmber
                    : _okGreen,
              ),
              if (hub.blocked > 0)
                _ChipBit(
                  icon: Icons.engineering_outlined,
                  label: '${hub.blocked} en mantenimiento',
                  color: _warnAmber,
                ),
            ],
          ),
          if (hub.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hub.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.25,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de servidor en pantalla angosta (sin diagrama).
class _MobileNodeCard extends StatelessWidget {
  const _MobileNodeCard({
    required this.node,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
  });

  final NodeView node;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onLogs;
  final VoidCallback onRestart;
  final VoidCallback onUpload;
  final VoidCallback onDependencies;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: node.color.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(0, 10, 4, 10),
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
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  _NodeMenu(
                    node: node,
                    onEdit: onEdit,
                    onToggle: onToggle,
                    onDelete: onDelete,
                    onLogs: onLogs,
                    onRestart: onRestart,
                    onUpload: onUpload,
                    onDependencies: onDependencies,
                  ),
              ],
            ),
          ),
          if (node.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                node.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DataBit(
                  label: 'versión',
                  value: node.version.isEmpty ? '—' : 'v${node.version}',
                ),
                _DataBit(
                  label: 'prioridad',
                  value: node.priority?.toString() ?? '—',
                ),
                _DataBit(label: 'ping', value: node.latencyLabel),
                _DataBit(label: 'espacio', value: node.diskLabel),
                _DataBit(label: 'RAM', value: node.ramLabel),
                _DataBit(
                  label: 'depende de',
                  value: node.dependsOnNames.isEmpty
                      ? '—'
                      : node.dependsOnNames.join(', '),
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
    );
  }
}

/// Menú «···» con TODAS las acciones de un servidor.
class _NodeMenu extends StatelessWidget {
  const _NodeMenu({
    required this.node,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
  });

  final NodeView node;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onLogs;
  final VoidCallback onRestart;
  final VoidCallback onUpload;
  final VoidCallback onDependencies;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${node.name}',
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      iconSize: 18,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'deps':
            onDependencies();
          case 'logs':
            onLogs();
          case 'restart':
            onRestart();
          case 'upload':
            onUpload();
          case 'toggle':
            onToggle();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Editar'),
        ),
        const PopupMenuItem(
          value: 'deps',
          child: _MenuRow(
            icon: Icons.account_tree_outlined,
            label: 'Dependencias',
          ),
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
          child: _MenuRow(
            icon: Icons.upload_file_outlined,
            label: 'Subir al proyecto',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: _MenuRow(
            icon: node.enabled
                ? Icons.power_settings_new
                : Icons.power_outlined,
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

/// Chip pequeño con icono (estado del hub, ping…).
class _ChipBit extends StatelessWidget {
  const _ChipBit({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
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
    final color = ok == null
        ? scheme.onSurfaceVariant
        : (ok! ? _okGreen : _warnAmber);
    final icon = ok == null
        ? Icons.help_outline
        : (ok! ? Icons.check : Icons.close);
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
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
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
            fontSize: 8.5,
            letterSpacing: .5,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// LIENZO
// ==================================================================

/// Fondo de puntos (un lienzo de diagrama, no una tabla).
class _CanvasDotsPainter extends CustomPainter {
  _CanvasDotsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .35);
    const step = 22.0;
    for (var y = step; y < size.height; y += step) {
      for (var x = step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasDotsPainter old) => old.color != color;
}

/// Dibuja las líneas del diagrama.
///
///   1. HUB → cada servidor (la conexión de la red).
///   2. Servidor → servidor por cada DEPENDENCIA, con flecha en el servidor
///      del que se depende; si es MUTUA, la flecha va en las dos puntas.
///
/// Las líneas de un servidor que no responde (o está bloqueado) van
/// punteadas: se ve de un vistazo qué tramo está roto sin leer nada.
class _TopologyPainter extends CustomPainter {
  _TopologyPainter({
    required this.hub,
    required this.cards,
    required this.nodes,
    required this.selectedId,
    required this.grid,
    required this.accent,
  });

  final Rect hub;
  final Map<int, Rect> cards;
  final List<NodeView> nodes;
  final int? selectedId;
  final Color grid;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final n in nodes) n.id: n};

    // --- HUB → servidor ---
    for (final node in nodes) {
      final rect = cards[node.id];
      if (rect == null) continue;
      final focused = selectedId == null || selectedId == node.id;
      final color = node.color.withValues(alpha: focused ? .85 : .25);
      final paint = Paint()
        ..color = color
        ..strokeWidth = focused ? 2 : 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final start = Offset(hub.center.dx, hub.bottom);
      final end = Offset(rect.center.dx, rect.top);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx,
          start.dy + (end.dy - start.dy) * .55,
          end.dx,
          end.dy - (end.dy - start.dy) * .55,
          end.dx,
          end.dy,
        );
      if (node.alive) {
        canvas.drawPath(path, paint);
      } else {
        _dashed(canvas, path, paint);
      }
      _arrow(canvas, Offset(end.dx, end.dy - 2), const Offset(0, 1), color);
    }

    // --- DEPENDENCIAS entre servidores ---
    for (final edge in topologyDependencyEdges(nodes)) {
      final node = byId[edge.from];
      final target = byId[edge.to];
      final from = cards[edge.from];
      final to = cards[edge.to];
      if (node == null || target == null || from == null || to == null) {
        continue;
      }
      final mutual = edge.mutual;
      final broken =
          !node.alive || !target.alive || node.blocked || target.blocked;
      final focused =
          selectedId == null ||
          selectedId == node.id ||
          selectedId == target.id;
      final color = (broken ? _warnAmber : accent).withValues(
        alpha: focused ? .9 : .22,
      );
      final paint = Paint()
        ..color = color
        ..strokeWidth = focused ? 1.9 : 1.1
        ..style = PaintingStyle.stroke;

      // La línea sale y entra por los costados y se arquea, para no
      // confundirse con las del hub.
      final startSide = from.center.dx <= to.center.dx ? from.right : from.left;
      final endSide = from.center.dx <= to.center.dx ? to.left : to.right;
      final start = Offset(startSide, from.center.dy);
      final end = Offset(endSide, to.center.dy);
      final mid = (start + end) / 2;
      final bow = (to.center.dy - from.center.dy) * .35;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(mid.dx, start.dy + bow, mid.dx, end.dy + bow, end.dx, end.dy);
      if (broken) {
        _dashed(canvas, path, paint, dash: 5, gap: 4);
      } else {
        canvas.drawPath(path, paint);
      }
      final dir = (end - Offset(mid.dx, end.dy + bow));
      _arrow(canvas, end, dir.distance == 0 ? const Offset(1, 0) : dir, color);
      if (mutual) {
        final back = (start - Offset(mid.dx, start.dy + bow));
        _arrow(
          canvas,
          start,
          back.distance == 0 ? const Offset(-1, 0) : back,
          color,
        );
      }
    }
  }

  /// Pinta una punta de flecha en [tip], orientada según [direction].
  void _arrow(Canvas canvas, Offset tip, Offset direction, Color color) {
    final d = direction.distance == 0 ? const Offset(1, 0) : direction;
    final angle = math.atan2(d.dy, d.dx);
    const len = 7.0;
    const spread = .42;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final p1 = tip;
    final p2 =
        tip - Offset(math.cos(angle - spread), math.sin(angle - spread)) * len;
    final p3 =
        tip - Offset(math.cos(angle + spread), math.sin(angle + spread)) * len;
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close(),
      paint,
    );
  }

  /// Trazo discontinuo (para lo que no responde).
  void _dashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 7,
    double gap = 5,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter old) {
    if (old.hub != hub ||
        old.selectedId != selectedId ||
        old.nodes.length != nodes.length ||
        old.cards.length != cards.length) {
      return true;
    }
    for (final entry in cards.entries) {
      if (old.cards[entry.key] != entry.value) return true;
    }
    return true;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
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
                              : (_log.isEmpty
                                    ? '(sin líneas: el servicio no ha escrito nada)'
                                    : _log),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: compact ? 11 : 11.8,
                            height: 1.45,
                            color: _error != null
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFD6E2EE),
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
