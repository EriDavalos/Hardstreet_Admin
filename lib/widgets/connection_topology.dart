import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.os = '',
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

  /// Sistema operativo del servidor ya legible («Ubuntu 24.04 LTS · x64»).
  /// Lo informa cada nodo en su `/api/health`; vacío = no lo reporta.
  final String os;
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
    // APAGADO (`enabled = 0`): el servicio del servidor sigue corriendo; lo
    // que se apaga es su participación en el Drive, así que su contenido no
    // aparece y quien dependa de él queda en mantenimiento.
    if (!enabled) {
      return 'Apagado en el Drive: sus carpetas no se ven y no recibe archivos '
          'nuevos. Quien dependa de él queda en mantenimiento. El servicio del '
          'servidor y sus archivos NO se tocan.';
    }
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

// Ancho máximo de la card. Estrecha a propósito: la ficha se lee de un vistazo
// y, con dos o tres servidores, el diagrama se ve como una ESTRELLA (el HUB en
// el centro y las cards alrededor) en vez de dos fichas enormes que se comen
// todo el lienzo. Las letras y los datos NO se achican.
const double _cardWMax = 400;
// Ancho con el que una card se ve cómoda: de ahí sale CUÁNTAS caben por fila.
const double _cardWWish = 400;
// Por debajo de esto la card ya no se lee: se baja una columna antes.
const double _cardWMin = 340;
// La card lleva la ficha completa: nombre, dirección, estado, descripción y SO.
// Con la descripción y el SO hacían falta ~30 px más (antes 300 y el contenido
// quedaba sin aire: el `Spacer` desaparecía).
const double _cardH = 332;
const double _hubW = 380;
// El HUB mide lo que mide su contenido (título + chips + aviso). Antes eran
// 172 px fijos y la card quedaba con un hueco vacío debajo de los chips.
const double _hubH = 140;
// Aire entre cards: las filas y las columnas se separan bastante para que no
// se lean como un bloque y un toque no caiga justo en el borde de la vecina.
const double _rowGap = 104;
const double _padX = 14;
const double _gapX = 44;

/// Diagrama interactivo de los servidores del Drive.
class NodesTopology extends StatefulWidget {
  const NodesTopology({
    super.key,
    required this.nodes,
    required this.hub,
    required this.onEdit,
    required this.onToggle,
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
  /// Desplazamientos manuales (pulsación larga + arrastrar): POSICIÓN → delta.
  ///
  /// Se guarda por posición y no por id a propósito: dos servidores sin id
  /// propio (o con el id del .env del hub repetido) compartían la misma clave,
  /// así que mover o seleccionar uno movía y marcaba al otro.
  final Map<int, Offset> _moved = {};

  /// Servidor seleccionado (por posición): se iluminan SUS líneas.
  int? _selected;

  /// La selección se quita SOLA a los 4 s (o con Esc): enfocar un servidor es
  /// para mirar ese momento, no un modo que se queda pegado.
  Timer? _selectionTimer;
  static const Duration _selectionTtl = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    // Esc quita el foco desde cualquier parte del panel (la página no tiene un
    // campo con foco cuando se está mirando el diagrama).
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (_selected == null) return false;
    // Con una ventana encima (terminal, editar…) Esc es para cerrarla.
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    _clearSelection();
    return true;
  }

  /// Enfoca (o desenfoca) un servidor y arma el reloj de los 4 s.
  void _select(int index) {
    _selectionTimer?.cancel();
    final next = _selected == index ? null : index;
    setState(() => _selected = next);
    if (next == null) return;
    _selectionTimer = Timer(_selectionTtl, () {
      if (!mounted || _selected == null) return;
      setState(() => _selected = null);
    });
  }

  void _clearSelection() {
    _selectionTimer?.cancel();
    if (_selected == null) return;
    setState(() => _selected = null);
  }

  @override
  void didUpdateWidget(covariant NodesTopology old) {
    super.didUpdateWidget(old);
    // Una card que ya no existe no puede seguir seleccionada ni movida.
    final total = widget.nodes.length;
    _moved.removeWhere((index, _) => index >= total);
    if (_selected != null && _selected! >= total) {
      _selectionTimer?.cancel();
      _selected = null;
    }
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
        // Columnas: las que caben con una card de ancho cómodo, con un tope de
        // dos mientras sean poco servidores y de tres cuando ya hay muchos.
        // Después se reparten en filas ARRIBA y ABAJO del HUB (estrella).
        final total = widget.nodes.length;
        final maxCols = total <= 4 ? 2 : 3;
        // Columnas que caben con una card del ancho cómodo, nunca tan angosta
        // que la letra se apriete (se quita una columna antes de bajar de
        // _cardWMin).
        var perRow = ((width - 2 * _padX + _gapX) / (_cardWWish + _gapX))
            .round()
            .clamp(1, maxCols);
        while (perRow > 1 &&
            (width - 2 * _padX - (perRow - 1) * _gapX) / perRow < _cardWMin) {
          perRow--;
        }
        // ---- GRUPOS DE DEPENDENCIA ----
        //
        // Un servidor y aquel del que depende se colocan JUNTOS. Antes se
        // repartían por orden de prioridad y podían caer uno ARRIBA y otro
        // ABAJO del HUB: la línea de la relación lo cruzaba por encima y se
        // veía mal. Ahora los grupos (componentes de dependencias) van en
        // filas contiguas y no se parten si caben enteros.
        final groups = _dependencyGroups();

        var rows = 0;
        if (total > 0) {
          perRow = math.min(perRow, total);
          // Dos servidores RELACIONADOS van en UNA fila (del mismo lado del
          // HUB): la relación es una línea corta entre vecinos. Solo si el
          // ancho no da para dos cards legibles se deja uno arriba y otro
          // abajo; entonces la línea rodea el HUB por fuera.
          final canPair = (width - 2 * _padX - _gapX) / 2 >= _cardWMin;
          if (groups.length == 1 && total == 2 && canPair) {
            perRow = 2;
          } else if (total >= 2) {
            // Con DOS servidores sin relación en una sola fila el HUB quedaría
            // arriba y no en el medio: se usa una card por fila (uno arriba,
            // otro abajo).
            perRow = math.min(perRow, (total + 1) ~/ 2);
          }
          rows = ((total - 1) ~/ perRow) + 1;
          // Reparto EQUILIBRADO: si la última fila quedaría casi vacía (4 en
          // columnas de 3 = 3 + 1 no; 5 = 3 + 2 sí), se usa una columna menos.
          // Cada fila sale centrada, así que la estrella queda simétrica.
          perRow = ((total - 1) ~/ rows) + 1;
        }

        // Filas, metiendo grupos ENTEROS: un grupo solo se corta si es más
        // grande que una fila entera (no cabría de otra forma).
        final rowItems = <List<int>>[];
        var currentRow = <int>[];
        for (final group in groups) {
          if (group.length > perRow) {
            for (final i in group) {
              if (currentRow.length == perRow) {
                rowItems.add(currentRow);
                currentRow = [];
              }
              currentRow.add(i);
            }
            continue;
          }
          if (currentRow.isNotEmpty &&
              currentRow.length + group.length > perRow) {
            rowItems.add(currentRow);
            currentRow = [];
          }
          currentRow.addAll(group);
        }
        if (currentRow.isNotEmpty) rowItems.add(currentRow);
        rows = rowItems.length;

        final usable = width - 2 * _padX - (perRow - 1) * _gapX;
        final cardW = math.min(_cardWMax, usable / perRow);

        // ---- ESTRELLA: el HUB en el MEDIO y las cards alrededor ----
        //
        // Antes el HUB iba arriba y todas las cards colgaban debajo (un árbol).
        // El diseño es una ESTRELLA: el HUB ocupa el centro del lienzo y los
        // servidores se reparten en filas ARRIBA y ABAJO, alternando (la fila
        // 0 es la más cercana al HUB por arriba, la 1 la más cercana por abajo,
        // la 2 la siguiente arriba…). Así las líneas salen del HUB en todas
        // direcciones y con dos, tres o cinco servidores el conjunto queda
        // centrado en él en vez de colgando de una esquina.
        final rowsAbove = rows <= 1 ? 0 : (rows + 1) ~/ 2; // filas pares
        // Alto que ocupan las filas de arriba, MÁS el aire hasta el HUB (cada
        // fila reserva `_rowGap` por delante; la de abajo hace lo mismo).
        final aboveHeight = rowsAbove * (_cardH + _rowGap);
        const double padY = 22.0;
        final hubTop = padY + aboveHeight;
        final hub = Rect.fromLTWH((width - _hubW) / 2, hubTop, _hubW, _hubH);

        // Reparto en filas, cada una centrada (así la estrella se ve equilibrada
        // aunque en la última fila queden menos servidores).
        final cards = <int, Rect>{}; // por id (lo usan las líneas)
        final slots = <int, Rect>{}; // por posición (lo usa cada card)
        var lowerBottom = hub.bottom;
        for (var r = 0; r < rowItems.length; r++) {
          final rowNodes = rowItems[r];
          final rowWidth =
              rowNodes.length * cardW + (rowNodes.length - 1) * _gapX;
          final left0 = (width - rowWidth) / 2;
          final double top;
          // Con UNA sola fila todo va DEBAJO del HUB: si se tratara como
          // «fila 0 = arriba» quedaría en negativo y fuera del lienzo (se
          // pintaba pero no se podía tocar).
          final above = rowsAbove > 0 && r.isEven;
          if (above) {
            // Arriba: la fila 0 pegada al HUB y las siguientes hacia afuera.
            final k = r ~/ 2;
            top = hub.top - _rowGap - (k + 1) * _cardH - k * _rowGap;
          } else {
            // Abajo: la fila 1 es la más cercana al HUB.
            final k = r ~/ 2;
            top = hub.bottom + _rowGap + k * (_cardH + _rowGap);
            lowerBottom = math.max(lowerBottom, top + _cardH);
          }
          for (var c = 0; c < rowNodes.length; c++) {
            final i = rowNodes[c];
            final node = widget.nodes[i];
            final base = Rect.fromLTWH(
              left0 + c * (cardW + _gapX),
              top,
              cardW,
              _cardH,
            );
            final delta = _moved[i] ?? Offset.zero;
            slots[i] = base.shift(delta);
            cards[node.id] = slots[i]!;
          }
        }

        // El alto sale del contenido real (arriba + HUB + abajo), nunca de una
        // fórmula fija: así el HUB queda centrado con cualquier número de
        // servidores y con las cards movidas a mano.
        final height = widget.nodes.isEmpty
            ? hub.bottom + padY
            : math.max(hub.bottom + padY, lowerBottom + padY);

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
                      selectedId: _selected == null
                          ? null
                          : widget.nodes[_selected!].id,
                      grid: scheme.outlineVariant,
                      accent: scheme.primary,
                    ),
                  ),
                ),
              ),
              // El hub, en el CENTRO: es el router de la estrella.
              Positioned.fromRect(
                key: const ValueKey('drive-topology-hub'),
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
                    onPressed: () {
                      setState(_moved.clear);
                      _clearSelection();
                    },
                    icon: const Icon(Icons.center_focus_strong, size: 16),
                    label: const Text('Reordenar'),
                  ),
                ),
              for (var i = 0; i < widget.nodes.length; i++)
                if (slots[i] != null)
                  Positioned.fromRect(
                    rect: slots[i]!,
                    child: _DraggableCard(
                      offset: _moved[i] ?? Offset.zero,
                      onMoved: (delta) => setState(() {
                        _moved[i] = delta;
                      }),
                      child: _NodeCard(
                        node: widget.nodes[i],
                        busy: widget.busyId == widget.nodes[i].id,
                        selected:
                            _selected == i ||
                            widget.picked.contains(widget.nodes[i].id),
                        selectMode: widget.selectMode,
                        picked: widget.picked.contains(widget.nodes[i].id),
                        onPick: () => widget.onPick?.call(widget.nodes[i]),
                        onTap: () => _select(i),
                        onEdit: () => widget.onEdit(widget.nodes[i]),
                        onToggle: () => widget.onToggle(widget.nodes[i]),
                        onLogs: () => widget.onLogs(widget.nodes[i]),
                        onRestart: () => widget.onRestart(widget.nodes[i]),
                        onUpload: () => widget.onUpload(widget.nodes[i]),
                        onDependencies: () =>
                            widget.onDependencies(widget.nodes[i]),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Grupos de servidores unidos por DEPENDENCIAS (componentes conexas):
  /// `[[Bodega, Respaldo], [Estudio]]`.
  ///
  /// Dentro de cada grupo va PRIMERO el servidor del que dependen los demás y
  /// después sus dependientes: así se lee «Bodega → Respaldo» y la línea que
  /// los une es corta (van en la misma fila). Los ids que no existen en la
  /// lista se ignoran, igual que en [topologyDependencyEdges].
  List<List<int>> _dependencyGroups() {
    final n = widget.nodes.length;
    if (n == 0) return const [];
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    final indexById = <int, int>{
      for (var i = 0; i < n; i++) widget.nodes[i].id: i,
    };
    for (var i = 0; i < n; i++) {
      for (final dep in widget.nodes[i].dependsOnIds) {
        final j = indexById[dep];
        if (j == null || j == i) continue;
        final a = find(i);
        final b = find(j);
        if (a != b) parent[b] = a;
      }
    }

    final byRoot = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      byRoot.putIfAbsent(find(i), () => []).add(i);
    }
    return [
      for (final g in byRoot.values)
        (g..sort((a, b) {
          final da = widget.nodes[a].dependsOnIds.isEmpty ? 0 : 1;
          final db = widget.nodes[b].dependsOnIds.isEmpty ? 0 : 1;
          return da != db ? da - db : a - b;
        })),
    ];
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
  /// Dónde estaba la card cuando se levantó el dedo/ratón.
  Offset _start = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Se mueve SOLO con pulsación larga. Antes bastaba un arrastre con un
        // pelín de movimiento para correr la card unos píxeles: el toque de
        // "seleccionar" acababa moviéndola y parecía que se movía otra.
        onLongPressStart: (_) => setState(() {
          _start = widget.offset;
          _dragging = true;
        }),
        onLongPressMoveUpdate: (d) =>
            widget.onMoved(_start + d.offsetFromOrigin),
        onLongPressEnd: (_) => setState(() => _dragging = false),
        onLongPressCancel: () {
          if (_dragging) setState(() => _dragging = false);
        },
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
    required this.onTap,
    required this.onEdit,
    required this.onToggle,
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
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
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
    // `Semantics(selected:)` es lo que dice QUÉ servidor está enfocado (y lo
    // lee el lector de pantalla): las demás cards NO se atenúan ni se ocultan,
    // solo se destaca la elegida.
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: node.notes.isEmpty ? node.name : '${node.name}\n${node.notes}',
        waitDuration: const Duration(milliseconds: 600),
        // MANUAL: con el disparo automático, la pulsación larga —que ahora es
        // la que MUEVE la card— abría el globo de la descripción encima del
        // diagrama. Con ratón se sigue viendo al pasar por encima.
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          // Toda la card responde al toque (antes solo el NOMBRE): seleccionar
          // un servidor nunca depende de acertarle a la letra.
          behavior: HitTestBehavior.opaque,
          onTap: selectMode ? onPick : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            // Recorta el filo de color a las esquinas de la card: sin esto la
            // línea verde de arriba sobresalía por los lados y parecía suelta.
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              // El borde mantiene SU ancho al seleccionar: si engordaba, el
              // contenido se corría un píxel y la card parecía moverse.
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : accent.withValues(alpha: .45),
                width: 1.4,
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
                // Filo con el color del estado: se reconoce de reojo. El
                // radio es el de la card menos su borde (16 - 1.4) para que
                // encaje con la esquina redondeada.
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14.6),
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
                              // Indicador propio y COMPACTO: el Checkbox de
                              // Material dentro de una card de 268-320 px se
                              // comía el renglón y se veía desalineado con el
                              // nombre. Aquí basta un cuadradito con su ✓ (la
                              // card entera ya marca al tocarla).
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: AnimatedContainer(
                                  key: ValueKey('node-pick-${node.id}'),
                                  duration: const Duration(milliseconds: 140),
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: picked
                                        ? scheme.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: picked
                                          ? scheme.primary
                                          : scheme.outline,
                                      width: 1.4,
                                    ),
                                  ),
                                  child: picked
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 13,
                                          color: scheme.onPrimary,
                                        )
                                      : null,
                                ),
                              ),
                            // La card se lee como un SERVIDOR: su rack con el
                            // foco de estado encendido encima, no un punto
                            // suelto. El nombre va al lado, con la dirección
                            // debajo (en la misma cabecera: así la ficha no
                            // crece al hacerse más estrecha).
                            _ServerBadge(color: accent),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    node.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    node.url,
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
                                onLogs: onLogs,
                                onRestart: onRestart,
                                onUpload: onUpload,
                                onDependencies: onDependencies,
                              ),
                          ],
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
                        // en la card, no escondida en el tooltip o en «Editar»,
                        // y con su rótulo para que se sepa qué es ese texto.
                        if (node.notes.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DESCRIPCIÓN',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 8,
                                    letterSpacing: .5,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
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
                              ],
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
                        // SO con el que trabaja ESE servidor (el nodo lo dice en
                        // su /api/health). Sin dato se enseña «—», no se inventa.
                        const SizedBox(height: 5),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(
                            children: [
                              Text(
                                'SO',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 8.5,
                                  letterSpacing: .5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  node.os.isEmpty ? '—' : node.os,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                  padding: EdgeInsets.zero,
                  // Compacto de verdad: el botón de 48 px hacía más alta la
                  // cabecera y el contenido del HUB desbordaba la card.
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  onPressed: onConfigure,
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // El estado va en su píldora y el resto en UNA línea: con cuatro
          // chips la fila se partía en dos y la card quedaba con un hueco
          // vacío debajo (era el problema de diseño del HUB).
          Row(
            children: [
              _ChipBit(
                icon: hub.online
                    ? Icons.check_circle_outline_rounded
                    : Icons.cloud_off_outlined,
                label: hub.online ? 'en línea' : 'sin respuesta',
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (hub.version.isNotEmpty) 'v${hub.version}',
                    hub.latencyLabel,
                    '${hub.onlineCount}/${hub.totalCount} '
                        'servidor${hub.totalCount == 1 ? '' : 'es'}',
                    if (hub.blocked > 0) '${hub.blocked} en mantenimiento',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color:
                        hub.totalCount > 0 && hub.onlineCount < hub.totalCount
                        ? _warnAmber
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (hub.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            // El aviso completo, al pasar el ratón: en la card va en dos líneas
            // para no romper el alto del diagrama.
            Tooltip(
              message: hub.note,
              child: Text(
                hub.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ] else ...[
            // Sin aviso, la card dice qué hace el HUB (y no queda un hueco).
            const SizedBox(height: 6),
            Text(
              'Reparte las carpetas y las subidas entre los servidores.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
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
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
  });

  final NodeView node;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
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
                // El mismo rack que en el diagrama: en el celular también se
                // reconoce como un servidor.
                _ServerBadge(color: node.color),
                const SizedBox(width: 9),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESCRIPCIÓN',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8.5,
                      letterSpacing: .5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
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
                ],
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
                _DataBit(label: 'SO', value: node.os.isEmpty ? '—' : node.os),
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
    required this.onLogs,
    required this.onRestart,
    required this.onUpload,
    required this.onDependencies,
  });

  final NodeView node;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
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
            // Apagar NO apaga la máquina: el servidor queda apagado para el
            // Drive (`enabled = 0`), sigue en la lista para volver a
            // encenderlo y quien dependa de él queda en mantenimiento con su
            // aviso. Para quitarlo de la lista está *Eliminar* (borrado
            // lógico, `active = 0`).
            label: node.enabled ? 'Apagar en el Drive' : 'Encender en el Drive',
          ),
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

/// El «rack» de un servidor: el icono de una máquina con su foco de estado.
///
/// Antes la card llevaba un punto de color suelto delante del nombre y se
/// leía como una fila cualquiera. Con el rack se ve de qué se está hablando
/// (un servidor de archivos) sin leer nada, y el foco dice si está encendido,
/// apagado o sin comprobar con el mismo color de siempre.
class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.color});

  final Color color;

  /// Lado del rack (el foco de estado sobresale un poco por la esquina).
  static const double size = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: .40)),
            ),
            // La máquina dibujada: las ranuras de un servidor de rack.
            child: Center(
              child: Icon(Icons.dns_rounded, size: size * .56, color: color),
            ),
          ),
          Positioned(
            right: -1.5,
            bottom: -1.5,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
      // El enfocado se marca MÁS, pero los demás siguen a la vista: antes sus
      // líneas se desvanecían y parecía que el servidor había desaparecido.
      final focused = selectedId == null || selectedId == node.id;
      final color = node.color.withValues(alpha: focused ? .9 : .55);
      final paint = Paint()
        ..color = color
        ..strokeWidth = focused ? 2.1 : 1.3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // En la ESTRELLA hay cards arriba y abajo del HUB: el cable sale del
      // borde que MIRA a la card. Antes siempre salía por `hub.bottom`, así que
      // las de arriba tenían la línea cruzando el HUB por encima.
      final below = rect.center.dy >= hub.center.dy;
      final start = Offset(hub.center.dx, below ? hub.bottom : hub.top);
      final end = Offset(rect.center.dx, below ? rect.top : rect.bottom);
      final dy = end.dy - start.dy;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx,
          start.dy + dy * .55,
          end.dx,
          end.dy - dy * .55,
          end.dx,
          end.dy,
        );
      if (node.alive) {
        canvas.drawPath(path, paint);
      } else {
        _dashed(canvas, path, paint);
      }
      final dir = Offset(0, below ? 1 : -1);
      _arrow(canvas, end - dir * 2, dir, color);
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
        alpha: focused ? .95 : .55,
      );
      final paint = Paint()
        ..color = color
        ..strokeWidth = focused ? 2 : 1.2
        ..style = PaintingStyle.stroke;

      // ANCLAJE: por el lado de cada card que MIRA a la otra. Si una está
      // encima de la otra, por arriba/abajo; si están al lado, por los
      // costados. Antes SIEMPRE salía por los costados, así que dos cards en la
      // misma columna se unían con una S que cruzaba el HUB y se veía mal.
      final dx = to.center.dx - from.center.dx;
      final dy = to.center.dy - from.center.dy;
      final vertical = dy.abs() > dx.abs() * .8;

      final directStart = vertical
          ? (dy >= 0 ? from.bottomCenter : from.topCenter)
          : (dx >= 0 ? from.centerRight : from.centerLeft);
      final directEnd = vertical
          ? (dy >= 0 ? to.topCenter : to.bottomCenter)
          : (dx >= 0 ? to.centerLeft : to.centerRight);
      // Si el tramo directo atraviesa el HUB, la relación sale POR FUERA de él
      // (por el costado más cercano) en vez de esconderse detrás de la card.
      final detour = _segmentCrossesHub(directStart, directEnd);
      final viaLeft = (from.center.dx + to.center.dx) / 2 <= hub.center.dx;

      final Offset start;
      final Offset end;
      final Offset dir;
      if (detour) {
        start = Offset(viaLeft ? from.left : from.right, from.center.dy);
        end = Offset(viaLeft ? to.left : to.right, to.center.dy);
        dir = Offset(viaLeft ? 1 : -1, 0);
      } else if (vertical) {
        final down = dy >= 0;
        start = directStart;
        end = directEnd;
        dir = Offset(0, down ? 1 : -1);
      } else {
        final right = dx >= 0;
        start = directStart;
        end = directEnd;
        dir = Offset(right ? 1 : -1, 0);
      }

      final Path path;
      if (detour) {
        final sideX = viaLeft
            ? math.max(6.0, hub.left - 26)
            : math.min(size.width - 6, hub.right + 26);
        final mid = Offset(sideX, (start.dy + end.dy) / 2);
        path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + (mid.dx - start.dx) * .55,
            start.dy,
            mid.dx,
            mid.dy - (mid.dy - start.dy) * .55,
            mid.dx,
            mid.dy,
          )
          ..cubicTo(
            mid.dx,
            mid.dy + (end.dy - mid.dy) * .55,
            end.dx + (mid.dx - end.dx) * .55,
            end.dy,
            end.dx,
            end.dy,
          );
      } else {
        final mid = (start + end) / 2;
        final bow = (vertical ? dx : dy) * .35;
        final c1 = vertical
            ? Offset(start.dx + bow, mid.dy)
            : Offset(mid.dx, start.dy + bow);
        final c2 = vertical
            ? Offset(end.dx + bow, mid.dy)
            : Offset(mid.dx, end.dy + bow);
        path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      }
      if (broken) {
        _dashed(canvas, path, paint, dash: 5, gap: 4);
      } else {
        canvas.drawPath(path, paint);
      }
      // La punta entra PERPENDICULAR a la card (la dirección del anclaje), no
      // tangente a la curva: si no, en vertical apuntaba de lado.
      _arrow(canvas, end, dir, color);
      if (mutual) {
        _arrow(canvas, start, -dir, color);
      }
    }
  }

  /// ¿El tramo recto entre [a] y [b] pasa por encima de la tarjeta del HUB?
  ///
  /// Se recorta el segmento contra el rectángulo del HUB (Liang-Barsky). Si lo
  /// toca, la dependencia se dibuja rodeándolo: antes la línea se metía debajo
  /// de la card del hub, desaparecía, y parecía que la relación estaba rota.
  bool _segmentCrossesHub(Offset a, Offset b) {
    final r = hub.inflate(8);
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    var t0 = 0.0;
    var t1 = 1.0;
    bool edge(double p, double q) {
      if (p == 0) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
      return true;
    }

    return edge(-dx, a.dx - r.left) &&
        edge(dx, r.right - a.dx) &&
        edge(-dy, a.dy - r.top) &&
        edge(dy, r.bottom - a.dy);
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
