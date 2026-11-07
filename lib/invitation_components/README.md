# Componentes de invitación

Cada carpeta es un **objeto** de la invitación y contiene:

- su definición en el catálogo (`InvitationComponent`);
- sus diseños intercambiables (`InvitationComponentDesign`);
- el CSS que hace visible cada diseño en el HTML público.

Las plantillas viven en `templates/invitation_templates.dart` y no
duplican HTML: son combinaciones de un documento base, una portada y los
diseños de cada componente.

## Carpetas

| Carpeta | Objeto |
| --- | --- |
| `cover/` | Portada |
| `countdown/` | Cuenta regresiva |
| `quote/` | Frase |
| `photos/` | Fotos |
| `families/` | Familias |
| `details/` | Detalles / información |
| `hashtag/` | Hashtag |
| `itinerary/` | Itinerario |
| `rsvp/` | Confirmación |
| `footer/` | Pie |
| `music/` | Música |

`component_catalog.dart` reúne el catálogo y `components_css.dart` compone
los estilos de los diseños elegidos. Para añadir un diseño nuevo:

1. agrégalo a la lista `designs` de la carpeta del componente;
2. añade su regla en la función `*ComponentCss`;
3. añade una receta en `templates/` si debe formar parte de una plantilla.
