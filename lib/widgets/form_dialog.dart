import 'package:flutter/material.dart';

import '../theme.dart';

/// Diálogo de formulario ESTÁNDAR del panel (usuarios, clientes, roles,
/// paquetes y permisos):
/// - Cabecera con avatar degradado + título/subtítulo y botón cerrar.
/// - Ancho RESPONSIVO: en computadora se ensancha para aprovechar el espacio
///   (configurable con [maxWidth]); en móvil se ajusta a la pantalla.
/// - Contenido en secciones ([FormSection]) con etiqueta en mayúsculas.
/// - Banner de error destacado y acciones Cancelar / Guardar (spinner).
/// - Opcional: barra lateral de menú ([FormMenu]) para modales grandes.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.subtitle,
    this.saving = false,
    this.error,
    this.maxWidth = 440,
    this.minWidth,
    this.menu,
    this.contentHeight,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final bool saving;
  final String? error;

  /// Ancho máximo del contenido. En pantallas grandes el diálogo crece hasta
  /// aquí; en móvil nunca excede el ancho disponible (menos márgenes).
  final double maxWidth;

  /// Ancho mínimo deseado (útil en computadora para modales compactos).
  final double? minWidth;

  /// Menú lateral opcional (vista desktop/ancha): lista de secciones para
  /// saltar a un punto del formulario largo.
  final List<FormMenu>? menu;

  /// Altura fija del contenido (para listas internas con scroll), p. ej.
  /// el modal de permisos. Si es null, el diálogo mide lo que ocupa.
  final double? contentHeight;

  /// Widgets extra a la IZQUIERDA de Cancelar (p. ej. "Asignar del catálogo").
  final List<Widget>? footer;

  /// Ancho objetivo del diálogo según pantalla:
  /// móvil respeta la pantalla; desktop crece hasta [maxWidth].
  double _targetWidth(double screen) {
    final max = maxWidth <= 0 ? 440.0 : maxWidth;
    final min = minWidth ?? 0;
    // En pantallas angostas: ancho disponible menos márgenes de la ventana.
    final available = screen - 32;
    if (available < max) {
      // En móvil el ancho lo decide AlertDialog (insetPadding); no forzamos.
      return 0;
    }
    final target = max < min ? min : max;
    return target.clamp(min, available);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context).width;
    final target = _targetWidth(screen);
    final hasMenu = (menu?.length ?? 0) > 1 && screen > 760;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: .30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: saving ? null : onCancel,
            icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      // NOTA: la animación de entrada va DENTRO del scroll (envolviendo la
      // columna), nunca alrededor del SingleChildScrollView/ListView:
      // un LayoutBuilder/Opacity animado por encima de scrollables anidados
      // dispara el assertion '!semantics.parentDataDirty' del framework.
      content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: target <= 0 ? double.infinity : target,
            minWidth: target <= 0 ? 0 : target * .96,
          ),
          child: SizedBox(
            height: contentHeight,
            child: SingleChildScrollView(
              child: TweenAnimationBuilder<double>(
                // Animación sutil de entrada: el formulario se desvanece y
                // sube (solo el contenido, no el contenedor del scroll).
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 12),
                    child: child,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasMenu)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 168,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final item in menu!)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: _FormMenuItem(item: item),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: _FormBody(error: error, children: children)),
                        ],
                      )
                    else
                      _FormBody(error: error, children: children),
                  ],
                ),
              ),
            ),
          ),
      ),
      actions: [
        Row(
          children: [
            ...?footer,
            const Spacer(),
            TextButton(
              onPressed: saving ? null : onCancel,
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(saveLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cuerpo del formulario (children + banner de error).
class _FormBody extends StatelessWidget {
  const _FormBody({required this.children, this.error});

  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.error.withValues(alpha: .35)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.error,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Ítem del menú lateral de un [FormDialog] largo: al tocarlo hace scroll
/// hasta la sección con esa clave global.
class FormMenu {
  const FormMenu({required this.label, required this.scrollTo});

  final String label;

  /// Llave global de la sección destino (pásala a [FormSection.keyOf] o
  /// directamente el GlobalKey del widget ancla).
  final GlobalKey scrollTo;
}

class _FormMenuItem extends StatelessWidget {
  const _FormMenuItem({required this.item});

  final FormMenu item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        final ctx = item.scrollTo.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          item.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Sección de formulario: etiqueta en mayúsculas + campo(s).
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: .9,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
