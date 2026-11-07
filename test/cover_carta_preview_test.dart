import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/invitation_model.dart';
import 'package:hardstreet_admin/widgets/invitation_preview.dart';

void main() {
  testWidgets('la portada Carta se abre como sobre', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvitationPreview(
            invitation: Invitation.sample('sobre-xv')
                .copyWith(coverStyle: 'carta'),
            allowCover: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Portada'));
    await tester.pump();

    expect(find.text('ABRIR CARTA'), findsNothing);
    expect(find.text('Toca el sobre para abrir'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Sin botón: toda la carta (el sobre) sigue siendo la zona de apertura.
    await tester.tap(find.byKey(const ValueKey('carta-envelope')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Toca el sobre para abrir'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
