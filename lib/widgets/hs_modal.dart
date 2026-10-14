/// Modal del panel: en MÓVIL ocupa TODA la pantalla; en computadora sigue
/// siendo el diálogo flotante de siempre.
///
/// REGLA: los formularios y selectores del panel (clientes, paquetes, roles,
/// permisos, agendas, carpetas del Drive…) se abren igual que con `showDialog`
/// —el `builder` devuelve el mismo `AlertDialog`/`FormDialog`— pero aquí, en
/// una pantalla angosta, se les quitan los márgenes, las esquinas y la sombra:
/// la propia superficie del diálogo cubre la pantalla, con el título arriba,
/// el contenido al centro (desplazable) y las acciones abajo.
///
/// Las confirmaciones cortas (¿Eliminar…?) NO usan esto a propósito: ahí un
/// cuadro chico se lee mejor que una pantalla completa con dos botones.
library;

import 'package:flutter/material.dart';

/// Ancho a partir del cual una pantalla ya es "de computadora". Es el MISMO
/// umbral que usan las páginas para su modo compacto (isCompact).
const double kHsPhoneWidth = 620;

/// ¿Estamos en una pantalla de móvil?
bool hsIsPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kHsPhoneWidth;

/// `showDialog` que en móvil muestra el modal a PANTALLA COMPLETA.
Future<T?> showHsModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final phone = hsIsPhone(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    builder: (ctx) =>
        phone ? _PhoneModalShell(child: builder(ctx)) : builder(ctx),
  );
}

/// Estira el diálogo a toda la pantalla en móvil.
///
/// El `AlertDialog` de dentro coloca su título, su contenido (en un `Flexible`)
/// y sus acciones; lo único que faltaba era que su superficie no se encogiera
/// al tamaño del contenido ni dejara márgenes.
class _PhoneModalShell extends StatelessWidget {
  const _PhoneModalShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dialogTheme: theme.dialogTheme.copyWith(
          // Sin márgenes ni esquinas: la superficie llega a los bordes.
          insetPadding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          // Y sin encogerse al contenido: alto y ancho de la pantalla.
          constraints: const BoxConstraints(
            minWidth: double.infinity,
            minHeight: double.infinity,
          ),
        ),
      ),
      child: child,
    );
  }
}
