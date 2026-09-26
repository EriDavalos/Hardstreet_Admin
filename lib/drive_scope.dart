import 'package:flutter/widgets.dart';

import 'drive_service.dart';

/// Provee el [DriveService] único de la app a todo el árbol de widgets.
class DriveScope extends InheritedNotifier<DriveService> {
  const DriveScope({
    super.key,
    required DriveService drive,
    required super.child,
  }) : super(notifier: drive);

  static DriveService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DriveScope>();
    assert(scope != null, 'DriveScope no encontrado en el árbol');
    return scope!.notifier!;
  }

  /// Igual que [of] pero null-safe (para saber si ya hay uno arriba).
  static DriveService? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DriveScope>();
    return scope?.notifier;
  }
}
