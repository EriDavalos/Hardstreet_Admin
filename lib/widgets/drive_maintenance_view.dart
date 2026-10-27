import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../drive_host.dart';

/// Ámbar de «esperando/mantenimiento» (el mismo de Conexión).
const Color _amber = Color(0xFFD97706);

/// Vista de MANTENIMIENTO del Drive: ocupa TODA la vista y va centrada.
///
/// Antes el aviso era una tarjeta pequeña arriba, sobre una lista vacía: no se
/// leía como «el Drive está parado» y parecía que faltaba contenido. Ahora la
/// vista entera es el aviso —sin encabezado, sin carpetas, sin botones de
/// subir— y se centra en el hueco disponible (también en el celular, donde se
/// puede tirar hacia abajo para reintentar).
///
/// No nombra servidores dependientes: ese detalle vive en Conexión.
class DriveMaintenanceView extends StatelessWidget {
  const DriveMaintenanceView({super.key, required this.drive, this.onRetry});

  final DriveBase drive;

  /// Qué hace «Reintentar» (normalmente `drive.refresh`).
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final busy = drive.loading;

    final retry = onRetry;
    Future<void> refresh() async {
      if (retry != null) await retry();
    }

    return DecoratedBox(
      key: const ValueKey('drive-maintenance'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              _amber.withValues(alpha: dark ? .10 : .06),
              scheme.surface,
            ),
            scheme.surface,
            Color.alphaBlend(
              _amber.withValues(alpha: dark ? .05 : .04),
              scheme.surface,
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Resplandor suave arriba: da profundidad sin imágenes ni blur.
          Positioned(
            top: -170,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 460,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _amber.withValues(alpha: dark ? .16 : .10),
                        _amber.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: _panel(context, scheme, busy),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// La tarjeta central del aviso (entra con un fundido corto y único).
  Widget _panel(BuildContext context, ColorScheme scheme, bool busy) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            _amber.withValues(alpha: .05),
            Theme.of(context).cardColor,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _amber.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(),
            const SizedBox(height: 18),
            // Etiqueta «moderna» del estado, en versalitas.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _amber.withValues(alpha: .30)),
              ),
              child: Text(
                'MANTENIMIENTO',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _amber,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Drive en mantenimiento',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
            ),
            const SizedBox(height: 10),
            Text(
              driveMaintenanceNotice,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(Icons.dns_outlined, _serverLabel()),
                _chip(Icons.cloud_off_outlined, 'Sin servidores disponibles'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : (onRetry == null ? null : () => onRetry!()),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 19),
                label: Text(busy ? 'Comprobando…' : 'Reintentar'),
                style: FilledButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Los archivos vuelven solos en cuanto un servidor responda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: scheme.onSurfaceVariant.withValues(alpha: .85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Disco con la herramienta: el emblema del aviso.
  Widget _badge() {
    return Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _amber.withValues(alpha: .30),
            _amber.withValues(alpha: .10),
          ],
        ),
        border: Border.all(color: _amber.withValues(alpha: .35)),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _amber.withValues(alpha: .14),
        ),
        child: const Icon(Icons.engineering_rounded, size: 34, color: _amber),
      ),
    );
  }

  /// Chip pequeño con un dato del estado.
  Widget _chip(IconData icon, String label) {
    return Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _amber),
              const SizedBox(width: 6),
              // Flexible: una dirección larga (o un nombre de equipo) se
              // recorta en vez de desbordar en el celular.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dirección del hub tal como se lee en la vista (sin el esquema).
  String _serverLabel() {
    if (!drive.isRemote) return 'Carpeta de este equipo';
    final base = DriveHost.base;
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) return base;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}
