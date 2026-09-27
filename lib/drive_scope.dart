import 'package:flutter/widgets.dart';

import 'drive_base.dart';

/// Provee el drive (local o remoto) único de la app a todo el árbol.
class DriveScope extends InheritedNotifier<DriveBase> {
  const DriveScope({
    super.key,
    required DriveBase drive,
    required super.child,
  }) : super(notifier: drive);

  static DriveBase of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DriveScope>();
    assert(scope != null, 'DriveScope no encontrado en el árbol');
    return scope!.notifier!;
  }

  /// Igual que [of] pero null-safe (para saber si ya hay uno arriba).
  static DriveBase? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DriveScope>();
    return scope?.notifier;
  }
}
