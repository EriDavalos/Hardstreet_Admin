import 'package:flutter/widgets.dart';

/// En plataformas que no son web el visor usa su WebView nativo; este stub
/// solo existe para que el import condicional compile.
Widget driveWebPlayer(
  BuildContext context, {
  required String html,
  required String cacheKey,
}) => const SizedBox.shrink();
