import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../drive_api_service.dart';

/// Página "Conexión": estado del enlace con el servidor del drive.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.driveApi});

  final DriveApiService driveApi;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  Timer? _timer;

  // Sondeo de salud con package:http: funciona en web y nativo.
  // (dart:io HttpClient lanza UnsupportedError en Chrome.)
  Future<({int statusCode, String body})> httpGet(
      String url, {required Duration timeout}) async {
    final r = await http
        .get(Uri.parse(url))
        .timeout(timeout);
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
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    final sw = Stopwatch()..start();
    String? err;
    Map<String, dynamic>? health;
    try {
      final r = await httpGet(
        '${widget.driveApi.base}/api/health',
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
            ? (const Color(0xFF22A55B), Icons.cloud_done_outlined, 'Conectado')
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
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Servidor: ${widget.driveApi.base}',
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
        const SizedBox(height: 16),

        // ===== Detalles =====
        _SectionCard(
          title: 'Detalles de la conexión',
          children: [
            _Row('Dirección', widget.driveApi.base),
            _Row(
              'Latencia',
              _latencyMs == null ? '—' : '$_latencyMs ms',
            ),
            _Row(
              'Última comprobación',
              _lastCheck == null
                  ? '—'
                  : '${_lastCheck!.hour.toString().padLeft(2, '0')}:${_lastCheck!.minute.toString().padLeft(2, '0')}:${_lastCheck!.second.toString().padLeft(2, '0')}',
            ),
            _Row(
              'Uptime del servidor',
              _uptimeLabel(),
            ),
            _Row('Servicio', _health?['service'] as String? ?? '—'),
            _Row(
              'Carpeta de datos',
              _health?['root'] as String? ?? '—',
            ),
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

        // ===== Cómo solucionarlo =====
        if (!online)
          _SectionCard(
            title: 'Si no conecta, revisa',
            children: [
              _Bullet('Que el servidor esté encendido y con el servicio corriendo:'),
              _Mono('sudo systemctl status hardstreet-drive'),
              _Bullet('Que el firewall permita el puerto:'),
              _Mono('sudo ufw allow 4000/tcp'),
              _Bullet('Que la IP coincida (configurable con --dart-define=DRIVE_API=…).'),
            ],
          ),
      ],
    );
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
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
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
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
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
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
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
