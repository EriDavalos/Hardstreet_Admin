# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| **Paquetes** | ✅ DOS NIVELES en el mismo módulo: abre en la **galería de categorías** (portadas con su foto, cuántos paquetes y desde qué precio, más la de "Todo el catálogo" y el botón **Nueva categoría**) y al abrir una se ven SUS paquetes, editables, sin salir ni abrir un modal. Ya dentro, el catálogo estilo flyer (tier, categoría, servicios, imagen) con cards o filas; el formulario tiene pestañas Datos / Servicios, vista previa en vivo y permite AGREGAR servicios sin salir |
| **Servicios** | ✅ Catálogo con icono, nombre, descripción y liga del Drive (opcional) |
| **Clientes** | ✅ CRUD + tarjeta interactiva que abre el modal de administración de paquetes |
| **Finanzas** | ✅ Tabla con el dinero de cada paquete y de cada tipo de movimiento (se expande), gráfica por mes y registro de movimientos |
| **Usuarios / Roles** | ✅ CRUD + permisos por módulo |
| **Agendas** | ✅ Calendario de eventos con franja de próximos eventos y **alta de eventos** eligiendo cliente → su paquete → servicio |
| **Dashboard** | ✅ Tablero sin scroll (escritorio) con el resumen, las finanzas y los eventos |
| **Mi paquete** | ✅ Módulo del CLIENTE (antes se llamaba "Dashboard Cliente"): su paquete, el checklist de servicios, sus carpetas compartidas y, **por servicio**, la carpeta del Drive, la liga y la **selección de fotos** que él mismo marca. Es un módulo como los demás: si el rol no tiene "Ver" en `my_package` / "Mi paquete", NO aparece en el menú |
| Conexión, Configuraciones, Reportes | 🚧 Próximamente, pero ya son **módulos con permiso**: solo ofrecen "Ver" y el admin decide qué rol los ve desde Roles. Requiere la migración `Hardstreet-DB/2026-10-18_modulos_conexion_config_reportes.sql`; hasta aplicarla se comportan como antes (visibles) |

## Modal de paquete (Clientes)

Al abrir un cliente se administran sus paquetes en un solo modal:

- **Primero las tarjetas** de sus paquetes ("targets"); al tocar una se
  entra al detalle con animación (la flecha del encabezado regresa).
- **Izquierda — la ficha del paquete**: el flyer del catálogo con el look
  de su tier (Premium = oro sobre negro, Gold = ámbar, Basic = acero),
  más dinero (abonado/saldo/pagado), avance y el botón Finalizar.
- **Derecha — la administración**: pestañas de Servicios (con la liga base
  del Drive de cada servicio, copiable y editable), Calendario (las TARJETAS
  de los eventos agendados del paquete: crear, editar y eliminar, con los
  próximos primero), Movimientos y **Drive** (la carpeta compartida).

El **directorio de clientes** también es interactivo: toda la tarjeta (nombre,
correo, teléfono y el número de paquetes) abre el administrador de paquetes al
tocarla, sin quitar los botones de siempre (Paquetes / Editar / Eliminar). En
pantallas angostas esas acciones se guardan en el menú **⋮** de la tarjeta.

En ventanas angostas (menos de 1020 px de ancho, p. ej. un teléfono) la ficha
queda arriba y las pestañas abajo; la ficha, el precio y el pie del modal se
reacomodan en vez de recortar contenido.

### Carpetas compartidas (pestaña Drive)

Cada paquete del cliente puede **compartir VARIAS carpetas del Drive** (antes
solo una):

- El botón abre un **selector que navega el Drive de verdad** (sin mover la
  carpeta que estás viendo en el módulo Archivos); cada carpeta elegida queda
  en una tarjeta propia, con su botón para **dejar de compartirla** (las demás
  siguen igual).
- Se guardan en `purchased_packages_drive` (una fila por carpeta); la columna
  vieja `purchased_packages.drive_path` se mantiene sincronizada con la
  primera, por compatibilidad.
- El **Drive del cliente** muestra SOLO las carpetas compartidas de sus
  paquetes: si a un paquete le compartes `ReynaCoot` y a otro `Cliente`, en
  su Drive aparecen esas carpetas y **nada más**.
- **Sin duplicados**: no deja compartir una carpeta que esté dentro de otra ya
  compartida (o que la contenga), ni en el mismo paquete ni en otro del mismo
  cliente — el cliente vería el mismo contenido dos veces. El selector muestra
  esas carpetas **bloqueadas, con el motivo**.
- Sin carpetas asignadas, el cliente ve su Drive vacío con el aviso "Aún no se
  te comparte ninguna carpeta".
- El equipo del estudio (rol Admin, u otro rol con permiso de Archivos) sigue
  viendo el Drive completo: el alcance solo aplica al cliente.

### Movimientos y ahorro

La pestaña **Movimientos** concentra el dinero del paquete:

- Arriba, las tarjetas de control: **Disponible**, **Ahorro**, **Abono
  externo**, **Invertido** y **Gastado**. Se reacomodan solas (2, 3 o 4 por
  fila) según el ancho.
- **Abonar** (tabla de abonos: mantiene el total pagado) y **Registrar
  movimiento**: inversión, gasto, **ahorro** o abono externo.
- El **ahorro** se captura como cantidad o como **porcentaje del disponible**,
  que además deja constancia del % aplicado en su concepto.
- **Disponible = abonado − gastado − ahorro + abono externo**: el ahorro se
  APARTA del disponible y el abono externo (dinero que entra por fuera) se le
  SUMA, igual que en el módulo Finanzas.
- **Editar un registro**: cada movimiento y cada abono tiene su botón de
  edición (mientras el paquete NO esté finalizado). Se puede cambiar el tipo,
  el monto y el concepto; un paquete terminado es solo de consulta y el
  backend rechaza la edición.
- Los movimientos propios no tocan el total abonado ni el saldo del paquete
  (eso lo hacen los abonos).

## Dashboard

En ventanas anchas (≥ 1000 px) el Dashboard es un **tablero que NO scrollea**:
la página llena la pantalla y reparte todo en tres columnas de tarjetas
compactas (resumen + finanzas, eventos y clientes, distribución + accesos
rápidos). Cada columna scrollea por dentro solo si su contenido no cabe. En
pantallas angostas se mantiene el acomodo en una columna con scroll.

## Módulo Finanzas

Todo lo monetario del negocio en una sola vista (`/api/admin/finance`,
permiso sobre el módulo "Finanzas"), pensada para NO bajar con el scroll:

- Arriba, la tira de **totales** en cuadros horizontales. El primero es
  **Ganado**, que es el **Disponible** de los datos (abonado − gastado −
  ahorro + abono externo): el dinero que de verdad queda.
- Debajo, **una TABLA** ("Dinero por paquete y movimiento") con las columnas
  Concepto · Monto · Ahorro · Salidas:
  - **Fila por PAQUETE**: al expandirla muestra su desglose (cobrado, por
    cobrar, ganado/disponible, ahorro, gastos, inversión y abono externo),
    sus movimientos y sus acciones (**Abonar al ahorro** / **Agregar
    movimiento**).
  - **Fila por TIPO de movimiento** (Abonos, Gastos, Inversiones, Ahorro,
    Abonos externos): al expandirla se desglosa registro por registro, con su
    concepto, paquete/cliente, fecha y monto.
  - **Fila GENERAL (sin paquete)**: el dinero del NEGOCIO que no pertenece a
    ningún paquete, con su desglose y sus movimientos.
- **Agregar movimiento** y **Abonar al ahorro** son DOS acciones separadas en
  la cabecera (la segunda lleva el verde del ahorro).
- **Agregar movimiento**: registra gasto, inversión, ahorro o abono externo
  sin salir de Finanzas. El paquete es **opcional** — viene en "General (todo
  el negocio)", así que ya no hay que elegir paquete; solo se elige si quieres
  atribuir el movimiento a un paquete del cliente. El ahorro admite porcentaje
  del disponible (del paquete elegido o, en general, del negocio).
- **Gráfica de los últimos 6 meses**: lo que ENTRÓ contra lo que SALIÓ, en la
  columna lateral.
- En escritorio la tabla y la gráfica van lado a lado (solo la tabla scrollea
  por dentro); en pantallas angostas todo vive en una sola zona con scroll.

El **Dashboard** añade esa misma información en versión compacta (cuadros +
gráfica) y un acceso rápido al módulo. Todo es *best effort*: si el usuario no
tiene permiso o no hay conexión, el resto del dashboard sigue viéndose.

Requiere las tablas `site_config` y `user_drive_shares` (`Hardstreet-DB/hardstreet.sql`)
(movimientos sin paquete + `drive_path`) y la de
`Hardstreet-DB/2026-10-14_modulo_finanzas.sql`, que
registra el módulo y copia los permisos de "Clientes" a los roles que ya los
tienen. El rol **Admin pasa siempre**, así que el módulo funciona aunque la
migración aún no se aplique (y el menú no lo esconde: si el backend todavía no
conoce el módulo, se muestra igual).

## Calendario (módulo Agendas)

- Vista de semana (rejilla de horas) o de mes, con el panel de filtros por
  servicio y la franja de próximos eventos.
- **Nuevo evento**: en escritorio es el botón de la cabecera y en móvil el
  ícono **+** de la barra del calendario (para no robarle altura al
  calendario). El alta pide, en orden, el **cliente**, el **paquete comprado
  de ese cliente** y el **servicio del paquete** (opcional), más fecha, hora
  y nota. Sin cliente no se pueden elegir paquetes: el formulario avisa si el
  cliente no tiene paquetes comprados.

## Opciones de compartir por SERVICIO (Mi paquete)

Cada servicio de un paquete comprado puede compartir con el cliente TRES
cosas, todas opcionales y **por servicio del paquete** (no globales del
catálogo). Se configuran en la pestaña Servicios del paquete, acción
**Compartir**, y son también las OPCIONES que le salen al cliente:

- **Carpeta del Drive**: se elige con el mismo selector que navega el Drive de
  verdad, **dentro** de lo que el cliente ya tiene compartido.
- **Liga**: la URL que el cliente verá (p. ej. su álbum en línea).
- **Selección de elementos/fotos**: la hace **el propio CLIENTE** desde "Mi
  paquete": el botón **Elegir fotos** abre el navegador de SUS carpetas
  compartidas —el MISMO selector del Drive, con miniaturas, vista previa y
  descarga— y marca lo que quiere (se ve el contador de elegidas). Se guarda
  la **LISTA de rutas** — nada se mueve ni se copia de carpeta — y las rutas
  tienen que caer dentro de lo que se le comparte (el backend lo revalida).

Los dos interruptores (**Elegir fotos** y **Abrir carpeta**) deciden qué le
sale al cliente en cada servicio: antes *Elegir fotos* aparecía en TODOS y no
se podía apagar. *Elegir fotos* nace **apagado** (se enciende donde hace
falta); *Abrir carpeta* nace encendido y solo sale si el servicio tiene una
carpeta compartida.

En "Mi paquete" cada servicio muestra sus acciones en **UNA fila deslizable**
(en el teléfono no se apilan): *Abrir carpeta*, *Ver liga* y *Mis fotos (N)*,
cada una solo si su opción está encendida. El estudio ve lo compartido,
cuántos elementos eligió el cliente y qué opciones tiene encendidas cada
servicio en la pestaña Servicios del paquete.

Requiere las tablas `purchased_packages_services_shares` (con las columnas
`pick_photos` y `show_folder`: migración
`Hardstreet-DB/2026-10-16_opciones_por_servicio.sql`) y
`purchased_packages_services_items` (dump `Hardstreet-DB/hardstreet.sql`); sin
ellas todo cae a "sin opciones" en vez de fallar.

## Móvil: el encabezado no se come la pantalla

En el teléfono el encabezado de cada módulo conserva POCO alto para que la
información tenga la pantalla:

- Los **botones de acción** (Nuevo, Agregar movimiento, Abonar al ahorro,
  Refrescar…) van en **UNA sola fila que se desliza de lado**; antes se
  apilaban y empujaban el contenido hacia abajo.
- Las **píldoras de información** ("Ganado", "Ahorro", "Salidas", conteos…)
  también van en una fila deslizable en vez de envolverse en varios renglones.
- El **desglose de cada renglón** (tabla de Finanzas, ficha del paquete) usa
  filas y píldoras deslizables, y su contenido scrollea por dentro de su zona
  en vez de estirar la página.

## Personalizar paquete

El diálogo de alta/edición de paquete es visual e intuitivo:

- **Vista previa en vivo** (arriba) del flyer: refleja nombre, subtítulo,
  precio, tier, categoría y número de servicios al escribir.
- Pestaña **Datos**: nombre, subtítulo, descripción, precio, tier, categoría
  e imagen para la web. La imagen se puede escribir a mano (`images/…`) o
  elegir del **Drive** con **Elegir una foto del Drive** (el mismo selector de
  fotos de la app: rejilla con miniatura, vista previa y descarga); se guarda
  su URL pública para que la web la abra sin sesión, y se ve su miniatura en
  el propio formulario.
- Pestaña **Servicios**: buscador, contador y **Agregar** — crea un servicio
  nuevo del catálogo sin salir del diálogo (queda seleccionado solo).

## Módulo Paquetes: cards o filas

El catálogo se presenta de dos formas, con el conmutador que está junto al
buscador (el mismo gesto que en el Drive):

- **Cards** (por defecto): el flyer de la web tal cual se ve en "Nuestros
  Paquetes" — línea dorada, badge de tier, categoría con icono, servicios y
  precio con CTA "Personalizar".
- **Filas**: el mismo diseño en una línea por paquete (barra de acento del tier,
  icono de categoría, nombre, subtítulo, servicios incluidos y precio), para
  recorrer y comparar todo el catálogo sin perder la identidad de la marca. En
  el celular las acciones van al menú "⋮".

### La FOTO del paquete en el panel

La tarjeta del panel pinta la **misma foto que ve la web** (`url_image`), no un
hueco: en banda arriba o de fondo, según lo que pida el diseño. Se pide al
servidor del drive en tamaño de tarjeta (`/thumb/<ruta>?w=640`) y **con el
token de la sesión en la URL**, porque `Image.network` no puede mandar
cabeceras y sin él el servidor responde 403 (ésa era la razón de que las fotos
"no cargaran"). Un paquete sin foto lo dice ("Sin foto · la web usa una del
sitio"), que es lo que hace la página en ese caso.Tamaño MÁXIMO de una card: **450 × 675**. En pantallas anchas no se estiran sin
fin (formato de flyer, 2:3); si el contenido no cabe a lo alto, se recorta el
bloque del medio y el pie del precio sigue a la vista.

Con la foto **de fondo**, los textos de la card van SIEMPRE en claro (aunque el
panel esté en modo claro) y sobre ellos va un **velo negro**: encima de una foto
el texto oscuro del tema claro se perdía, que es justo cuando "no se leían las
letras".

La web es **pública** y no tiene sesión, así que sus fotos (la imagen de cada
paquete y las de la portada) no las podría abrir. El panel las **publica** en el
servidor del drive: al abrir Paquetes manda las imágenes de los
paquetes y al guardar Sitio web las de la portada
(`POST /api/public-photos`, un alcance por módulo, que reemplaza sólo esa
lista). Sólo esas rutas se sirven sin token; el resto del drive sigue igual de
cerrado (ver `hardstreet-drive/README.md`).

## Módulo Paquetes: la galería de categorías

El módulo abre en la **galería** y de ahí se baja a los paquetes, todo en la
misma pantalla (`lib/widgets/category_gallery.dart`):

- **Portadas**: cada categoría con la foto que la representa, cuántos paquetes
  tiene y desde qué precio salen. Una categoría sin paquetes se ve igual,
  diciendo "Sin paquetes todavía"; si ningún paquete tiene foto, la portada usa
  el emoji de la categoría en vez de un recuadro vacío. Al pasar el mouse la
  portada **sube un poco** (el mismo gesto que las cards de paquetes), no se
  agranda.
- La primera portada es **Todo el catálogo**: los paquetes de todas las
  categorías, para quien quiere verlo todo de una vez.
- **Nueva categoría** (acción del encabezado, requiere *create* en Paquetes)
  crea la categoría de verdad → `POST /api/admin/categories`. No se pide icono:
  el panel y la web lo sacan del NOMBRE (Boda 💍, XV Años 👑…).
- Al abrir una portada se ven **sus paquetes con `WebPackageCard`** (la misma
  tarjeta del catálogo, editables) y una flecha para **volver a la galería**. El
  buscador, los chips de categoría y los botones de diseño y "Nuevo paquete"
  viven en ese nivel; al crear un paquete desde una categoría, el formulario ya
  viene con ESA categoría elegida.
- Las categorías que sólo aparecen en un paquete (una que todavía no esté
  registrada) también salen, en vez de desaparecer.

## Diseñar las cards (Diseñador de paquetes)

El botón **Diseñar cards** (en Paquetes, requiere permiso de *update*) abre el
diseñador: a la izquierda los controles y a la derecha la **vista previa en
vivo** de la tarjeta y de la fila, tal como quedarán en la web.

- Pestaña **Global**: dorados de la marca, columnas del catálogo (1–4),
  separación, redondeo, borde, relleno, línea superior, elevación y sombra al
  pasar el mouse, tipografía del nombre (serif/MAYÚSCULAS), qué se muestra
  (categoría, subtítulo, cuántos servicios, lista, precio, botón), cuántos
  servicios se listan y los textos ("Desde"/"Cotizar"…).
- **Foto del paquete**: sin foto, en **banda arriba** (con su alto) o **de
  fondo**. De fondo, la foto se ve a TODO color y encima va un **velo NEGRO**
  que oscurece más abajo y a la izquierda —donde van el nombre, los servicios y
  el precio— para que el texto resalte; el control *Oscurecido de la foto
  (degradado)* manda cuánto tapa (0 = foto limpia). Es el mismo velo en el
  panel, en el diseñador y en la web (`site.js` → `hsPhotoFade` con negro). La
  foto es la del paquete (pestaña *Datos* del formulario, y puede elegirse del
  Drive).
- Pestañas por **tier** (Premium / Gold / Basic): acento, acento claro, fondo,
  badge relleno o delineado y fuerza del borde, con **paletas listas** de un
  toque y la opción de copiar la paleta a los otros tiers.
- **Volver al diseño original** restaura el look de fábrica del sitio.

Lo que se guarda aquí lo aplica la web **en vivo** (sin volver a publicar):
`PUT /api/admin/site` → `site_config.design`, y el sitio lo lee al cargar con
`GET /api/site` y lo traduce a CSS (`Hardstreet/gallery/assets/site.js`). Los
dos lados comparten los MISMOS defaults: `test/site_design_test.dart` compara
el diseño del panel con el de la web y falla si alguien los separa.

Los **colores de la marca** que se elijan aquí también tiñen el módulo: los
chips de categoría y la minivista previa del formulario de paquete los usan.

### La card del panel y la de la web son LA MISMA

La tarjeta de la página se pinta con las medidas de la del panel: **un solo
relleno** (el del diseño, en `.pkg-flyer-inner`; las secciones ya no suman el
suyo), el **badge del tier en flujo arriba a la izquierda** (no flotando sobre
la foto), categoría → nombre → subtítulo → **descripción** → línea completa
fina → cuántos servicios → lista sin separadores entre filas → pie con el
precio y el botón. El nombre va en blanco en TODOS los tiers (el degradado
dorado del nombre era una de las diferencias) y el pie lleva el tinte del
acento de su tier.

Lo que NO se toca por paridad: la **animación de entrada** del catálogo
(`reveal` + `hsPkgIn`, la que elige el diseñador) y la elevación al pasar el
mouse, que son de la web; y el botón del pie, que en el panel es **Editar**
(esto es un formulario) y en la web el CTA del diseño (*Cotizar*).
`Hardstreet/tests/site-design.test.mjs` comprueba el marcado y el CSS de esas
piezas.

## Módulo Sitio web (portada) — solo Windows

**Sitio web** edita la PORTADA que ven los clientes desde el panel, sin tocar
HTML: textos, imágenes y qué secciones se muestran (y en qué orden). Lo que se
guarda lo aplica la web en vivo (`GET /api/site` → `gallery/assets/site.js`),
así que no hay que volver a publicar el sitio.

- **Textos**: cada campo muestra arriba el valor de fábrica (lo que dice hoy el
  sitio) y al lado un botón para volver a él. El titular admite dos líneas con
  `|` (la segunda va resaltada) para no perder el diseño al reescribirlo.
- **Imágenes**: ruta local del sitio o una URL; los fondos del hero y del
  divisor también se cambian desde aquí.
- **Secciones**: subir/bajar cada bloque y apagarlo cuando no se quiere mostrar.
- **Base de datos**: mientras la base esté vacía, la web se pinta con lo que
  trae su HTML y el panel guarda SÓLO los campos cambiados. Con la base vacía el
  módulo lo avisa y ofrece **"Guardar lo actual en la base"**: sube TODO el
  contenido actual (textos, imágenes, opciones, orden y visibilidad). A partir
  de ahí la base manda y cada guardado vuelve a mandar el documento completo,
  así que la web lee su contenido de la base y nunca se pierde lo que no se
  tocó en esa sesión.
- Requiere el permiso del módulo "Sitio web" (`Ver` / `Editar`) y la tabla
  `site_config` que registra el módulo (`Hardstreet-DB/hardstreet.sql`).
- Alternativa al botón, desde el servidor:
  `node Hardstreet-Backend/tool/seed-site-content.mjs` lee lo que la web tiene
  ahora (HTML + CSS + defaults de `site.js`) y lo escribe en
  `site_config.landing` (`--dry-run` para verlo sin tocar la base).

Por ahora el módulo se ofrece **sólo en Windows** (en Android y en la web del
panel ni aparece en el menú): es un editor pensado para trabajar con el sitio a
la vista en la computadora.

Pruebas: `test/site_page_test.dart` comprueba que los ganchos del HTML y el
catálogo del panel coincidan, que los valores de fábrica sean los del sitio y
que editar/guardar haga lo que dice (incluido que un documento COMPLETO —el que
sube "Guardar lo actual en la base"— pinta la portada igual que los defaults:
`Hardstreet/tests/site-sections.test.mjs`).

## Módulo Servicios

Catálogo que se incluye en los paquetes (`/api/admin/services`, permiso
sobre el módulo "Servicios"):

- Icono seleccionable, nombre, descripción y **URL base** opcional: la
  liga de la carpeta del Drive afiliada al servicio.
- El icono se guarda como `material:videocam` y la web dibuja **el mismo
  icono** con la tipografía Material Symbols (el panel y la página no
  mantienen dos listas distintas). Los iconos heredados (`icon/x.svg`) siguen
  funcionando. `Hardstreet/tests/site-design.test.mjs` lo comprueba:

  ```bash
  cd Hardstreet && node --test tests/site-design.test.mjs
  ```
- La liga se administra aquí o directo desde la pestaña Servicios del
  paquete comprado del cliente.
- Requiere la migración `Hardstreet-DB/2026-10-13_services_url.sql`.

## Módulo Archivos (Drive)

- Carpetas anidadas (`ReynaCoot/SesionPrevia/Fiesta/...`), navegación por breadcrumbs.
- **Alcance del CLIENTE**: si el usuario es un cliente, el módulo muestra solo
  las carpetas que se le comparten en sus paquetes (ver "Carpeta compartida");
  el equipo del estudio ve el Drive completo.
- Sube varias imágenes a la vez desde el selector nativo del sistema.
- Vista de cuadrícula con miniaturas o vista de lista (nombre, fecha, tamaño).
- Buscar dentro de la carpeta, renombrar, eliminar, crear carpetas.
- **Visor de imágenes a PANTALLA COMPLETA** (sin bordes curvos), con la
  información del archivo y su posición ("3 de 12") encima de la foto,
  botones de zoom, **Descargar** sin salir del visor, navegación con las
  flechas del teclado (← →) y cierre con Esc.
- **Descargas**: en escritorio se elige el destino con el diálogo del sistema;
  en **Android** no existe ese diálogo (`file_selector` no implementa
  `getSavePath()`, de ahí el `UnimplementedError`), así que el archivo (o el
  ZIP de una selección/carpeta) se deja en la carpeta **Descargas** del
  dispositivo con `MediaStore` y la app avisa dónde quedó.
- Si un refresco de fondo falla (servidor ocupado mientras subes fotos), el
  listado se queda a la vista y solo aparece el aviso “Sin conexión ·
  reintentar”: el directorio no se vacía ni cambia por un fallo pasajero.

Las imágenes se guardan en carpetas reales del sistema dentro de
`Documentos/HardStreetDrive` (multiplataforma: Windows, macOS, Linux). Puedes
abrir esa carpeta con el explorador de archivos y verás la misma estructura.

## Widget de "próximos eventos"

Los eventos agendados también se pueden tener fuera de la app. La app —que es
la que tiene la sesión y los datos— calcula los próximos eventos y los EMPUJA
al widget nativo por el canal `hardstreet/events_widget` (el widget nunca
consulta la API por su cuenta).

- **Android** — widget de la pantalla de inicio (`EventWidgetProvider`):
  encabezado, contador, botón **Agregar agenda** y TODA la agenda que viene
  agrupada por día (lista desplazable dentro del widget). Se alimenta desde el
  servicio de avisos (refresco cada 5 min) y desde el módulo Agendas. En la
  franja "Próximos eventos" de Agendas hay un botón para **colocarlo en el
  inicio** (Android 8+ pide la confirmación del lanzador).
- **Windows** — panel flotante del escritorio (esquina inferior derecha,
  siempre visible, con esquinas redondeadas): se puede arrastrar y su botón
  **+** hace lo mismo que el de Android. Se enciende y apaga con el mismo botón
  de la franja (la preferencia se guarda con `shared_preferences`).
- **Colores y toques**: los TEXTOS y la marca siguen siendo los del tema de la
  app (`onSurface`/`onSurfaceVariant` y `primary`), pero el FONDO va **más
  oscuro** a propósito para que el widget se distinga del escritorio/fondo de
  pantalla, y **sin borde dibujado** (el trazo se recortaba en las esquinas
  redondeadas y se veía sucio). El **panel de Windows** pinta además cada
  evento como una **tarjeta con el color de SU servicio** (la misma paleta del
  calendario) en un tinte tenue, con barra de acento a la izquierda:
  disimulado, pero se distinguen de un vistazo; su encabezado y su botón **+**
  van más grandes. Una prueba compara la paleta nativa (`colors.xml` y
  `event_widget.cpp`) con `AppTheme` para que no se separen.
  **Tocar un evento abre el módulo de Agendas en ESE evento** (el calendario se
  mueve a su día y abre su detalle), y el botón **+ (Agregar agenda), que solo
  aparece si el rol tiene "Crear" en Agendas, abre el alta de evento** (el
  widget no navega: le pasa el toque a la app).
- **Se mantiene al día SOLO** (sin la app abierta): el rótulo del día ("HOY ·
  16 OCT") y el descarte de lo que ya pasó NO se copian de lo último que empujó
  la app, se **recalculan con la hora del dispositivo** cada vez que el widget
  se repinta. Además se repinta por su cuenta: en Android con una alarma propia
  cada 15 min más el `updatePeriodMillis` del lanzador, y en Windows con un
  temporizador del panel. Antes, al pasar la medianoche con la app cerrada, un
  evento del día anterior seguía diciendo "HOY".

## Archivos compartidos (entre usuarios)

Módulo **independiente** del Drive de los paquetes: aquí las personas comparten
una carpeta entre ellas (una carpeta de su computadora o una de su Drive), y se
navega **dentro del mismo módulo** —nunca salta al módulo Archivos— con el mismo
diseño que el Drive y en **solo lectura** (se ve, se amplía y se descarga; no se
escribe en la carpeta de otra persona).

El contenido de la carpeta se presenta como en **Archivos**: grupos de
**CARPETAS** e **IMÁGENES** con las mismas tarjetas (misma altura, mismo
redondeo, misma separación) y las fotos en el mismo tamaño de miniatura (480 px,
que el servidor reduce una vez y guarda en caché). Al abrir la carpeta se dejan
**pedidas** las primeras miniaturas, así la cuadrícula aparece con las fotos en
vez de ir llenándose a cuentagotas.

El **visor** de una foto compartida pide el **preview redimensionado**
(`/api/local/thumb?w=1600`), nunca el original: el original puede pesar 10 MB y,
si la carpeta está en la computadora de su dueño, tiene que viajar por su app.
El módulo trata estas carpetas como un drive **por red** (no como una carpeta
del disco), que es lo que hace que sus miniaturas se pidan de verdad.

Lo importante para que funcione: **una carpeta de TU computadora la sirve TU
computadora**. La app abre una conexión SALIENTE al servidor del drive (long
polling) y contesta lo que los demás usuarios piden, leyendo su propio disco:
es como compartir una carpeta de red, pero sin abrir puertos, sin IP fija y sin
tocar el router. La contraparte es que **la carpeta se ve mientras la app esté
abierta en esa computadora**; si se cierra, la app avisa ("Esa carpeta está en
la computadora de quien la comparte: se abre cuando su aplicación esté
abierta") en vez de mostrar un error raro. El agente arranca y se detiene solo:
se enciende al compartir la primera carpeta del equipo y se apaga al dejar de
compartir la última.

Compartir exige **permiso de compartir** en el rol y, en el celular, el módulo
es de solo lectura (compartir requiere elegir una carpeta del equipo, y eso se
hace en la computadora): la app lo dice en vez de ofrecer un botón que no puede
funcionar.

Arriba del módulo hay un **switch del servicio de compartir**: encendido, la
app sirve las carpetas de ESTA computadora mientras el panel esté abierto
(aunque ahora mismo no queden compartidos a la vista) y lo recuerda para la
próxima vez; apagado, los demás solo ven "Apagada ahora". El switch muestra el
estado REAL (también se apaga solo si la sesión deja de servir) y, en pantalla
angosta, va como botón de imagen junto a "Actualizar". Si el rol no puede
compartir, la tarjeta lo dice ahí mismo (antes el botón simplemente no
aparecía).

Cada carpeta compartida lleva su **estado a la vista** (se pregunta al servidor
con `/api/local/status`): *Disponible* (está en el servidor), *En línea* (está en
la computadora del dueño y su app está abierta), *Apagada ahora* (su app no está
abierta), *Servidor sin base de datos* (al servidor del drive le falta
`DRIVE_DB`), *Ya no está compartida* (el compartido se dio de baja) o *No
disponible*, con el motivo que manda el servidor. Ese último caso también cubre
un servidor todavía sin actualizar, que contesta 404 con "La carpeta compartida
no existe o ya no está activa": el módulo lo traduce a "Ya no está compartida"
y explica qué hacer, en vez de mostrar el texto crudo.

## Arranque

La app abre con una animación de marca (fondo del tema activo, la marca que
entra con rebote, el nombre y una barra fina) y después un fundido cruzado
hacia el login o el panel: la MISMA en Windows y en Android. En Android oscuro,
además, la ventana nativa ya usa el fondo del arranque (`#0C111C`) para que no
haya un destello blanco antes del primer frame.

## Actualizaciones internas (Android)

El actualizador descarga el APK y lo entrega al instalador del sistema por
`FileProvider`. El APK se descarga en el caché NORMAL de la app
(`getTemporaryDirectory()`), que es el que declara `res/xml/file_paths.xml`:
antes se usaba `Directory.systemTemp`, que en Android apunta a `code_cache` y
provocaba *"Failed to find configured root that contains …"*. Además
`MainActivity` copia el archivo al caché si llegara a quedar fuera de las
rutas declaradas, así que la instalación ya no puede fallar por eso.

## Ejecutar

```bash
cd Hardstreet_Admin
flutter pub get
flutter run -d windows   # o macos / linux / chrome
```

## Tests

```bash
flutter test
```
