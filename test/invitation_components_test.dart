import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/invitation_components/component_catalog.dart';
import 'package:hardstreet_admin/invitation_components/templates/invitation_templates.dart';
import 'package:hardstreet_admin/invitation_html.dart';
import 'package:hardstreet_admin/invitation_model.dart';
import 'package:hardstreet_admin/widgets/invitation_html_editor.dart';

// ==================================================================
// PLANTILLAS COMPUESTAS — catálogo, recetas y HTML por componente
// ==================================================================

void main() {
  group('catálogo por componente', () {
    test('cada carpeta aporta diseños con claves únicas', () {
      expect(kInvitationComponents, isNotEmpty);
      final keys = kInvitationComponents.map((c) => c.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys, containsAll(['cover', 'families', 'details', 'itinerary']));

      for (final component in kInvitationComponents) {
        expect(
          component.designs.length,
          greaterThanOrEqualTo(2),
          reason: '${component.key} debe ofrecer variantes',
        );
        final designs = component.designs.map((d) => d.key).toList();
        expect(designs.toSet().length, designs.length);
        expect(component.design(component.fallback), isNotNull);
        expect(component.design('diseno-que-no-existe'), isNull);
      }
    });

    test('los componentes de flujo son los únicos que se reordenan', () {
      expect(
        kFlowInvitationComponents.toSet(),
        kInvitationComponents.where((c) => c.flow).map((c) => c.key).toSet(),
      );
      expect(
        kFixedInvitationComponents.toSet(),
        kInvitationComponents.where((c) => !c.flow).map((c) => c.key).toSet(),
      );
      expect(kFlowInvitationComponents, contains('itinerary'));
      expect(kFixedInvitationComponents, contains('cover'));
    });
  });

  group('recetas de plantilla', () {
    test('combinan una base, una portada y diseños válidos', () {
      expect(kInvitationTemplateRecipes, hasLength(2));
      final keys = kInvitationTemplateRecipes.map((t) => t.key).toList();
      expect(keys.toSet().length, keys.length);

      for (final recipe in kInvitationTemplateRecipes) {
        expect(invitationTemplate(recipe.baseTemplate), isNotNull);
        expect(kInvitationCoverStyles, contains(recipe.coverStyle));
        for (final entry in recipe.components.entries) {
          final component = invitationComponentForKey(entry.key);
          expect(component, isNotNull, reason: '${recipe.name}: ${entry.key}');
          expect(
            component!.design(entry.value),
            isNotNull,
            reason: '${recipe.name}: ${entry.key}=${entry.value}',
          );
        }
      }
    });

    test('Marfil & Oro usa carta y papel marfil', () {
      final inv = Invitation.samplePreset('marfil-clasica');

      expect(inv.template, 'boda-marfil');
      expect(inv.preset, 'marfil-clasica');
      expect(inv.templateRecipe.name, 'Marfil & Oro');
      expect(inv.coverStyleKey, 'carta');
      expect(inv.coverBackdropKey, 'marfil');
      expect(inv.componentDesign('cover'), 'carta');
    });

    test('una receta desconocida cae en la combinación rosa', () {
      final inv = Invitation.samplePreset('no-existe');
      expect(inv.preset, 'rosa-clasica');
      expect(inv.template, 'sobre-xv');
      expect(inv.coverStyleKey, 'rosa');
      expect(inv.componentDesign('families'), 'tarjetas');
    });
  });

  group('serialización', () {
    test('el preset y los diseños sobreviven a JSON', () {
      final original = Invitation.samplePreset('marfil-clasica');
      final inv = original.copyWith(
        componentDesigns: {
          ...original.componentDesigns,
          'families': 'minimal',
          'footer': 'minimal',
        },
      );
      final design = (inv.toJson()['design'] as Map).cast<String, dynamic>();
      expect(design['preset'], 'marfil-clasica');
      expect((design['components'] as Map)['families'], 'minimal');
      expect((design['components'] as Map)['cover'], 'carta');

      final back = Invitation.fromJson(inv.toJson());
      expect(back.preset, 'marfil-clasica');
      expect(back.template, 'boda-marfil');
      expect(back.componentDesign('families'), 'minimal');
      expect(back.componentDesign('footer'), 'minimal');
      expect(back.coverStyleKey, 'carta');
    });

    test('un diseño inválido se descarta y usa el de la receta', () {
      final inv = Invitation.samplePreset('marfil-clasica')
          .copyWith(componentDesigns: {'families': 'inventado'});
      final back = Invitation.fromJson(inv.toJson());

      expect(back.componentDesigns, isEmpty);
      expect(back.componentDesign('families'), isNot('inventado'));
    });

    test('una invitación vieja usa los diseños de fábrica de su base', () {
      final legacy = Invitation.fromJson({
        'id': 9,
        'template': 'boda-marfil',
        'title': 'Boda de Ana y Luis',
        'design': {
          'sections': ['cover', 'families', 'details', 'itinerary'],
        },
      });

      expect(legacy.preset, isEmpty);
      expect(legacy.templateRecipe.name, 'Marfil & Oro');
      expect(legacy.coverStyleKey, 'carta');
      expect(legacy.componentDesign('families'), 'tarjetas');
      expect(legacy.componentDesign('details'), 'tarjetas');
      expect(legacy.componentDesign('itinerary'), 'linea');
      expect(legacy.componentDesign('cover'), 'carta');
    });
  });

  group('HTML por componente', () {
    test('envuelve cada bloque y añade solo el CSS de los diseños', () {
      final inv = Invitation.samplePreset('marfil-clasica').copyWith(
        photos: const ['https://drive.test/files/foto.jpg'],
        quote: 'La vida es más bonita compartida.',
        hashtag: '#AnaYLuis2026',
      );
      final html = buildInvitationHtml(inv);

      expect(html, contains('hs-cover'));
      expect(html, contains('data-flow="true"'));
      expect(html, isNot(contains('data-design="diseno-que-no-existe"')));
    });

    test('el editor inyecta acciones sin reescribir el diseño', () {
      final html = buildInvitationHtml(
        Invitation.samplePreset('marfil-clasica'),
      );
      final editor = injectInvitationEditor(html, openAtStart: true);

      // El documento real sigue intacto y además trae la capa de edición.
      expect(editor, contains('hs-cover'));
      expect(editor, contains('__HS_INV'));
      expect(editor, contains('hs-editbar'));
      expect(editor, contains("callHandler('hsEditor'"));
      expect(editor, contains('OPEN_AT_START = true'));
      expect(editor, contains('hs-editor-open'));
      expect(editor, contains('hs-edit-drop-end'));
      expect(editor, isNot(contains('__HS_OPEN_AT_START__')));

      final cover = injectInvitationEditor(html, openAtStart: false);
      expect(cover, contains('OPEN_AT_START = false'));
      expect(cover, contains('hs-editbar'));
      expect(cover, isNot(contains('__HS_OPEN_AT_START__')));
    });

    test('el HTML público no lleva la capa de edición', () {
      final html = buildInvitationHtml(Invitation.samplePreset('rosa-clasica'));
      expect(html, isNot(contains('hs-editbar')));
      expect(html, isNot(contains("callHandler('hsEditor'")));
      expect(html, isNot(contains('hs-editor-open')));
    });

    test('cambiar un diseño cambia el wrapper y su CSS', () {
      final base = Invitation.samplePreset('rosa-clasica').copyWith(
        families: const [
          InvitationFamily(title: 'Padres', names: ['Ana', 'Luis']),
        ],
      );
      final changed = base.copyWith(
        componentDesigns: {...base.componentDesigns, 'families': 'minimal'},
      );
      final html = buildInvitationHtml(changed);

      expect(html, contains('data-component="families" data-design="minimal"'));
      expect(
        html,
        contains('.hs-comp[data-component="families"][data-design="minimal"]'),
      );
      expect(html, isNot(contains('data-design="columnas"')));
    });
  });
}
