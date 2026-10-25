import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../drive_host.dart';

/// Verde de «todo bien» (el mismo de la tarjeta de Conexión).
const Color _okGreen = Color(0xFF2F9E5B);

/// Ámbar de «esperando» (el mismo de Conexión).
const Color _waitAmber = Color(0xFFD97706);

/// Card con el ESTADO de la conexión con el servidor del Drive.
///
/// Antes, cuando el listado fallaba y no había nada que mostrar, se dibujaba un
/// estado vacío a PÁGINA COMPLETA: un icono gigante, la excepción cruda
/// (`HandshakeException … tls_record.cc:127`) y un botón. Eso no decía qué
/// servidor era, por qué protocolo iba ni qué revisar; y con la conexión
/// funcionando no había ni rastro de esa información.
///
/// Ahora el estado vive en una CARD con la dirección, el protocolo, cuánto
/// tardó la última respuesta y una pista cuando el error se puede reconocer; y
/// la MISMA card, reducida a una franja ([compact]), se dibuja cuando todo va
/// bien, para que los datos del servidor estén a la vista aunque esté
/// conectado.
class DriveStatusCard extends StatelessWidget {
  const DriveStatusCard({
    super.key,
    required this.drive,
    this.onRetry,
    this.compact = false,
  });

  final DriveBase drive;

  /// Qué hace «Reintentar» / «Actualizar» (normalmente `drive.refresh`).
  final VoidCallback? onRetry;

  /// true = franja de una línea (el Drive está conectado).
  final bool compact;

  bool get _failed => drive.error != null;

  /// El fallo es MANTENIMIENTO (un servidor depende de otro que no responde),
  /// no una red caída: el hub ya dijo qué pasó y hay que decirlo con sus
  /// palabras, en ámbar y no en rojo.
  bool get _maintenance =>
      _failed &&
      (drive.error ?? '').toLowerCase().contains('mantenimiento');

  bool get _busy => !_failed && drive.conn == DriveConn.checking;

  Color get _color => _maintenance
      ? _waitAmber
      : _failed
      ? const Color(0xFFDC2626)
      : _busy
      ? _waitAmber
      : _okGreen;

  String get _title => _maintenance
      ? 'Drive en mantenimiento'
      : _failed
      ? 'Sin conexión con el Drive'
      : _busy
      ? 'Conectando con el Drive'
      : 'Conectado al Drive';

  String get _state => _failed
      ? 'Sin respuesta'
      : _busy
      ? 'Sin comprobar'
      : 'En línea';

  String get _iconLabel => _maintenance
      ? 'Mantenimiento'
      : _failed
      ? 'Sin conexión'
      : _busy
      ? 'Sin comprobar'
      : 'En línea';

  IconData get _icon => _maintenance
      ? Icons.engineering_outlined
      : _failed
      ? Icons.cloud_off_outlined
      : _busy
      ? Icons.sync_rounded
      : Icons.cloud_done_outlined;

  /// Dirección del servidor tal como se lee en la card (sin el esquema).
  ///
  /// Un drive LOCAL (una carpeta de este equipo) no tiene servidor: se dice.
  String get _address {
    if (!drive.isRemote) return 'Carpeta de este equipo';
    final base = DriveHost.base;
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) return base;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Uri? get _server => drive.isRemote ? Uri.tryParse(DriveHost.base) : null;

  /// `HTTPS` cuando la dirección va cifrada; `HTTP` cuando va en claro.
  String? get _protocol {
    final server = _server;
    if (server == null) return null;
    return server.scheme.toLowerCase() == 'https' ? 'HTTPS' : 'HTTP';
  }

  /// «0.34 s» / «820 ms» de la última respuesta buena (null si no hay).
  String? get _latency {
    final d = drive.lastResponse;
    if (d == null || _failed) return null;
    final ms = d.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  /// Pista para el error MÁS COMÚN: apuntar al hub por `https` cuando ese
  /// puerto habla HTTP sin TLS (responde `WRONG_VERSION_NUMBER` en el
  /// handshake). También cubre el servidor apagado y el puerto equivocado.
  String? get _hint {
    if (!drive.isRemote) return null;
    final e = (drive.error ?? '').toLowerCase();
    final server = _server;
    final https = server?.scheme.toLowerCase() == 'https';
    final tls =
        e.contains('handshake') ||
        e.contains('wrong_version') ||
        e.contains('certificate');
    if (https && tls) {
      final host = server!.host;
      final port = server.hasPort ? ':${server.port}' : '';
      return 'Esa dirección va por HTTPS, pero el hub de este puerto habla '
          'HTTP sin cifrar. Prueba con http://$host$port en Configuraciones.';
    }
    if (e.contains('timed out') || e.contains('timeout')) {
      return 'El servidor no contestó a tiempo: revisa que esté encendido y '
          'que la red llegue hasta él.';
    }
    if (e.contains('refused') || e.contains('nada escucha')) {
      return 'Nadie contesta en ese puerto: revisa la dirección y que el hub '
          'esté corriendo.';
    }
    return null;
  }

  /// De dónde sale la dirección (solo cuando NO es la de fábrica).
  String? get _origin {
    if (!drive.isRemote) return null;
    if (DriveHost.usingFallback) return 'Respaldo automático';
    if (DriveHost.isCustom) return 'Dirección propia';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _color;
    // Un tinte del color del estado sobre la superficie de la card: se nota el
    // estado sin gritar y sigue leyéndose como una tarjeta del panel.
    final surface = Color.alphaBlend(
      color.withValues(alpha: .05),
      theme.cardColor,
    );

    if (compact) return _strip(scheme, color, surface);
    return _card(context, theme, scheme, color, surface);
  }

  /// Franja de una línea: punto de estado + dirección + latencia.
  Widget _strip(ColorScheme scheme, Color color, Color surface) {
    final bits = <String>[_iconLabel, _address, ?_latency];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .26)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              bits.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: _failed ? 'Volver a intentar' : 'Actualizar',
              visualDensity: VisualDensity.compact,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  /// Card completa: cabecera con estado, datos del servidor y detalle del fallo.
  Widget _card(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    Color color,
    Color surface,
  ) {
    final hint = _hint;
    final chips = <Widget>[
      if (_protocol != null)
        _Chip(
          icon: _protocol == 'HTTPS'
              ? Icons.lock_outline_rounded
              : Icons.lock_open_rounded,
          label: _protocol!,
          color: color,
        ),
      if (_latency != null)
        _Chip(icon: Icons.timer_outlined, label: _latency!, color: color),
      if (_origin != null)
        _Chip(icon: Icons.settings_ethernet, label: _origin!, color: color),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filo superior con el color del estado: se reconoce de reojo.
          Container(height: 3, color: color),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .12),
                      ),
                      child: Icon(_icon, size: 21, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _address,
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
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: .3)),
                      ),
                      child: Text(
                        _state,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
                if (_failed) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: .22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drive.error!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (hint != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 15,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  hint,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_failed ? 'Reintentar' : 'Actualizar'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip pequeño de dato (protocolo, latencia, origen de la dirección).
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
