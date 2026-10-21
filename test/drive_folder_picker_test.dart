import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/drive_folder_picker.dart';

// ==================================================================
// HARD STREET ADMIN — Selector de carpeta del Drive
// ==================================================================
// Al compartir una carpeta (Administrar paquete / Empresas) el selector se
// abre en la RAÍZ y SIEMPRE tiene que dejar retroceder:
//
//   * aunque la carpeta abierta esté vacía (antes el "Subir un nivel" vivía
//     dentro del listado de subcarpetas: sin subcarpetas no había forma de
//     volver y el diálogo se quedaba atrapado);
//   * las migas de pan anteriores se pueden tocar para volver de un salto.
// ==================================================================

/// Registra las rutas que el selector pide al servidor.
class _Loads {
  final calls = <List<String>>[];

  Future<List<String>> call(List<String> path) async {
    calls.add(List<String>.of(path));
    return const <String>[];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Loads loads, {
  List<String> initial = const <String>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DriveFolderPicker(
          base: '',
          initial: initial,
          load: loads.call,
          conflict: (_) => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la carpeta vacía deja volver atrás', (tester) async {
    final loads = _Loads();
    await _pump(tester, loads, initial: const ['Boda']);

    expect(loads.calls.single, const ['Boda']);
    // El listado está vacío (no hay subcarpetas), pero se puede subir.
    expect(find.textContaining('no tiene subcarpetas'), findsOneWidget);
    expect(find.text('Subir un nivel'), findsOneWidget);

    await tester.tap(find.text('Subir un nivel'));
    await tester.pumpAndSettle();

    expect(loads.calls.last, isEmpty);
  });

  testWidgets('abierto en la raíz no hay nada a lo que subir', (tester) async {
    final loads = _Loads();
    await _pump(tester, loads);

    expect(loads.calls.single, isEmpty);
    expect(find.text('Subir un nivel'), findsNothing);
  });

  testWidgets('las migas de pan vuelven a la carpeta tocada', (tester) async {
    final loads = _Loads();
    await _pump(tester, loads, initial: const ['Boda', 'Fiesta']);

    expect(loads.calls.single, const ['Boda', 'Fiesta']);

    // Tocar "Boda" vuelve a ESA carpeta (no a la raíz).
    await tester.tap(find.text('Boda'));
    await tester.pumpAndSettle();

    expect(loads.calls.last, const ['Boda']);
  });
}
