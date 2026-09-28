import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_platform.dart';

/// Ventana OBLIGATORIA de actualización: no se puede cerrar ni desplegar
/// detrás. Ofrece la descarga según el dispositivo (.exe / .apk).
class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({
    super.key,
    required this.currentVersion,
    required this.requiredVersion,
    required this.notes,
    required this.downloadUrl,
  });

  final String currentVersion;
  final String requiredVersion;
  final String notes;
  final String downloadUrl;

  static Future<void> show(
    BuildContext context, {
    required String currentVersion,
    required String requiredVersion,
    required String notes,
    required String downloadUrl,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      useSafeArea: false,
      builder: (_) => PopScope(
        canPop: false, // Esc y back NO cierran la ventana
        child: ForceUpdateDialog(
          currentVersion: currentVersion,
          requiredVersion: requiredVersion,
          notes: notes,
          downloadUrl: downloadUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAndroid = isAndroidPlatform; // false en web
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: .12),
                ),
                child: Icon(Icons.system_update_alt_rounded,
                    size: 38, color: scheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'Actualización requerida',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Tu versión $currentVersion ya no es compatible.\n'
                'Necesitas la versión $requiredVersion para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    notes,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: downloadUrl.isEmpty
                    ? null
                    : () =>
                        launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.download_rounded),
                label: Text(isAndroid
                    ? 'Descargar actualización (.apk)'
                    : 'Descargar actualización (.exe)'),
              ),
              if (downloadUrl.isEmpty)
                Text(
                  'El servidor no publicó el enlace de descarga aún.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.error,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Descarga e instala la nueva versión para volver a entrar.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
