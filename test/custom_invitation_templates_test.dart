import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/invitation_components/templates/custom_invitation_templates.dart';
import 'package:hardstreet_admin/invitation_components/templates/invitation_templates.dart';
import 'package:hardstreet_admin/invitation_model.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InvitationTemplateStore.resetForTest();
  });

  test('guarda, aplica, actualiza y elimina una plantilla', () async {
    final base = templateRecipeForInvitation(
      preset: 'marfil-clasica',
      template: 'boda-marfil',
    );
    final custom = base.copyWith(
      key: InvitationTemplateStore.newKey('Mi Jardín'),
      name: 'Mi Jardín',
      occasion: 'Boda',
      hint: 'Una copia propia de Marfil & Oro.',
      custom: true,
    );
    await InvitationTemplateStore.save(custom);

    expect(InvitationTemplateStore.recipes, hasLength(1));
    expect(InvitationTemplateStore.recipes.single.name, 'Mi Jardín');

    final sample = Invitation.samplePreset(custom.key);
    expect(sample.preset, custom.key);
    expect(sample.templateRecipe.name, 'Mi Jardín');
    expect(sample.componentDesign('cover'), 'carta');

    // La plantilla sobrevive a cerrar y volver a abrir la app.
    InvitationTemplateStore.resetForTest();
    await InvitationTemplateStore.load();
    expect(InvitationTemplateStore.recipes, hasLength(1));

    final updated = custom.copyWith(
      name: 'Mi Jardín actualizado',
      components: {...custom.components, 'details': 'lista'},
    );
    await InvitationTemplateStore.save(updated);
    expect(InvitationTemplateStore.recipes, hasLength(1));
    expect(
      InvitationTemplateStore.find(custom.key)?.name,
      'Mi Jardín actualizado',
    );
    expect(
      InvitationTemplateStore.find(custom.key)?.components['details'],
      'lista',
    );

    await InvitationTemplateStore.delete(custom.key);
    expect(InvitationTemplateStore.recipes, isEmpty);
    expect(InvitationTemplateStore.find(custom.key), isNull);
  });

  test('sanea el JSON de una plantilla guardada', () async {
    SharedPreferences.setMockInitialValues({
      InvitationTemplateStore.storageKey: jsonEncode([
        {
          'key': 'prueba',
          'name': 'Plantilla rota',
          'occasion': 'XV',
          'baseTemplate': 'no-existe',
          'coverStyle': 'no-existe',
          'accent': 'azul',
          'bgColor': 'FFF',
          'effect': 'fuego',
          'font': 'otra',
          'components': {
            'details': 'inventado',
            'families': 'columnas',
            'cover': 'noche',
          },
        },
      ]),
    });
    InvitationTemplateStore.resetForTest();
    await InvitationTemplateStore.load();

    final recipe = InvitationTemplateStore.recipes.single;
    expect(recipe.key, 'custom-prueba');
    expect(recipe.name, 'Plantilla rota');
    expect(recipe.baseTemplate, 'sobre-xv');
    expect(recipe.coverStyle, 'rosa');
    expect(recipe.accent, isEmpty);
    expect(recipe.bgColor, isEmpty);
    expect(recipe.effect, isEmpty);
    expect(recipe.font, isEmpty);
    expect(recipe.components['families'], 'columnas');
    expect(recipe.components.containsKey('details'), isFalse);
    expect(recipe.components.containsKey('cover'), isFalse);

    expect(Invitation.samplePreset(recipe.key).preset, recipe.key);
  });

  test('una plantilla personalizada no puede pisar una de fábrica', () {
    registerInvitationTemplateRecipes([
      kInvitationTemplateRecipes.first.copyWith(custom: true),
    ]);

    expect(
      allInvitationTemplateRecipes,
      hasLength(kInvitationTemplateRecipes.length),
    );
    expect(invitationTemplateRecipeForKey('rosa-clasica')?.name, 'Rosa Pastel');
  });
}
