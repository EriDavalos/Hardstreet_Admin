import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_settings.dart';
import '../drive_api_service.dart';
import '../drive_host.dart';

/// Página "Conexión": estado del enlace con el servidor del drive.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.driveApi});

  final DriveApiService driveApi;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  Timer? _timer;

  /// Lo que el usuario escribe en "Dirección del servidor" (vacío = la de
  /// fábrica). Arranca con lo que haya guardado.
  late final TextEditingController _hostCtrl = TextEditingController(
    text: DriveHost.custom ?? '',
  );
  String? _hostError;
  String? _hostSaved;

  // Sondeo de salud con package:http: funciona en web y nativo.
  // (dart:io HttpClient lanza UnsupportedError en Chrome.)
  Future<({int statusCode, String body})> httpGet(
    String url, {
    required Duration timeout,
  }) async {
    final r = await http.get(Uri.parse(url)).timeout(timeout);
    return (statusCode: r.statusCode, body: r.body);
  }

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

  @override
  void initState() {
    super.initState();
    _check();
    // Sondeo cada 15 s mientras la página está visible.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hostCtrl.dispose();
    super.dispose();
  }

  /// Guarda la dirección escrita (o vuelve a la de fábrica si está vacía).
  Future<void> _saveHost(String? value) async {
    final text = (value ?? '').trim();
    if (!DriveHost.isValid(text)) {
      setState(() {
        _hostError = 'Escribe una dirección como http://192.168.1.72:4000';
        _hostSaved = null;
      });
      return;
    }
    final ok = await AppSettings.instance.setDriveHost(text);
    if (!mounted) return;
    setState(() {
      _hostError = ok ? null : 'Esa dirección no se pudo guardar.';
      _hostSaved = ok
          ? (DriveHost.isCustom
                ? 'Guardado: ${DriveHost.base}. Ya se está usando en todos los módulos.'
                : 'Guardado: se usa la dirección de fábrica (${DriveHost.compiled}).')
          : null;
      if (ok && !DriveHost.isCustom) _hostCtrl.text = '';
    });
    if (ok && mounted) {
      // Sin reiniciar: el cliente del drive resuelve la base en cada petición.
      unawaited(widget.driveApi.refresh());
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    final sw = Stopwatch()..start();
    String? err;
    Map<String, dynamic>? health;
    try {
      // Se prueba la dirección CONFIGURADA ([DriveHost]): así, al cambiarla, el
      // botón "Probar conexión" comprueba la nueva ANTES de reiniciar la app.
      final r = await httpGet(
        '${DriveHost.base}/api/health',
        timeout: const Duration(seconds: 5),
      );
      if (r.statusCode == 200) {
        health = parseJson(r.body);
      } else {
        err = 'HTTP ${r.statusCode}';
      }
    } catch (e) {
      err = e.toString();
    }
    sw.stop();
    if (!mounted) return;
    setState(() {
      _latencyMs = sw.elapsedMilliseconds;
      _lastCheck = DateTime.now();
      _health = health;
      _lastError = err;
    });
    _checking = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = widget.driveApi.conn == DriveConn.online && _health != null;
    final checking = _checking;

    final (color, icon, label) = checking
        ? (Colors.amber, Icons.sync, 'Verificando…')
        : online
        ? (const Color(0xFF2F6BFF), Icons.cloud_done_outlined, 'Conectado')
        : (scheme.error, Icons.cloud_off_outlined, 'Sin conexión');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
      children: [
        // ===== Tarjeta principal de estado =====
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (online)
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .12),
                      ),
                    ),
                  Icon(icon, size: 64, color: color),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Servidor: ${DriveHost.base}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: checking ? null : _check,
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Probar conexión'),
              ),
            ],
          ),
        ),
        if (DriveHost.usingFallback) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Conexión local automática',
            children: [
              Text(
                'El nombre público no respondió desde esta red (certificado '
                'del router o NAT), así que la app está usando la dirección '
                'local ${DriveHost.lanFallback}. Funciona mientras estés en la '
                'red de la oficina.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
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
          ),
        ],
        const SizedBox(height: 16),

        // ===== Dirección del servidor (editable) =====
        _SectionCard(
          title: 'Dirección del servidor',
          children: [
            Text(
              'El panel llega al servidor por su dirección. Dentro de la red de '
              'la oficina el nombre público (${DriveHost.compiled}) puede '
              'responder el router con un certificado que el dispositivo '
              'rechaza ("unable to get local issuer certificate"). Si eso pasa, '
              'la app prueba sola el nombre público por HTTP directo '
              '(${DriveHost.publicHttp}) y la dirección local '
              '(${DriveHost.lanFallback}). También puedes escribirla aquí a mano.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('drive-host-field'),
              controller: _hostCtrl,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Dirección del drive',
                hintText: DriveHost.compiled,
                prefixIcon: const Icon(Icons.dns_outlined),
                helperText: 'Vacío = la de fábrica (${DriveHost.compiled})',
                errorText: _hostError,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _saveHost,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  key: const ValueKey('drive-host-save'),
                  onPressed: () => _saveHost(_hostCtrl.text),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar'),
                ),
                const SizedBox(width: 10),
                TextButton(
                  key: const ValueKey('drive-host-reset'),
                  onPressed: () {
                    _hostCtrl.text = '';
                    _saveHost(null);
                  },
                  child: const Text('Usar la de fábrica'),
                ),
              ],
            ),
            if (_hostSaved != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _hostSaved!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ===== Detalles =====
        _SectionCard(
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
            _Row('Carpeta de datos', _health?['root'] as String? ?? '—'),
            // Los vídeos sacan su miniatura (y su versión ligera) con ffmpeg
            // EN EL SERVIDOR. Si falta, las tarjetas de vídeo solo pueden
            // enseñar el icono: aquí se ve el motivo en vez de parecer un
            // fallo de la app.
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
        ),
        const SizedBox(height: 16),

        // ===== Falta ffmpeg en el servidor =====
        if (online && _health?['video'] is Map &&
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
        if (online && _health?['video'] is Map &&
            (_health!['video'] as Map)['posters'] != true)
          const SizedBox(height: 16),

        // ===== Cómo solucionarlo =====
        if (!online)
          _SectionCard(
            title: 'Si no conecta, revisa',
            children: [
              _Bullet(
                'Que el servidor esté encendido y con el servicio corriendo:',
              ),
              _Mono('sudo systemctl status hardstreet-drive'),
              _Bullet('Que el firewall permita el puerto:'),
              _Mono('sudo ufw allow 4000/tcp'),
              _Bullet(
                'Que la dirección sea la correcta para la red en la que estás:',
              ),
              _Mono('${DriveHost.compiled}  (la de fábrica)'),
              _Mono(
                '${DriveHost.publicHttp}  (si el HTTPS falla en el teléfono)',
              ),
              _Mono(
                '${DriveHost.lanFallback}  (dentro de la red de la oficina)',
              ),
              _Bullet('Se cambia arriba, en "Dirección del servidor".'),
            ],
          ),
      ],
    );
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
