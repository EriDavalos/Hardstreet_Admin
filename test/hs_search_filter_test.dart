import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/hs_search_filter.dart';

/// Módulo de prueba: reproduce el patrón de los módulos reales (búsqueda +
/// botón de filtros que abre el modal).
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _query = '';
  String _role = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HsSearchFilterBar(
              hint: 'Buscar usuario…',
              initial: _query,
              onChanged: (v) => setState(() => _query = v),
              groups: const [
                HsFilterGroup(
                  id: 'role',
                  title: 'Rol',
                  options: [
                    HsFilterOption(
                      value: '',
                      label: 'Todos',
                      count: 8,
                      icon: Icons.groups_rounded,
                    ),
                    HsFilterOption(
                      value: 'Admin',
                      label: 'Admin',
                      count: 2,
                      icon: Icons.badge_outlined,
                    ),
                    HsFilterOption(
                      value: 'Empleado',
                      label: 'Empleado',
                      count: 6,
                      icon: Icons.badge_outlined,
                    ),
                  ],
                ),
              ],
              selected: {'role': _role},
              onApply: (f) => setState(() => _role = f['role'] ?? ''),
            ),
            const SizedBox(height: 10),
            Text('consulta:$_query|rol:$_role'),
          ],
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: _Host()));
  await tester.pump();
}

void main() {
  testWidgets('búsqueda y filtro aplican en el módulo', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pump();
    expect(find.text('consulta:ana|rol:'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Filtros'), findsOneWidget);
    expect(find.text('ROL'), findsOneWidget);

    await tester.tap(find.text('Admin'));
    await tester.pump();
    await tester.tap(find.textContaining('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.text('consulta:ana|rol:Admin'), findsOneWidget);
    // El filtro activo se ve como píldora removible, sin abrir el modal.
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Limpiar filtros'), findsNothing);

    await tester.tap(find.byTooltip('Quitar filtro'));
    await tester.pumpAndSettle();
    expect(find.text('consulta:ana|rol:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en celular el módulo de filtros ocupa la pantalla', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();

    // El diálogo llega de borde a borde y muestra todas sus acciones.
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.width, closeTo(390, 1));
    expect(find.text('Limpiar'), findsOneWidget);
    expect(find.text('Ver todo'), findsOneWidget);
    expect(find.text('Empleado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
