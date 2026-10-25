import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_settings.dart';
import '../hs_format.dart';
import '../widgets/connection_topology.dart';
import '../drive_api_service.dart';
import '../drive_host.dart';
import '../hs_api.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';

/// Página "Conexión": estado del enlace con el servidor del drive.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.driveApi});

  final DriveApiService driveApi;

  // Sondeo de salud con package:http: funciona en web y nativo.
  // (dart:io HttpClient lanza UnsupportedError en Chrome.)
  //
  // Es ESTÁTICO para que las pruebas puedan responder por él: el sondeo va al
  // servidor real y no hay otra forma de ejercitar la tarjeta de servidores.
  static Future<({int statusCode, String body})> Function(
    String url,
    Duration timeout,
  )
  healthGet = _healthGet;

  static Future<({int statusCode, String body})> _healthGet(
    String url,
    Duration timeout,
  ) async {
    final r = await http.get(Uri.parse(url)).timeout(timeout);
    return (statusCode: r.statusCode, body: r.body);
  }

  /// Detalle de cada servidor que solo da el HUB con sesión (`/api/nodes`):
  /// espacio libre/total, prioridad, notas… `/api/health` es público y no los
  /// lleva (no expone rutas del disco). Inyectable como [healthGet].
  static Future<({int statusCode, String body})> Function(
    String url,
    Duration timeout,
  )
  hubNodesGet = _hubNodesGet;

  static Future<({int statusCode, String body})> _hubNodesGet(
    String url,
    Duration timeout,
  ) async {
    final token = HsSession.token ?? '';
    final r = await http
        .get(Uri.parse(url), headers: {if (token.isNotEmpty) 'apikey': token})
        .timeout(timeout);
    return (statusCode: r.statusCode, body: r.body);
  }

  /// Cliente de las acciones de administración (log, reinicio, subir
  /// archivos). Es inyectable como el resto: las pruebas lo reemplazan por un
  /// `MockClient` y nunca tocan un servidor de verdad.
  static http.Client adminClient = http.Client();

  /// Selector de archivos del proyecto. Inyectable: en las pruebas se
  /// reemplaza para no abrir el diálogo del sistema.
  static Future<List<XFile>> Function() pickProjectFiles = _pickProjectFiles;

  static Future<List<XFile>> _pickProjectFiles() async {
    const group = XTypeGroup(label: 'Archivos del proyecto');
    return openFiles(acceptedTypeGroups: [group]);
  }

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  Timer? _timer;

  /// Último resultado de guardar la dirección del HUB (lo enseña la card del
  /// panel lateral). La dirección se edita en el modal «Configurar hub».
  String? _hostSaved;

  /// Servidor con una acción en curso (la fila muestra un girador).
  int? _adminBusyId;

  /// Servidores MARCADOS para una acción en lote (subir el proyecto a varios).
  final Set<int> _picked = {};

  /// true = tocar una card la marca; false = solo ilumina sus conexiones.
  bool _selectMode = false;

  Map<String, dynamic>? parseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _checking = false;
  int? _latencyMs;
  DateTime? _lastCheck;
  Map<String, dynamic>? _health;
  String? _lastError;

  /// Dirección donde se encontró el HUB (null = todavía no se ha dado con él).
  String? _hubBase;

  // Servidores del Drive federado: la lista vive en el backend y el hub la
  // reparte. Con un solo servidor el Drive funciona como siempre.
  List<Map<String, dynamic>> _nodes = const [];
  bool _nodesLoading = false;
  String? _nodesError;

  /// Detalle por servidor que da el hub con sesión (`/api/nodes`): espacio
  /// libre y total, prioridad, notas. Por id y, de respaldo, por nombre (el
  /// hub puede estar usando otra lista y entonces los ids no son los mismos).
  Map<int, Map<String, dynamic>> _nodeInfo = const {};
  Map<String, Map<String, dynamic>> _nodeInfoByName = const {};

  @override
  void initState() {
    super.initState();
    _check();
    _loadNodes();
    // Sondeo cada 15 s mientras la página está visible.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  /// Lee los servidores registrados. Sin permiso de Conexión el backend
  /// contesta 403 y la tarjeta lo dice: no se rompe el resto de la página.
  Future<void> _loadNodes() async {
    if (_nodesLoading) return;
    setState(() {
      _nodesLoading = true;
      _nodesError = null;
    });
    try {
      final nodes = await HsApi.driveNodes();
      if (!mounted) return;
      setState(() => _nodes = nodes);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _nodesError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _nodesError = '$e');
    } finally {
      if (mounted) setState(() => _nodesLoading = false);
    }
  }

  /// Alta o edición de un servidor.
  Future<void> _editNode([Map<String, dynamic>? node]) async {
    final saved = await showHsModal<bool>(
      context: context,
      builder: (_) => _DriveNodeDialog(node: node, siblings: _nodes),
    );
    if (saved == true) await _loadNodes();
  }

  /// Enciende o apaga un servidor (apagado = el hub no guarda nada nuevo ahí).
  Future<void> _toggleNode(Map<String, dynamic> node) async {
    final on = node['enabled'] == true || node['enabled'] == 1;
    try {
      await HsApi.updateDriveNode(
        id: (node['id'] as num).toInt(),
        enabled: !on,
      );
      await _loadNodes();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    }
  }

  Future<void> _deleteNode(Map<String, dynamic> node) async {
    final name = (node['name'] ?? 'servidor').toString();
    final sure = await confirmDelete(
      context,
      title: 'Quitar "$name"',
      message:
          'Sus carpetas dejarán de verse en el Drive. Los archivos NO se '
          'borran del servidor.',
      confirmLabel: 'Quitar',
    );
    if (!sure) return;
    try {
      await HsApi.deleteDriveNode((node['id'] as num).toInt());
      await _loadNodes();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    }
  }

  // ==================== Administración del servidor ====================
  //
  // Ver la terminal, reiniciar el servicio y subir archivos al proyecto van al
  // HUB: él comprueba con el backend que quien los pide es el
  // SUPERADMINISTRADOR y luego los reenvía al servidor con su secreto. El panel
  // nunca guarda ni ve ese secreto, y el módulo entero solo lo ve el superadmin
  // (ver [main.dart]).

  /// Base del hub (o, si no se encontró, del servidor configurado).
  String get _adminBase =>
      (_hubBase ?? widget.driveApi.base).replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _adminHeaders {
    final token = HsSession.token ?? '';
    return {if (token.isNotEmpty) 'apikey': token};
  }

  /// Mensaje legible de una respuesta de administración.
  String _apiMessage(int status, Map<String, dynamic>? data) {
    final parts = [
      data?['error'],
      data?['details'],
      data?['hint'],
    ].map((v) => (v ?? '').toString().trim()).where((v) => v.isNotEmpty);
    return parts.isEmpty ? 'HTTP $status' : parts.join(' · ');
  }

  /// Servidores ya MEZCLADOS (base + estado del hub + espacio) para la tabla.
  List<NodeView> _nodeViews() {
    final names = <int, String>{
      for (final n in _nodes)
        if (n['id'] is num)
          (n['id'] as num).toInt(): (n['name'] ?? '').toString(),
    };

    bool? sharpOf(Object? raw) {
      if (raw is! Map) return null;
      final libs = raw['libs'];
      if (libs is Map && libs['sharp'] != null) return libs['sharp'] == true;
      final image = raw['image'];
      return image is Map ? image['sharp'] == true : null;
    }

    bool? ffmpegOf(Object? raw) {
      if (raw is! Map) return null;
      final libs = raw['libs'];
      if (libs is Map && libs['ffmpeg'] != null) return libs['ffmpeg'] == true;
      final video = raw['video'];
      return video is Map ? video['posters'] == true : null;
    }

    double? bytesOf(Object? raw, String key) {
      if (raw is! Map) return null;
      final value = raw[key];
      return value is num && value.isFinite && value >= 0
          ? value.toDouble()
          : null;
    }

    final out = <NodeView>[];
    for (final node in _nodes) {
      final id = (node['id'] as num?)?.toInt() ?? 0;
      final key = (node['name'] ?? '').toString().trim().toLowerCase();
      final state = _nodeStates[id] ?? _nodeStatesByName[key];
      final extra = _nodeInfo[id] ?? _nodeInfoByName[key];
      final deps =
          (node['dependsOn'] as List?) ??
          (extra?['dependsOn'] as List?) ??
          (state?['dependsOn'] as List?) ??
          const [];
      final blocked = state?['blocked'] == true || extra?['blocked'] == true;
      final online = state == null ? null : state['online'] == true;
      final latency = (state?['latencyMs'] ?? extra?['latencyMs']);
      out.add(
        NodeView(
          id: id,
          name: (node['name'] ?? 'Servidor').toString(),
          url: (extra?['url'] ?? node['url'] ?? '').toString(),
          enabled: node['enabled'] == true || node['enabled'] == 1,
          priority: (extra?['priority'] ?? node['priority']) is num
              ? ((extra?['priority'] ?? node['priority']) as num).toInt()
              : null,
          notes: (extra?['notes'] ?? node['notes'] ?? '').toString().trim(),
          version: (state?['version'] ?? extra?['version'] ?? '').toString(),
          latencyMs: latency is num ? latency.toInt() : null,
          free: bytesOf(extra, 'freeBytes'),
          total: bytesOf(extra, 'totalBytes'),
          sharp: sharpOf(state ?? extra),
          ffmpeg: ffmpegOf(state ?? extra),
          // RAM del servidor: la informa cada nodo en su /api/health y el hub
          // la reenvía. Sin dato se enseña «—», nunca un 0 inventado.
          memUsed: bytesOf(extra?['mem'] ?? state?['mem'], 'usedBytes'),
          memTotal: bytesOf(extra?['mem'] ?? state?['mem'], 'totalBytes'),
          online: online,
          error: (state?['error'] ?? extra?['error'])?.toString(),
          blocked: blocked,
          blockedReason: (state?['blockedReason'] ?? extra?['blockedReason'])
              ?.toString(),
          dependsOnIds: [
            for (final d in deps)
              if (d is num) d.toInt(),
          ],
          dependsOnNames: [
            for (final d in deps)
              if (d is num) names[d.toInt()] ?? '#${d.toInt()}' else '$d',
          ],
        ),
      );
    }
    return out;
  }

  /// El HUB tal como lo pinta el diagrama (dirección, versión, ping, cuántos
  /// servidores responden y si hay alguno en mantenimiento).
  HubView _hubView() {
    final viaHub = _viaHub;
    final total = viaHub
        ? (_health!['nodes'] as List).length
        : _nodes.where((n) => n['enabled'] == true || n['enabled'] == 1).length;
    final online = viaHub ? _nodesOnline() : 0;
    // Sin hub al que preguntar, o con el Drive apuntando a un servidor suelto,
    // el diagrama tiene que decirlo: si no, parece que todos están caídos.
    final note = _health == null
        ? 'El panel no está conectado con el HUB: el estado de cada servidor '
              'no se puede comprobar desde aquí.'
        : !viaHub
        ? 'Contesta un servidor suelto, no el HUB: no se puede saber si los '
              'demás responden. Apunta la dirección al HUB (puerto '
              '${DriveHost.hubPort}).'
        : !_driveOnHub
        ? 'El estado se mira en el HUB ($_hubBase), pero el Drive apunta a '
              '${widget.driveApi.base}: así solo se ven las carpetas de ese '
              'servidor.'
        : '';
    return HubView(
      url: (_hubBase ?? widget.driveApi.base).replaceAll(RegExp(r'/+$'), ''),
      online: _health != null,
      version: '${_health?['version'] ?? ''}'.replaceAll(RegExp(r'^v'), ''),
      latencyMs: _latencyMs,
      onlineCount: online,
      totalCount: total,
      blocked: _maintenanceItems.length,
      note: note,
    );
  }

  /// Servidores BLOQUEADOS por dependencia según el hub (vacío = todo bien).
  List<Map<String, dynamic>> get _maintenanceItems {
    final maintenance = _health?['maintenance'];
    final items = maintenance is Map ? maintenance['items'] : null;
    return (items as List?)
            ?.whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry('$k', v)))
            .toList() ??
        const [];
  }

  /// La fila de la BASE (para editar/apagar/quitar desde la tabla).
  Map<String, dynamic>? _nodeById(int id) {
    for (final node in _nodes) {
      if ((node['id'] as num?)?.toInt() == id) return node;
    }
    return null;
  }

  void _editFromView(NodeView view) {
    final raw = _nodeById(view.id);
    if (raw != null) _editNode(raw);
  }

  void _toggleFromView(NodeView view) {
    final raw = _nodeById(view.id);
    if (raw != null) _toggleNode(raw);
  }

  void _deleteFromView(NodeView view) {
    final raw = _nodeById(view.id);
    if (raw != null) _deleteNode(raw);
  }

  /// Abre la terminal (log del servicio) de un servidor.
  Future<void> _openTerminal(NodeView node) async {
    await showHsModal<void>(
      context: context,
      builder: (_) => NodeTerminalSheet(
        serverName: node.name,
        load: () => _fetchLogs(node),
        onRestart: () => _restartNode(node, confirm: false),
      ),
    );
  }

  Future<String> _fetchLogs(NodeView node) async {
    final r = await ConnectionPage.adminClient
        .get(
          Uri.parse('$_adminBase/api/admin/node/${node.id}/logs?lines=400'),
          headers: _adminHeaders,
        )
        .timeout(const Duration(seconds: 25));
    final data = parseJson(r.body);
    if (r.statusCode != 200) throw _apiMessage(r.statusCode, data);
    return (data?['text'] ?? '').toString();
  }

  /// Reinicia el servicio del servidor (`systemctl restart hardstreet-drive`).
  Future<String> _restartNode(NodeView node, {bool confirm = true}) async {
    if (confirm) {
      final sure = await _confirmRestart(node);
      if (!sure) return '';
    }
    setState(() => _adminBusyId = node.id);
    try {
      final r = await ConnectionPage.adminClient
          .post(
            Uri.parse('$_adminBase/api/admin/node/${node.id}/restart'),
            headers: _adminHeaders,
          )
          .timeout(const Duration(seconds: 30));
      final data = parseJson(r.body);
      if (r.statusCode != 200) {
        final message = _apiMessage(r.statusCode, data);
        // Desde la terminal el texto del error se enseña en su propia ventana.
        if (!confirm) throw message;
        HsToast.error('No se pudo reiniciar ${node.name}', details: message);
        return message;
      }
      final message = (data?['message'] ?? 'Reiniciando ${node.name}…')
          .toString();
      if (mounted) HsToast.success(message);
      // La salud del hub se refresca en unos segundos: se vuelve a mirar.
      unawaited(Future<void>.delayed(const Duration(seconds: 6), _check));
      return message;
    } catch (e) {
      final message = '$e';
      if (mounted) {
        HsToast.error('No se pudo reiniciar ${node.name}', details: message);
      }
      return message;
    } finally {
      if (mounted) setState(() => _adminBusyId = null);
    }
  }

  Future<bool> _confirmRestart(NodeView node) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reiniciar ${node.name}'),
        content: const Text(
          'Se reinicia el servicio del Drive en ese servidor '
          '(`sudo systemctl restart hardstreet-drive`). Las subidas en curso se '
          'cortan y el Drive deja de responder unos segundos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    return res == true;
  }

  /// Elige los archivos del proyecto (una sola vez, para uno o varios nodos).
  Future<List<XFile>> _pickProjectFiles() => ConnectionPage.pickProjectFiles();

  /// Manda [files] a UN servidor. Devuelve cuántos se guardaron y el error (si
  /// hubo) para que quien llama pueda resumir uno o varios servidores.
  Future<({int saved, String? error})> _uploadFilesTo(
    NodeView node,
    List<XFile> files,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_adminBase/api/admin/node/${node.id}/files'),
      )..headers.addAll(_adminHeaders);
      for (final file in files) {
        final bytes = await file.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes('files', bytes, filename: file.name),
        );
      }
      final streamed = await ConnectionPage.adminClient
          .send(request)
          .timeout(const Duration(minutes: 5));
      final body = await streamed.stream.bytesToString();
      final data = parseJson(body);
      if (streamed.statusCode != 200) {
        return (
          saved: 0,
          error: data == null ? body : _apiMessage(streamed.statusCode, data),
        );
      }
      final names =
          (data?['names'] as List?)?.whereType<String>().toList() ?? const [];
      return (saved: names.length, error: null);
    } catch (e) {
      return (saved: 0, error: '$e');
    }
  }

  /// Sube archivos a la carpeta del proyecto del servidor.
  ///
  /// Es para ACTUALIZAR el código a mano (server.js, lib/, public/…), así que
  /// no reinicia nada: si cambiaste código, reinicia tú después.
  Future<void> _uploadProject(NodeView node) async {
    final files = await _pickProjectFiles();
    if (files.isEmpty) return;
    setState(() => _adminBusyId = node.id);
    final res = await _uploadFilesTo(node, files);
    if (!mounted) return;
    setState(() => _adminBusyId = null);
    if (res.error != null) {
      HsToast.error('No se pudo subir a ${node.name}', details: res.error);
      return;
    }
    HsToast.success(
      '${res.saved} archivo${res.saved == 1 ? '' : 's'} en ${node.name}',
    );
  }

  /// Sube EL MISMO archivo de proyecto a TODOS los servidores marcados.
  ///
  /// Se eligen los archivos una sola vez y se manda a cada nodo por separado
  /// (el hub no tiene un endpoint "a todos"): así un servidor caído no impide
  /// que los demás queden actualizados, y el aviso dice cuáles fallaron.
  Future<void> _uploadToPicked() async {
    final targets = [
      for (final node in _nodeViews())
        if (_picked.contains(node.id)) node,
    ];
    if (targets.isEmpty) {
      HsToast.error('Marca al menos un servidor');
      return;
    }
    final files = await _pickProjectFiles();
    if (files.isEmpty) return;
    final failed = <String>[];
    var ok = 0;
    for (final node in targets) {
      setState(() => _adminBusyId = node.id);
      final res = await _uploadFilesTo(node, files);
      if (res.error != null) {
        failed.add('${node.name}: ${res.error}');
      } else {
        ok++;
      }
    }
    if (!mounted) return;
    setState(() {
      _adminBusyId = null;
      if (failed.isEmpty) {
        _picked.clear();
        _selectMode = false;
      }
    });
    if (failed.isEmpty) {
      HsToast.success(
        '${files.length} archivo${files.length == 1 ? '' : 's'} en '
        '$ok servidor${ok == 1 ? '' : 'es'}: '
        '${targets.map((t) => t.name).join(', ')}',
      );
    } else {
      HsToast.error(
        'Se subió a $ok de ${targets.length} servidores',
        details: failed.join(' · '),
      );
    }
  }

  /// Abre el modal de DEPENDENCIAS de un servidor (antes vivía dentro de
  /// «Editar», donde no se podían marcar bien).
  Future<void> _openDependencies(NodeView node) async {
    final raw = _nodeById(node.id);
    if (raw == null) return;
    final saved = await showHsModal<bool>(
      context: context,
      builder: (_) => _DependenciesDialog(node: raw, siblings: _nodes),
    );
    if (saved == true) await _loadNodes();
  }

  /// Opciones del HUB (dirección del Drive): se configuran EN el hub, no en
  /// una sección suelta de la pantalla.
  Future<void> _openHubConfig() async {
    await showHsModal<void>(
      context: context,
      builder: (_) => _HubConfigDialog(
        current: DriveHost.custom ?? '',
        compiled: DriveHost.compiled,
        publicHttp: DriveHost.publicHttp,
        lanFallback: DriveHost.lanFallback,
        onSave: _saveHubHost,
      ),
    );
  }

  /// Guarda la dirección del Drive (desde el modal del HUB).
  Future<String?> _saveHubHost(String text) async {
    final value = text.trim();
    if (!DriveHost.isValid(value)) {
      return 'Escribe una dirección como https://oriongo.ddns.net';
    }
    final ok = await AppSettings.instance.setDriveHost(value);
    if (!mounted) return ok ? null : 'Esa dirección no se pudo guardar.';
    setState(() {
      _hostSaved = ok
          ? (DriveHost.isCustom
                ? 'Guardado: ${DriveHost.base}'
                : 'Guardado: se usa la dirección de fábrica (${DriveHost.compiled}).')
          : null;
    });
    if (ok) {
      unawaited(widget.driveApi.refresh());
      unawaited(_check());
    }
    return ok ? null : 'Esa dirección no se pudo guardar.';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Busca el HUB, no solo la dirección configurada.
  ///
  /// Antes solo se preguntaba a `DriveHost.base`: si ahí contesta un servidor
  /// de archivos (p. ej. el 4000) o el HTTPS del nombre público falla, el panel
  /// no recibía la lista de nodos y TODOS salían «Habilitado», sin decir cuál
  /// estaba prendido. Ahora se prueba también el puerto del HUB en la misma
  /// máquina y los respaldos conocidos, y se usa el primero que conteste con
  /// la lista de servidores.
  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    String? err;
    Map<String, dynamic>? health; // lo que contestó (hub o servidor suelto)
    String? hubBase; // dirección que SÍ es el hub
    int? latency;
    for (final candidate in _probeCandidates()) {
      final sw = Stopwatch()..start();
      try {
        // 4 s por dirección: se prueban varias, y con 5 s cada una un móvil
        // sin red se pasaría media vida «Verificando…».
        final r = await ConnectionPage.healthGet(
          '$candidate/api/health',
          const Duration(seconds: 4),
        );
        if (r.statusCode != 200) {
          err = 'HTTP ${r.statusCode} en $candidate';
          continue;
        }
        final data = parseJson(r.body);
        if (data == null) {
          err = 'Respuesta no válida de $candidate';
          continue;
        }
        sw.stop();
        health ??= data;
        latency ??= sw.elapsedMilliseconds;
        if (data['nodes'] is List) {
          health = data;
          hubBase = candidate;
          latency = sw.elapsedMilliseconds;
          break;
        }
      } catch (e) {
        err = '$candidate: $e';
      }
    }
    if (!mounted) return;
    setState(() {
      _latencyMs = latency;
      _lastCheck = DateTime.now();
      _health = health;
      _hubBase = hubBase;
      // Un servidor que no es el hub NO es un error: la tarjeta lo explica.
      _lastError = health == null ? err : null;
      if (hubBase == null) {
        // Sin hub no hay datos de disco: no se enseñan los viejos.
        _nodeInfo = const {};
        _nodeInfoByName = const {};
      }
    });
    if (hubBase != null) unawaited(_loadNodeInfo(hubBase));
    _checking = false;
  }

  /// Pide al hub el detalle de cada servidor (espacio libre, prioridad…).
  ///
  /// Es silencioso: sin sesión (401) o sin red, cada tarjeta se queda con lo
  /// que sí da `/api/health` y esto no rompe la página.
  Future<void> _loadNodeInfo(String hubBase) async {
    try {
      final r = await ConnectionPage.hubNodesGet(
        '$hubBase/api/nodes',
        const Duration(seconds: 6),
      );
      if (r.statusCode != 200) return;
      final data = parseJson(r.body);
      final list = (data?['nodes'] as List?)?.whereType<Map>() ?? const <Map>[];
      final byId = <int, Map<String, dynamic>>{};
      final byName = <String, Map<String, dynamic>>{};
      for (final raw in list) {
        final row = raw.map((k, v) => MapEntry(k.toString(), v));
        final id = row['id'];
        if (id is num) byId[id.toInt()] = row;
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) byName[name] = row;
      }
      if (!mounted) return;
      setState(() {
        _nodeInfo = byId;
        _nodeInfoByName = byName;
      });
    } catch (_) {
      // Sin detalle: las tarjetas siguen con lo que dijo /api/health.
    }
  }

  /// El HUB en la misma máquina que [url] (solo cambia el puerto).
  String? _hubOf(String? url) {
    final uri = Uri.tryParse((url ?? '').trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.port == DriveHost.hubPort) return null;
    return Uri(
      scheme: uri.scheme == 'https' ? 'http' : uri.scheme,
      host: uri.host,
      port: DriveHost.hubPort,
    ).toString();
  }

  /// Direcciones donde buscar el HUB, en orden (sin repetir).
  List<String> _probeCandidates() {
    final out = <String>[];
    void add(String? url) {
      final u = (url ?? '').trim().replaceAll(RegExp(r'/+$'), '');
      if (u.isEmpty || out.contains(u)) return;
      out.add(u);
    }

    // Si ya se encontró una vez, se pregunta primero ahí: una sola petición.
    add(_hubBase);
    add(widget.driveApi.base);
    if (_hubBase == null) {
      // El HUB suele estar en la MISMA máquina que el servidor de archivos.
      add(_hubOf(widget.driveApi.base));
      add(DriveHost.base);
      add(_hubOf(DriveHost.base));
      add(DriveHost.publicHttp);
      add(DriveHost.lanFallback);
    }
    return out;
  }

  /// Estado que el HUB informa de cada servidor, por id.
  ///
  /// Vacío cuando el panel habla con UN servidor suelto (o no responde): ahí
  /// NO hay forma de saber si los demás están encendidos —los servidores de
  /// archivos no se abren a internet, solo el hub los alcanza— y por eso la
  /// lista no puede pintarlos como "Encendido" a la ligera.
  Map<int, Map<String, dynamic>> get _nodeStates {
    final list =
        (_health?['nodes'] as List?)?.whereType<Map>() ?? const <Map>[];
    final out = <int, Map<String, dynamic>>{};
    for (final raw in list) {
      final id = raw['id'];
      if (id is! num) continue;
      out[id.toInt()] = raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return out;
  }

  /// ¿El panel está hablando con el HUB (el que conoce a todos los servidores)?
  bool get _viaHub => _health?['nodes'] is List;

  /// ¿La dirección del DRIVE es la del HUB?
  ///
  /// Si el Drive apunta a un servidor de archivos, el estado se puede mirar
  /// en el hub (buscándolo en el puerto de al lado), pero el Drive sigue
  /// viendo solo las carpetas de ese servidor: hay que decirlo.
  bool get _driveOnHub {
    final base = widget.driveApi.base.trim().replaceAll(RegExp(r'/+$'), '');
    return _hubBase != null && base == _hubBase;
  }

  /// Los mismos estados, por NOMBRE (sin mayúsculas).
  ///
  /// El hub puede estar usando una lista distinta a la de la base (por
  /// ejemplo `DRIVE_NODES` del `.env`): ahí los ids que manda no son los de
  /// `drive_nodes` y sin el nombre no se sabría cuál responde.
  Map<String, Map<String, dynamic>> get _nodeStatesByName {
    final list =
        (_health?['nodes'] as List?)?.whereType<Map>() ?? const <Map>[];
    final out = <String, Map<String, dynamic>>{};
    for (final raw in list) {
      final name = (raw['name'] ?? '').toString().trim().toLowerCase();
      if (name.isEmpty) continue;
      out[name] = raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return out;
  }

  /// Cuántos servidores de los que conoce el hub están respondiendo.
  int _nodesOnline() {
    final list =
        (_health?['nodes'] as List?)?.whereType<Map>() ?? const <Map>[];
    return list.where((n) => n['online'] == true).length;
  }

  /// De dónde saca el hub su lista, en palabras.
  String _sourceLabel(Object? source) {
    switch (source) {
      case 'env':
        return 'la lista del .env (DRIVE_NODES)';
      case 'file':
        return 'el archivo de respaldo (DRIVE_NODES_FILE)';
      case 'none':
        return 'ninguna lista';
      default:
        return 'una lista que no es la base de datos';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = _health != null; // ¿contestó /api/health?
    final online =
        widget.driveApi.conn == DriveConn.online && answered; // Drive usable
    final viaHub = _viaHub;

    // La vista principal es SOLO el diagrama (más los avisos que explican por
    // qué no carga). El estado del HUB —que antes era una tarjeta grande aquí
    // arriba— vive en el panel lateral, junto a los demás detalles.
    final sections = <Widget>[
      // El hub contesta en /api/health pero el árbol no llega: se dice POR
      // QUÉ (hub sin servidores, nodo caído, sin sesión…) en vez de dejar
      // solo "Sin conexión", que parece un problema de la app.
      if (_health != null && widget.driveApi.conn != DriveConn.online) ...[
        const SizedBox(height: 16),
        _SectionCard(
          title: 'El servidor responde, pero el Drive no cargó',
          children: [
            Text(
              widget.driveApi.error ??
                  'El listado del Drive todavía no ha llegado. Toca '
                      '«Probar conexión» en unos segundos.',
              style: TextStyle(fontSize: 13, height: 1.35, color: scheme.error),
            ),
            const SizedBox(height: 8),
            Text(
              'Si esa dirección es la del HUB, el mensaje viene de él o de '
              'los servidores de archivos que tiene apuntados (mira cuáles '
              'responden en «Detalles de la conexión»).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
      // El hub puede estar tirando de `DRIVE_NODES` (o del archivo de
      // respaldo) en vez de la tabla `drive_nodes`: entonces los servidores
      // que editas en esta pantalla NO le llegan y esta lista no cuadra con
      // la suya. Se dice aquí, con el motivo, en vez de dejar solo puestos
      // «Habilitado» sin explicación.
      if (viaHub && (_health!['nodesSource'] ?? 'backend') != 'backend') ...[
        const SizedBox(height: 16),
        _SectionCard(
          title: 'El hub no está leyendo la lista de la base de datos',
          children: [
            _Bullet(
              'El hub está usando ${_sourceLabel(_health!['nodesSource'])}. '
              'Los servidores que agregues o edites aquí no le llegan, y su '
              'estado no se puede comprobar.',
            ),
            if ((_health!['nodesError'] ?? '').toString().trim().isNotEmpty)
              _Bullet('Motivo: ${_health!['nodesError']}'),
            _Bullet(
              'En el .env del hub tienen que estar DRIVE_CONFIG_URL y '
              'DRIVE_HUB_TOKEN (el MISMO valor que el backend). Después se '
              'reinicia:',
            ),
            _Mono('sudo systemctl restart hardstreet-drive-hub'),
            _Bullet('Y se toca «Probar conexión» aquí arriba.'),
          ],
        ),
      ],
      // ===== Servidores del Drive (Drive federado) =====
      _SectionCard(
        title: 'Servidores del Drive',
        children: [
          Text(
            'El Drive puede repartirse entre varios servidores y el panel lo '
            've como un solo árbol: cada carpeta vive en UN servidor y las '
            'carpetas nuevas se crean en el que tenga más espacio libre. Si '
            'solo hay uno, todo funciona como siempre.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Solo el Superadministrador puede administrar esta sección: '
            'agregar servidores, ver su terminal, reiniciarlos o subirles '
            'archivos.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          // ===== MANTENIMIENTO por dependencia =====
          // Con una dependencia rota el hub deja de usar el servidor
          // dependiente. Aquí se dice CUÁL y POR QUÉ, y el Drive enseña el
          // mismo aviso cuando no le queda ningún servidor usable.
          if (_maintenanceItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('drive-maintenance'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: .45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.engineering_outlined,
                        size: 18,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Drive en mantenimiento',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final item in _maintenanceItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· ${item['name'] ?? 'Servidor'}: '
                        '${item['reason'] ?? 'depende de un servidor que no responde'}',
                        style: const TextStyle(fontSize: 12.5, height: 1.3),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'Vuelve a responder el servidor del que dependen y salen '
                    'solos del mantenimiento.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // La lista es la de la BASE (qué servidores existen y cuáles están
          // habilitados); quién responde de verdad solo lo sabe el hub.
          // Decirlo evita el malentendido de ver "Encendido" en un servidor
          // apagado: con el hub se enseña su estado REAL.
          if (_nodes.isNotEmpty && (!viaHub || !_driveOnHub)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: .45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.wifi_tethering_off_outlined,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _health == null
                          ? 'No se pudo comprobar si estos servidores '
                                'responden: el panel no está conectado a '
                                'ninguno.'
                          : viaHub && !_driveOnHub
                          ? 'El estado de cada servidor se está mirando en '
                                'el HUB ($_hubBase), pero el Drive apunta a '
                                '${widget.driveApi.base}: así solo se ven las '
                                'carpetas de ese servidor y no las de los '
                                'demás. Escribe arriba la dirección del HUB '
                                '(puerto ${DriveHost.hubPort}).'
                          : 'Ahora mismo el panel habla con UN servidor '
                                '(«${_health!['service'] ?? 'servidor'}»), '
                                'no con el HUB: el Drive usa solo ese y no '
                                'se puede saber si los demás responden. '
                                'Para repartir las carpetas entre todos, '
                                'apunta la dirección al HUB (puerto '
                                '${DriveHost.hubPort}).',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Los botones van ANTES del diagrama: así se agrega un servidor sin
          // bajar por todo el árbol.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('drive-node-add'),
                onPressed: _nodesLoading ? null : () => _editNode(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar servidor'),
              ),
              // SELECCIÓN: marcar servidores para subirles el MISMO proyecto
              // de una sola vez (el archivo se elige una vez).
              FilterChip(
                key: const ValueKey('drive-node-select'),
                selected: _selectMode,
                onSelected: _nodes.isEmpty
                    ? null
                    : (on) => setState(() {
                        _selectMode = on;
                        if (!on) _picked.clear();
                      }),
                avatar: const Icon(Icons.checklist_rounded, size: 16),
                label: const Text('Seleccionar'),
              ),
              IconButton(
                key: const ValueKey('drive-node-refresh'),
                onPressed: _nodesLoading ? null : _loadNodes,
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          if (_picked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('drive-node-bulk'),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withValues(alpha: .3)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_picked.length} servidor${_picked.length == 1 ? '' : 'es'} '
                    'marcado${_picked.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('drive-node-bulk-upload'),
                    onPressed: _adminBusyId == null ? _uploadToPicked : null,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Subir proyecto a los marcados'),
                  ),
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('Quitar selección'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (_nodesLoading && _nodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (_nodesError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _nodesError!,
                style: TextStyle(color: scheme.error, fontSize: 12.5),
              ),
            ),
          if (_nodes.isEmpty && !_nodesLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no hay servidores. Agrega el primero con su dirección '
                '(la del hub en ese servidor, puerto ${DriveHost.hubPort}).',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            // El DIAGRAMA: el hub en el centro conectado a cada servidor y
            // las dependencias entre servidores como líneas con flecha.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NodesTopology(
                  nodes: _nodeViews(),
                  hub: _hubView(),
                  busyId: _adminBusyId,
                  onEdit: _editFromView,
                  onToggle: _toggleFromView,
                  onDelete: _deleteFromView,
                  onLogs: _openTerminal,
                  onRestart: (view) => _restartNode(view),
                  onUpload: _uploadProject,
                  onDependencies: _openDependencies,
                  onConfigureHub: _openHubConfig,
                  selectMode: _selectMode,
                  picked: _picked,
                  onPick: (view) => setState(() {
                    if (!_picked.add(view.id)) _picked.remove(view.id);
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  'Clic en un servidor para ver solo sus conexiones · '
                  'arrastra las cards para reacomodarlas · línea punteada = sin '
                  'respuesta · flecha en las dos puntas = dependencia mutua.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 16),

      const SizedBox(height: 16),

      // ===== Falta ffmpeg en el servidor =====
      if (online &&
          _health?['video'] is Map &&
          (_health!['video'] as Map)['posters'] != true)
        _SectionCard(
          title: 'Los vídeos no muestran miniatura',
          children: [
            _Bullet(
              'El servidor no tiene ffmpeg: sin él no puede sacar el primer '
              'fotograma de un vídeo (ni su versión ligera). Las tarjetas de '
              'vídeo se quedan con su icono.',
            ),
            _Bullet(
              'Instálalo en el servidor (la primera opción no necesita root) '
              'y reinicia el servicio:',
            ),
            _Mono('cd hardstreet-drive && npm install'),
            _Mono('sudo apt install -y ffmpeg   (alternativa del sistema)'),
            _Mono('sudo systemctl restart hardstreet-drive'),
            _Bullet('Luego toca «Probar conexión»: debe decir «Sí».'),
          ],
        ),
      if (online &&
          _health?['video'] is Map &&
          (_health!['video'] as Map)['posters'] != true)
        const SizedBox(height: 16),

      // ===== Cómo solucionarlo =====
      if (!online)
        _SectionCard(
          title: 'Si no conecta, revisa',
          children: [
            _Bullet(
              'Que el HUB esté encendido y con su servicio corriendo (la app '
              'habla con el hub, no con cada servidor de archivos):',
            ),
            _Mono('sudo systemctl status hardstreet-drive-hub'),
            _Mono(
              'curl http://127.0.0.1:${DriveHost.hubPort}/api/health   '
              '(en el servidor)',
            ),
            _Bullet(
              'Que el firewall y el router dejen entrar al puerto del hub:',
            ),
            _Mono('sudo ufw allow ${DriveHost.hubPort}/tcp'),
            _Bullet(
              'Los servidores de archivos NO se abren a internet: solo el hub '
              'los alcanza. En «Servidores del Drive» va su dirección interna '
              '(p. ej. http://192.168.1.72:4000).',
            ),
            _Bullet(
              'Que la dirección sea la correcta para la red en la que estás:',
            ),
            _Mono('${DriveHost.compiled}  (la de fábrica: el hub)'),
            _Mono(
              '${DriveHost.publicHttp}  (si el HTTPS falla en el teléfono)',
            ),
            _Mono('${DriveHost.lanFallback}  (dentro de la red de la oficina)'),
            _Bullet(
              'Se cambia en el HUB: botón ⚙ «Configurar hub» de su card.',
            ),
          ],
        ),
    ];

    // ===== Panel lateral: todo el detalle FUERA del diagrama =====
    final side = <Widget>[
      _hubSideCard(),
      const SizedBox(height: 14),
      _detailsCard(),
      if (DriveHost.usingFallback) ...[
        const SizedBox(height: 14),
        _fallbackCard(),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // En computadora los detalles van a un LADO (el diagrama manda); en
        // pantalla angosta se apilan debajo, como el resto del panel.
        final wide = constraints.maxWidth >= 1180;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
            children: [...sections, const SizedBox(height: 16), ...side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
                children: sections,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 20, 0),
              child: SizedBox(
                width: 360,
                child: ListView(
                  key: const ValueKey('connection-side'),
                  padding: const EdgeInsets.only(bottom: 40),
                  children: side,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Estado del HUB en palabras: color, icono y texto.
  ///
  /// Antes era la tarjeta grande que encabezaba el diagrama; ahora es la
  /// primera línea del panel lateral, para que la vista principal sea solo el
  /// diagrama. Dice si el que contesta es el HUB y cuántos servidores de
  /// archivos están prendidos, no un «Conectado» a secas.
  ({Color color, IconData icon, String label}) _hubStatus(ColorScheme scheme) {
    if (_checking) {
      return (color: Colors.amber, icon: Icons.sync, label: 'Verificando…');
    }
    if (_health == null) {
      return (
        color: scheme.error,
        icon: Icons.cloud_off_outlined,
        label: 'Hub sin respuesta',
      );
    }
    if (!_viaHub) {
      return (
        color: const Color(0xFF2F6BFF),
        icon: Icons.dns_outlined,
        label: 'Conectado a un servidor',
      );
    }
    final total = (_health!['nodes'] as List).length;
    return (
      color: total > 0 && _nodesOnline() == total
          ? const Color(0xFF2F9E5B)
          : Colors.amber,
      icon: Icons.hub,
      label: 'Hub conectado',
    );
  }

  /// Card del HUB en el panel lateral: su estado, la dirección del Drive y su
  /// botón de configuración (las opciones del hub viven en el hub, no sueltas
  /// aquí).
  Widget _hubSideCard() {
    final scheme = Theme.of(context).colorScheme;
    final status = _hubStatus(scheme);
    final total = _viaHub ? (_health!['nodes'] as List).length : 0;
    final up = _viaHub ? _nodesOnline() : 0;
    return _SectionCard(
      title: 'HUB',
      children: [
        Row(
          key: const ValueKey('hub-status'),
          children: [
            Icon(status.icon, size: 20, color: status.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: status.color,
                ),
              ),
            ),
          ],
        ),
        if (_health != null && _viaHub) ...[
          const SizedBox(height: 4),
          Text(
            '$up de $total servidor${total == 1 ? '' : 'es'} en línea'
            '${_latencyMs == null ? '' : ' · $_latencyMs ms'}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: up == total ? const Color(0xFF2F9E5B) : scheme.error,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.route_outlined, size: 17, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                DriveHost.base,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          DriveHost.isCustom
              ? 'Dirección propia (guardada en este equipo)'
              : 'Dirección de fábrica',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('hub-configure-side'),
              onPressed: _openHubConfig,
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: const Text('Configurar hub'),
            ),
            TextButton.icon(
              onPressed: _checking ? null : _check,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Probar'),
            ),
          ],
        ),
        if (_hostSaved != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _hostSaved!,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// Detalles técnicos de la conexión (antes ocupaban una sección entera del
  /// ancho completo; ahora son el panel lateral).
  Widget _detailsCard() {
    final scheme = Theme.of(context).colorScheme;
    final viaHub = _viaHub;
    return _SectionCard(
      title: 'Detalles de la conexión',
      children: [
        _Row('Dirección', DriveHost.base),
        _Row(
          'En uso ahora',
          DriveHost.base == widget.driveApi.base
              ? 'La configurada'
              : '${widget.driveApi.base} (se cambia al reabrir la app)',
        ),
        _Row('Latencia', _latencyMs == null ? '—' : '$_latencyMs ms'),
        _Row(
          'Última comprobación',
          _lastCheck == null
              ? '—'
              : '${_lastCheck!.hour.toString().padLeft(2, '0')}:${_lastCheck!.minute.toString().padLeft(2, '0')}:${_lastCheck!.second.toString().padLeft(2, '0')}',
        ),
        _Row('Uptime del servidor', _uptimeLabel()),
        _Row('Servicio', _health?['service'] as String? ?? '—'),
        _Row(
          'Hub',
          _health == null
              ? 'Sin respuesta'
              : viaHub
              ? 'Conectado'
                    '${(_health!['version'] ?? '').toString().isEmpty ? '' : ' · v${_health!['version']}'}'
              : 'No: contesta un servidor suelto',
        ),
        if (_hubBase != null && _hubBase != DriveHost.base)
          _Row('HUB encontrado', _hubBase!),
        if (_health?['nodesSource'] is String)
          _Row(
            'Lista de servidores',
            _health!['nodesSource'] == 'backend'
                ? 'Base de datos (drive_nodes)'
                : _sourceLabel(_health!['nodesSource']),
          ),
        _Row('Carpeta de datos', _health?['root'] as String? ?? '—'),
        if (_health?['nodes'] is List)
          _Row('Servidores conectados', _nodesHealthLabel()),
        if (_health?['nodes'] is List)
          for (final node in (_health!['nodes'] as List).whereType<Map>())
            _Row(
              '  · ${node['name'] ?? 'Servidor'}',
              node['online'] == true
                  ? 'En línea'
                  : 'Sin respuesta'
                        '${(node['error'] ?? '').toString().isEmpty ? '' : ': ${node['error']}'}',
            ),
        // RAM consumida de TODO el Drive (suma de los nodos que responden).
        _Row('RAM del Drive', _driveRamLabel()),
        _Row('Miniaturas de vídeo', _videoSupport('posters')),
        _Row('Calidad ligera de vídeo', _videoSupport('lightQuality')),
        if (_lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Último error: $_lastError',
              style: TextStyle(color: scheme.error, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  /// «5.2 GB / 24 GB» con la RAM de todos los servidores que responden.
  String _driveRamLabel() {
    final mem = _health?['mem'];
    if (mem is! Map) return '—';
    final used = mem['usedBytes'];
    final total = mem['totalBytes'];
    if (used is! num || total is! num || total <= 0) return '—';
    return '${hsBytes(used.toDouble())} / ${hsBytes(total.toDouble())}';
  }

  /// Aviso de la conexión local automática (respaldo por red).
  Widget _fallbackCard() {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Conexión local automática',
      children: [
        Text(
          'El nombre público no respondió desde esta red (certificado del '
          'router o NAT), así que la app está usando la dirección local '
          '${DriveHost.lanFallback}. Funciona mientras estés en la red de la '
          'oficina.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            DriveHost.clearFallback();
            setState(() {});
            _check();
          },
          icon: const Icon(Icons.public_outlined, size: 18),
          label: Text('Volver a ${DriveHost.compiled}'),
        ),
      ],
    );
  }

  /// "2 de 2" cuando el hub informa sus nodos.
  String _nodesHealthLabel() {
    final list = (_health?['nodes'] as List?)?.whereType<Map>() ?? const [];
    final online = list.where((n) => n['online'] == true).length;
    return '$online de ${list.length}';
  }

  /// "Sí" / "No: instala ffmpeg" según lo que diga el servidor.
  String _videoSupport(String key) {
    final video = _health?['video'];
    if (video is! Map) return '—';
    return video[key] == true ? 'Sí' : 'No: instala ffmpeg en el servidor';
  }

  String _uptimeLabel() {
    final up = _health?['uptime'];
    if (up is! num) return '—';
    final s = up.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h h $m min';
    if (m > 0) return '$m min $sec s';
    return '$sec s';
  }
}

// ============ Piezas visuales ============

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Alta/edición de un servidor de archivos del Drive.
class _DriveNodeDialog extends StatefulWidget {
  const _DriveNodeDialog({this.node, this.siblings = const []});

  final Map<String, dynamic>? node;

  /// Los demás servidores: entre ellos se eligen las DEPENDENCIAS.
  final List<Map<String, dynamic>> siblings;

  @override
  State<_DriveNodeDialog> createState() => _DriveNodeDialogState();
}

class _DriveNodeDialogState extends State<_DriveNodeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _priority;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.node != null;

  @override
  void initState() {
    super.initState();
    final n = widget.node ?? const <String, dynamic>{};
    _name = TextEditingController(text: (n['name'] ?? '').toString());
    _url = TextEditingController(text: (n['url'] ?? '').toString());
    _priority = TextEditingController(text: (n['priority'] ?? 100).toString());
    _notes = TextEditingController(text: (n['notes'] ?? '').toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _priority.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre al servidor');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(
        () => _error = 'La dirección debe empezar con http:// o https://',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final priority = int.tryParse(_priority.text.trim()) ?? 100;
      if (_editing) {
        await HsApi.updateDriveNode(
          id: (widget.node!['id'] as num).toInt(),
          name: name,
          url: url,
          priority: priority,
          notes: _notes.text.trim(),
        );
      } else {
        await HsApi.createDriveNode(
          name: name,
          url: url,
          priority: priority,
          notes: _notes.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.dns_outlined,
      title: _editing ? 'Editar servidor' : 'Nuevo servidor del Drive',
      subtitle: 'Donde viven las carpetas y las fotos del Drive.',
      saveLabel: _editing ? 'Guardar cambios' : 'Agregar servidor',
      saving: _saving,
      error: _error,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        TextField(
          key: const ValueKey('drive-node-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Servidor bodega',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('drive-node-url'),
          controller: _url,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Dirección',
            hintText: 'https://drive2.ejemplo.com',
            helperText: 'La URL del servidor de archivos, sin barra al final',
            prefixIcon: Icon(Icons.link),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _priority,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Prioridad',
            helperText: 'Menor gana cuando hay empate de espacio libre',
            prefixIcon: Icon(Icons.sort),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            // Se ve en la CARD del servidor, así que se llama descripción.
            labelText: 'Descripción (opcional)',
            hintText: 'Disco de 2 TB en la bodega',
            helperText: 'Se muestra en la card del servidor, en el diagrama',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          onSubmitted: (_) => _save(),
        ),
        // Las DEPENDENCIAS ya no viven aquí: tienen su propio modal (menú ⋯ →
        // «Dependencias»), porque dentro del formulario no se podían marcar
        // bien y se guardaban sin que se notara.
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Para unificar o separar servidores usa el menú ⋯ de su card → '
                  '«Dependencias».',
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El servidor nuevo se puede usar en cuanto esté en línea. Las '
                  'carpetas que ya existen NO se mueven: se siguen viendo desde '
                  'donde están.',
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// DEPENDENCIAS de un servidor, en su propio modal.
///
/// Antes vivían dentro de «Editar servidor»: en un formulario largo no se
/// veían, se marcaban sin querer y el guardado no se notaba. Aquí es lo único
/// que hay, con el estado actual ya marcado.
class _DependenciesDialog extends StatefulWidget {
  const _DependenciesDialog({required this.node, required this.siblings});

  /// El servidor al que se le configuran las dependencias.
  final Map<String, dynamic> node;

  /// Todos los servidores (se descarta él mismo).
  final List<Map<String, dynamic>> siblings;

  @override
  State<_DependenciesDialog> createState() => _DependenciesDialogState();
}

class _DependenciesDialogState extends State<_DependenciesDialog> {
  late final Set<int> _depends;
  bool _saving = false;
  String? _error;

  int get _id => (widget.node['id'] as num).toInt();
  String get _name => (widget.node['name'] ?? 'Servidor').toString();

  /// Los otros servidores (no puede depender de sí mismo).
  List<Map<String, dynamic>> get _others => [
    for (final n in widget.siblings)
      if ((n['id'] as num?)?.toInt() != _id) n,
  ];

  @override
  void initState() {
    super.initState();
    _depends = {
      for (final id in (widget.node['dependsOn'] as List?) ?? const [])
        if (id is num) id.toInt(),
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HsApi.updateDriveNode(
        id: _id,
        dependsOn: _depends.toList()..sort(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.account_tree_outlined,
      title: 'Dependencias de $_name',
      subtitle: 'Unificar con otros servidores o dejarlo independiente.',
      saveLabel: 'Guardar dependencias',
      saving: _saving,
      error: _error,
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        Text(
          'Sin marcar ninguno, este servidor es INDEPENDIENTE (diferencia). '
          'Marcando uno o varios queda UNIFICADO con ellos: si alguno deja de '
          'responder, ESTE entra en mantenimiento y el Drive lo dice. Puede ser '
          'mutuo (los dos se dependen).',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_others.isEmpty)
          Text(
            'Es el único servidor registrado: no hay otro del que depender.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          )
        else
          for (final other in _others)
            CheckboxListTile(
              key: ValueKey('drive-node-dep-${other['id']}'),
              value: _depends.contains((other['id'] as num).toInt()),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                (other['name'] ?? 'Servidor').toString(),
                style: const TextStyle(fontSize: 13.5),
              ),
              subtitle: Text(
                (other['url'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onChanged: (on) => setState(() {
                final id = (other['id'] as num).toInt();
                if (on == true) {
                  _depends.add(id);
                } else {
                  _depends.remove(id);
                }
              }),
            ),
        const SizedBox(height: 8),
        Text(
          _depends.isEmpty
              ? 'Ahora mismo: independiente.'
              : 'Ahora mismo: unificado con '
                    '${_depends.length} servidor${_depends.length == 1 ? '' : 'es'}.',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }
}

/// Configuración del HUB (dirección del Drive) en su propio modal.
///
/// El panel SIEMPRE habla con el hub: su dirección es una opción DEL HUB, así
/// que se edita aquí y no en una sección suelta de la pantalla.
class _HubConfigDialog extends StatefulWidget {
  const _HubConfigDialog({
    required this.current,
    required this.compiled,
    required this.publicHttp,
    required this.lanFallback,
    required this.onSave,
  });

  /// Dirección propia guardada ('' = usar la de fábrica).
  final String current;
  final String compiled;
  final String publicHttp;
  final String lanFallback;
  final Future<String?> Function(String text) onSave;

  @override
  State<_HubConfigDialog> createState() => _HubConfigDialogState();
}

class _HubConfigDialogState extends State<_HubConfigDialog> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply(String text) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.hub_outlined,
      title: 'Hub del Drive',
      subtitle: 'Dirección con la que el panel llega al hub.',
      saveLabel: 'Guardar dirección',
      saving: _saving,
      error: _error,
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => _apply(_ctrl.text),
      footer: [
        TextButton(
          key: const ValueKey('hub-address-reset'),
          onPressed: _saving
              ? null
              : () {
                  _ctrl.text = '';
                  _apply('');
                },
          child: const Text('Usar la de fábrica'),
        ),
      ],
      children: [
        TextField(
          key: const ValueKey('hub-address-field'),
          controller: _ctrl,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Dirección del Drive',
            hintText: widget.compiled,
            prefixIcon: const Icon(Icons.dns_outlined),
            helperText: 'Vacío = la de fábrica (${widget.compiled})',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _apply,
        ),
        const SizedBox(height: 12),
        Text(
          'Si el nombre público no responde desde esta red (certificado del '
          'router o NAT), la app prueba sola el mismo nombre por HTTP directo '
          '(${widget.publicHttp}) y la dirección local '
          '(${widget.lanFallback}). Aquí solo se cambia si el hub está en otra '
          'dirección.',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Los servidores de archivos NO se abren a internet: solo el '
                  'hub los alcanza. Sus direcciones van en «Servidores del '
                  'Drive».',
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: scheme.primary)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 14, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
