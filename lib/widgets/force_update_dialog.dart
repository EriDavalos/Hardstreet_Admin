import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../app_updater.dart';

/// Fases del flujo de actualización dentro del MISMO modal.
enum _Phase { idle, downloading, installing, installed, error }

/// Ventana de actualización: descarga la nueva versión DENTRO de la app
/// (barra de progreso en este mismo modal) y la instala sin pasar por el
/// navegador.
/// - `optional: false` (obligatoria): no se puede cerrar ni cancelar.
/// - `optional: true` (banner): se puede cerrar mientras no descargue.
class ForceUpdateDialog extends StatefulWidget {
  const ForceUpdateDialog({
    super.key,
    required this.currentVersion,
    required this.requiredVersion,
    required this.notes,
    required this.downloadUrl,
    this.optional = false,
  });

  final String currentVersion;
  final String requiredVersion;
  final String notes;
  final String downloadUrl;

  /// true = actualización opcional (modal cerrable); false = obligatoria.
  final bool optional;

  static Future<void> show(
    BuildContext context, {
    required String currentVersion,
    required String requiredVersion,
    required String notes,
    required String downloadUrl,
    bool optional = false,
  }) {
    return showDialog(
      context: context,
      // El modal opcional se cierra con clic fuera; el obligatorio no.
      barrierDismissible: optional,
      barrierColor: optional ? Colors.black54 : Colors.black87,
      useSafeArea: false,
      builder: (_) => ForceUpdateDialog(
        currentVersion: currentVersion,
        requiredVersion: requiredVersion,
        notes: notes,
        downloadUrl: downloadUrl,
        optional: optional,
      ),
    );
  }

  @override
  State<ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<ForceUpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = -1; // -1 = el servidor no informó el tamaño
  String? _error;

  bool get _isAndroid => isAndroidPlatform;

  /// Etiqueta del archivo según plataforma.
  String get _fileKind => _isAndroid ? '.apk' : '.exe';

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = -1;
      _error = null;
    });
    try {
      final file = await AppUpdater.downloadFn(
        widget.downloadUrl,
        fileName: _isAndroid
            ? 'hardstreet-update.apk'
            : 'HardstreetAdmin-setup.exe',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.installing);
      // En Windows el instalador reemplaza los archivos y cierra la app
      // (esta llamada no regresa). En Android abre el instalador del
      // sistema SOBRE la app y regresa.
      await AppUpdater.installFn(file);
      if (!mounted) return;
      setState(() => _phase = _Phase.installed);
    } on AppUpdateCancelled {
      // El usuario canceló: volver a la pantalla inicial del modal.
      if (mounted) setState(() => _phase = _Phase.idle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e is AppUpdateException
            ? e.message
            : 'No se pudo descargar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Mientras descarga, ni el back ni el clic fuera cancelan solos:
    // hay botón "Cancelar" explícito (el obligatorio nunca se cierra).
    return PopScope(
      canPop: widget.optional && _phase != _Phase.downloading,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        // Ancho FIJO: la barra de progreso (que expande al máximo disponible)
        // estiraba el modal al ancho de la pantalla. Con 420px la barra ocupa
        // exactamente el ancho interior del modal y el tamaño no salta entre
        // fases.
        child: SizedBox(
          width: 420,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(scheme),
                const SizedBox(height: 18),
                Text(
                  _title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.optional
                      ? 'Tienes la versión ${widget.currentVersion}. '
                            'La versión ${widget.requiredVersion} ya está disponible.'
                      : 'Tu versión ${widget.currentVersion} ya no es compatible.\n'
                            'Necesitas la versión ${widget.requiredVersion} para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                if (widget.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.notes,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                ..._actions(context, scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title => switch (_phase) {
    _Phase.idle =>
      widget.optional ? 'Actualización disponible' : 'Actualización requerida',
    _Phase.downloading => 'Descargando actualización',
    _Phase.installing => 'Instalando actualización',
    _Phase.installed => 'Instalación iniciada',
    _Phase.error => 'No se pudo descargar',
  };

  Widget _header(ColorScheme scheme) {
    final (icon, color) = switch (_phase) {
      _Phase.idle => (Icons.system_update_alt_rounded, scheme.primary),
      _Phase.downloading => (Icons.downloading_rounded, scheme.primary),
      _Phase.installing => (Icons.install_desktop_rounded, scheme.primary),
      _Phase.installed => (Icons.check_circle_outline_rounded, Colors.green),
      _Phase.error => (Icons.error_outline_rounded, scheme.error),
    };
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .12),
      ),
      child: Icon(icon, size: 38, color: color),
    );
  }

  List<Widget> _actions(BuildContext context, ColorScheme scheme) {
    switch (_phase) {
      case _Phase.idle:
        return [
          FilledButton.icon(
            onPressed: widget.downloadUrl.isEmpty
                ? null
                : () => _startDownload(),
            icon: const Icon(Icons.download_rounded),
            label: Text('Descargar e instalar ($_fileKind)'),
          ),
          if (widget.downloadUrl.isEmpty)
            Text(
              'El servidor no publicó el enlace de descarga aún.',
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
          const SizedBox(height: 6),
          Text(
            'Se descarga aquí mismo y se instala automáticamente.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ];
      case _Phase.downloading:
        final known = _total > 0;
        final value = known ? (_received / _total).clamp(0.0, 1.0) : null;
        return [
          LinearProgressIndicator(
            value: value,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            known
                ? '${_mb(_received)} de ${_mb(_total)} '
                      '(${((_received / _total) * 100).toStringAsFixed(0)}%)'
                : '${_mb(_received)} descargados…',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          // Cancelar solo existe en el modal opcional: el obligatorio
          // exige actualizar para entrar.
          if (widget.optional)
            TextButton.icon(
              onPressed: AppUpdater.cancelDownload,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancelar'),
            ),
        ];
      case _Phase.installing:
        return [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            _isAndroid
                ? 'Abriendo el instalador del sistema…\nConfirma "Instalar" '
                      'en el panel que aparece.'
                : 'Instalando la nueva versión…\nLa aplicación se cerrará '
                      'y se volverá a abrir automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ];
      case _Phase.installed:
        // Solo Android llega aquí: el instalador del sistema quedó abierto.
        return [
          Text(
            'Sigue las instrucciones del instalador del sistema para '
            'terminar de actualizar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (widget.optional)
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Entendido'),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _phase = _Phase.idle),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
        ];
      case _Phase.error:
        return [
          Text(
            _error ?? 'Error desconocido.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.error),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _startDownload(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ];
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
