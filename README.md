# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| **Paquetes** | ✅ Catálogo estilo flyer (tier, categoría, servicios, imagen); el formulario tiene pestañas Datos / Servicios, vista previa en vivo y permite AGREGAR servicios sin salir |
| **Servicios** | ✅ Catálogo con icono, nombre, descripción y liga del Drive (opcional) |
| **Clientes** | ✅ CRUD + tarjeta interactiva que abre el modal de administración de paquetes |
| **Finanzas** | ✅ Tabla con el dinero de cada paquete y de cada tipo de movimiento (se expande), gráfica por mes y registro de movimientos |
| **Usuarios / Roles** | ✅ CRUD + permisos por módulo |
| **Agendas** | ✅ Calendario de eventos con franja de próximos eventos y **alta de eventos** eligiendo cliente → su paquete → servicio |
| **Dashboard** | ✅ Tablero sin scroll (escritorio) con el resumen, las finanzas y los eventos |
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

### Carpeta compartida (pestaña Drive)

Cada paquete del cliente puede **compartir UNA carpeta del Drive**:

- El botón abre un **selector que navega el Drive de verdad** (sin mover la
  carpeta que estás viendo en el módulo Archivos) y la carpeta elegida queda
  guardada en el paquete (`purchased_packages.drive_path`).
- El **Drive del cliente** muestra SOLO las carpetas compartidas de sus
  paquetes: si a un paquete le compartes `ReynaCoot` y a otro `Cliente`, en
  su Drive aparecen esas dos carpetas y **nada más**.
- Sin carpeta asignada, el cliente ve su Drive vacío con el aviso "Aún no se
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

Requiere la migración `Hardstreet-DB/2026-10-15_movimientos_generales_y_carpeta_compartida.sql`
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

## Personalizar paquete

El diálogo de alta/edición de paquete es visual e intuitivo:

- **Vista previa en vivo** (arriba) del flyer: refleja nombre, subtítulo,
  precio, tier, categoría y número de servicios al escribir.
- Pestaña **Datos**: nombre, subtítulo, descripción, precio, tier, categoría
  e imagen para la web.
- Pestaña **Servicios**: buscador, contador y **Agregar** — crea un servicio
  nuevo del catálogo sin salir del diálogo (queda seleccionado solo).

## Módulo Servicios

Catálogo que se incluye en los paquetes (`/api/admin/services`, permiso
sobre el módulo "Servicios"):

- Icono seleccionable, nombre, descripción y **URL base** opcional: la
  liga de la carpeta del Drive afiliada al servicio.
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
- **Colores y toques**: el widget se pinta con la MISMA paleta del tema de la
  app (tarjeta = `cardColor`, textos = `onSurface`/`onSurfaceVariant`, acento =
  `primary`), en claro y en oscuro; una prueba compara la paleta nativa
  (`colors.xml` y `event_widget.cpp`) con `AppTheme` para que no se separen.
  **Tocar un evento abre el detalle de ESA agenda** en la app, y el botón **+
  (Agregar agenda), que solo aparece si el rol tiene "Crear" en Agendas,
  abre el alta de evento** (el widget no navega: le pasa el toque a la app).

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
