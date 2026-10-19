import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/hs_toast.dart';

/// Monta la app con la capa de avisos, como en producción (main.dart).
Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) =>
        HsToastHost(child: child ?? const SizedBox.shrink()),
    home: const Scaffold(body: SizedBox.expand()),
  ));
  await tester.pump();
}

/// Deja entrar la animación del aviso.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('el éxito sale con el azul de la app', (tester) async {
    await _pumpHost(tester);
    HsToast.success('Cliente creado exitosamente');
    await _settle(tester);

    expect(find.text('Cliente creado exitosamente'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
    expect(icon.color, const Color(0xFF2F6BFF),
        reason: 'azul de la app = operación exitosa');
  });

  testWidgets('el error sale ROJO y muestra el detalle del backend',
      (tester) async {
    await _pumpHost(tester);
    HsToast.error('Hubo un error',
        details: 'A tu rol le falta el permiso "delete" en el módulo "clientes"');
    await _settle(tester);

    expect(find.text('Hubo un error'), findsOneWidget);
    expect(
      find.text('A tu rol le falta el permiso "delete" en el módulo "clientes"'),
      findsOneWidget,
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_rounded));
    expect(icon.color, const Color(0xFFEF4444),
        reason: 'rojo = operación fallida');
  });

  testWidgets('el aviso se va solo al terminar su tiempo', (tester) async {
    await _pumpHost(tester);
    HsToast.success('Servicio eliminado exitosamente');
    await _settle(tester);
    expect(find.text('Servicio eliminado exitosamente'), findsOneWidget);

    await tester.pump(HsToast.duration + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Servicio eliminado exitosamente'), findsNothing);
  });

  testWidgets('se pueden apilar varios avisos', (tester) async {
    await _pumpHost(tester);
    HsToast.success('Rol creado exitosamente');
    HsToast.error('No se puede eliminar: hay usuarios con este rol');
    await _settle(tester);

    expect(find.text('Rol creado exitosamente'), findsOneWidget);
    expect(
        find.text('No se puede eliminar: hay usuarios con este rol'),
        findsOneWidget);
  });

  testWidgets('sin la capa de avisos nada se rompe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    HsToast.success('Nadie escucha');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
