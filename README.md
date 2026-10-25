# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| **Paquetes** | ✅ DOS NIVELES en el mismo módulo: abre en la **galería de categorías** (portadas con su foto, cuántos paquetes y desde qué precio, más la de "Todo el catálogo" y el botón **Nueva categoría**) y al abrir una se ven SUS paquetes, editables, sin salir ni abrir un modal. Ya dentro, el catálogo estilo flyer (tier, categoría, servicios, imagen) con cards o filas; el formulario tiene pestañas Datos / Servicios, vista previa en vivo y permite AGREGAR servicios sin salir |
| **Servicios** | ✅ Catálogo con icono, nombre, descripción y liga del Drive (opcional) |
| **Clientes** | ✅ CRUD + tarjeta interactiva que abre el modal de administración de paquetes |
| **Finanzas** | ✅ Vista con pestañas: **Resumen** (DINERO ACTUAL con su tabla de conceptos y gráfica), **Por paquete** y **Pagos** a colaboradores/empleados |
| **Usuarios / Roles** | ✅ CRUD + permisos por módulo |
| **Agendas** | ✅ Calendario de eventos con franja de próximos eventos, **alta de eventos** eligiendo cliente → su paquete (opcional) → servicio y **lugar en el mapa** (búsqueda o punto marcado). En el mes, los **días ocupados** se marcan en rojo |
| **Dashboard** | ✅ Tablero sin scroll (escritorio) con el resumen, las finanzas y los eventos |
| **Mi paquete** | ✅ Módulo del CLIENTE (antes se llamaba "Dashboard Cliente"): su paquete, el checklist de servicios, sus carpetas compartidas y, **por servicio**, la carpeta del Drive, la liga y la **selección de fotos** que él mismo marca. Es un módulo como los demás: si el rol no tiene "Ver" en `my_package` / "Mi paquete", NO aparece en el menú |
| **Notificaciones** | ✅ Módulo nuevo: **qué roles reciben cada aviso** (agenda próxima, fotos disponibles, envío de fotos, servicio/paquete terminado, impresión lista) y **envío de avisos manuales** a los roles elegidos. Cada aviso lleva su MÓDULO: al tocarlo en la campanita, el panel abre esa pantalla. Requiere la migración `Hardstreet-DB/2026-10-20_notificaciones_ubicaciones.sql` |
| **Conexión** | ✅ **SOLO el Superadministrador** (usuario 1, rol Superadmin): los servidores del Drive en un **diagrama interactivo** (hub central + cards con estado, versión, prioridad, bibliotecas, espacio, ping y dependencias), con terminal del servicio, reinicio y subida de archivos al proyecto. Ver *Conexión: servidores del Drive* |
| Configuraciones, Reportes | 🚧 Próximamente, pero ya son **módulos con permiso**: solo ofrecen "Ver" y el admin decide qué rol los ve desde Roles. Requiere la migración `Hardstreet-DB/2026-10-18_modulos_conexion_config_reportes.sql`; hasta aplicarla se comportan como antes (visibles) |

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

### Asignar un paquete del catálogo

El botón **Asignar del catálogo** abre una vista con los paquetes en
tarjetas pequeños de dos columnas (nombre, subtítulo y precio). Se elige el
paquete y, al pulsar **Asignar paquete**, aparece la pregunta
**¿Quieres mantener el precio?** con el precio del catálogo a la vista:

- **Aceptar** — asigna con el precio del catálogo, sin tocar nada más.
- **Cambiar** — abre el campo del precio especial, precargado con el del
  catálogo; el resumen **PRECIO A COBRAR** avisa cuánto sube o baja. Ese
  precio aplica SOLO a esa asignación: el catálogo no se modifica.
- **Precio 0** — el paquete queda **gratuito** (se guarda en cero y el resumen
  lo rotula «Gratuito»).

Si el precio especial coincide con el del catálogo se manda sin precio (se
usa el del catálogo). El backend (`/api/admin/client-packages`) acepta
`price` desde antes; el panel solo empezó a usarlo con esta vista.

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

Todo lo monetario del negocio en una vista moderna con **tres pestañas**
(`/api/admin/finance`, permiso sobre el módulo "Finanzas"):

- **Resumen**:
  - Arriba, el **DINERO ACTUAL**: abonado + abono externo − gastos −
    inversión − ahorro − **pagos**. Los pagos a colaboradores/empleados SÍ
    salen del dinero (antes se trataban como un "gasto invisible").
  - La tabla **Movimiento del dinero**: Abonado, Abono externo, Gastos,
    Inversión, Ahorro, Pagos y Por cobrar. Cada concepto lleva su monto y una
    barra proporcional animada, para ver de un vistazo qué pesa más.
  - La **gráfica de los últimos 6 meses** y los **movimientos recientes**.
- **Por paquete**: la misma información separada por paquete (abonado,
  gastos, inversión, ahorro, por cobrar, abono externo, pagos y dinero
  actual), con búsqueda, desglose y acciones al tocar cada paquete. Los
  **paquetes gratis SIN movimiento se omiten**; si un paquete de precio 0
  tiene un abono, gasto, inversión, ahorro, abono externo o un pago, sí
  aparece.
- **Pagos**: todo lo pagado a **cada colaborador y empleado**: total
  histórico, número de pagos, paquetes y último pago. Al tocar a una persona
  se desglosa cada pago (paquete, cliente, concepto y fecha).
- **Registrar movimiento**: gasto, inversión, ahorro (cantidad o porcentaje
  del dinero actual) o abono externo. El paquete es **opcional** — viene en
  "General (todo el negocio)". Los abonos se capturan en el paquete y los
  pagos se reparten desde el administrador del paquete (Movimientos →
  Repartir pago).
- Ya **no hay un separador de "Ahorro apartado"**: el ahorro aparece como un
  concepto de la tabla.

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
  calendario). El alta pide el **cliente** y la **fecha/hora** (más nota y
  lugar) y, **opcionalmente**, el **paquete comprado de ese cliente** y el
  **servicio del paquete**: con solo el cliente se agenda una fecha suelta de
  su calendario, sin depender de un paquete. El formulario avisa cuando el
  cliente no tiene paquetes, pero deja crear el evento igual. Las agendas sin
  paquete se guardan con `schedules.id_user` y `id_purchased_package = NULL`:
  requieren la migración `Hardstreet-DB/2026-10-22_agendas_por_cliente.sql`
  (sin ella el resto del calendario sigue funcionando y el alta sin paquete
  avisa que falta aplicarla). El `POST` de `/api/admin/agendas` acepta
  `userId` junto a (o en lugar de) `purchasedPackageId`.
- **Editar una agenda**: el detalle de un evento (rejilla de la semana, mes,
  franja de próximos eventos o el widget) lleva un **lápiz** que abre el
  formulario de edición: fecha/hora (con los atajos Hoy / Mañana / En 7 días),
  **servicio**, **ubicaciones** y **nota**. El cliente y el paquete NO se
  cambian ahí (el `PUT` del servidor tampoco los expone). El lápiz solo aparece
  con permiso de **actualizar** agendas; sin él el detalle es de solo lectura.
- **Varias ubicaciones por evento** (opcional): el alta y la edición de una
  agenda permiten sumar **una o VARIAS ubicaciones** con **Agregar otra
  ubicación**; se **numeran solas** (1, 2, 3…) en el orden en que se capturan
  y al quitar una las demás se renumeran. Se guardan en la tabla
  `schedule_locations` (una fila por lugar, con su `position`), así que el
  detalle de la agenda y las tarjetas del paquete las muestran numeradas. La
  PRIMERA se copia también en `schedules.location`/`lat`/`lng` para el
  calendario, el widget y los clientes. Requiere la migración
  `Hardstreet-DB/2026-10-20_agenda_ubicaciones.sql` (idempotente y con traspaso
  de los lugares ya guardados); sin ella la agenda sigue guardando su lugar
  único como antes. La API acepta `locations: [{ location, lat, lng }]` en
  `POST`/`PUT` de `/api/admin/agendas`.
- **Lugar del evento** (opcional): el alta y la edición de una agenda abren un
  **mapa** (flutter_map + OpenStreetMap, igual en celular, computadora y web)
  donde se BUSCA el lugar por nombre o se TOCA el punto; el nombre se puede
  corregir a mano. La búsqueda la resuelve el backend
  (`/api/admin/geocode` → Nominatim), no el dispositivo, así funciona en todas
  las plataformas. El lugar se ve en el detalle de la agenda (con mini mapa y
  botón **Abrir mapa**), en las tarjetas de próximos eventos, en la rejilla de
  la semana y en las tarjetas de agenda del paquete del cliente. Requiere la
  migración `Hardstreet-DB/2026-10-19_ubicacion_agendas.sql` (`location`,
  `lat`, `lng` en `schedules`); sin ella las agendas se guardan igual, sin
  lugar.
- **Ubicaciones guardadas**: el selector de lugar trae "MIS UBICACIONES" con
  los lugares ya usados (se eligen con un toque y se quitan con el chip) y el
  botón **Guardar ubicación** para agregar el lugar actual a la lista. Se
  administran en `/api/admin/locations` (tabla `locations`, por empresa, con
  los permisos del módulo Agendas): así se pueden tener tantas ubicaciones
  como sedes/salones/haciendas haga falta.
- **Qué ve un CLIENTE en el calendario**: sus propios eventos completos
  (cliente, paquete, servicio, nota y lugar) y los de los DEMÁS como huecos
  **Ocupado** — solo la fecha y la hora, sin nombres ni detalles —, así sabe
  cuándo el estudio está tomado sin enterarse de los eventos de otros.
  Al tocar un hueco **Ocupado** el cliente NO abre ningún detalle: solo le sale
  el aviso "Horario ocupado" (antes el modal se abría para no decir nada más
  que "Ocupado"). Si el día mezcla eventos suyos y ocupados, el detalle se abre
  solo con los suyos. El **estudio** sí abre esos huecos: para él una agenda
  ajena no está enmascarada.
  El recorte lo hace el **servidor** (`lib/agenda-visibility.ts` del backend):
  el panel, el widget de próximos eventos y cualquier llamada a la API reciben
  ya las agendas ajenas como `{ busy: true }`. Se considera cliente al rol
  **Cliente** y a cualquier usuario con paquetes comprados; el Admin y el
  personal que puede crear/editar/borrar agendas ven todo. Los **avisos**
  (campanita) de un cliente también se limitan a SUS eventos.
  Esos huecos **Ocupado** son los ÚNICOS días que se pintan en **rojo** (con
  candado en el badge): el rojo es la señal del cliente. Para el estudio un
  día con eventos lleva el **círculo del día resaltado** con el color de su
  servicio (y el badge con su icono), así se distingue de un día libre sin
  llenar el calendario de rojo.

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

**El envío se destaca como SIGUIENTE PASO.** Cuando el cliente ya marcó sus
fotos y todavía no las ha enviado, arriba de las acciones del servicio sale un
bloque propio —borde azul, rótulo **SIGUIENTE PASO** y una flecha— que dice
«Envía tus fotos a impresión», cuántas fotos lleva elegidas y que su fotógrafo
las recibe al enviarlas; el botón **Enviar a impresión** va ahí, lleno y a todo
lo ancho (antes era un botón de contorno más, y el cliente se quedaba con la
selección hecha creyendo que ya estaba). Al enviarlas el bloque desaparece y
quedan solo *Ver fotos (N)* y el aviso «Enviadas». Sin fotos elegidas no hay
bloque: no hay nada que mandar.

### Banner de la portada (Mostrar banner cliente)

En **Personalizar servicio** (módulo Servicios) hay un interruptor nuevo,
**Mostrar banner cliente**, que solo se puede encender si el servicio tiene
**Abrir carpeta** activo (sin carpeta no hay fotos que mostrar; al apagar la
carpeta el banner se apaga solo).

Con la opción encendida, cuando el servicio está **cumplido** (Terminado o
Entregado) la portada de "Mi paquete" deja de enseñar solo la foto del paquete
y pasa a mostrar hasta **10 fotos al azar** de las carpetas compartidas de
todos los servicios cumplidos que tengan la opción, cambiando cada 6 s con un
**fundido**. Cada foto llena TODO el banner (se recorta un poco HACIA ARRIBA,
así las verticales y las horizontales ocupan lo mismo sin cortarle la cara a la
persona en el banner ancho de la computadora) y el fundido entra ENCIMA de la
anterior, que sigue visible: entre foto y foto no hay huecos ni destellos.
Mientras las fotos se están bajando, debajo sigue la foto del paquete: el banner
nunca queda vacío. Y el fundido **espera a que la foto ya esté descargada**
(`HeroPhotoBanner.preload`): si la red va lenta se sigue viendo la anterior y el
cambio entra con su transición, en vez de fundir a un hueco y enseñar la foto de
golpe al llegar (la primera foto también entra fundida).

**El fondo de TODA la vista** (`PhotoBackdrop`) es la foto que se está viendo,
estirada y **desenfocada**, con un velo del color del panel encima para que el
héroe del módulo, las tarjetas y los textos sigan leyéndose. Va SIEMPRE detrás
del contenido (no encima ni alrededor de la tarjeta: el halo de color anterior
ensuciaba la portada) y cambia con el mismo fundido que el banner, o sea cada
6 s. Si la foto falla o no hay fotos, el fondo desaparece y la vista queda
como siempre. Sin fotos (o sin servicios cumplidos) se queda la foto del
paquete. Requiere la migración `Hardstreet-DB/2026-10-22_banner_cliente.sql`
(`services.show_banner`); sin ella el interruptor queda apagado y todo sigue
como antes.

El **estudio** también puede marcar la selección (botón **Elegir/Cambiar
fotos** y **Avisar al cliente** en el bloque de fotos del servicio), por si el
cliente no puede hacerlo. Si la selección **ya se envió a impresión**, esos
botones se cambian por **Reabrir envío** —la selección queda bloqueada hasta
reabrirla— y **Ver fotos** sigue disponible para consultarla.

Requiere las tablas `purchased_packages_services_shares` (con las columnas
`pick_photos` y `show_folder`: migración
`Hardstreet-DB/2026-10-16_opciones_por_servicio.sql`) y
`purchased_packages_services_items` (dump `Hardstreet-DB/hardstreet.sql`); sin
ellas todo cae a "sin opciones" en vez de fallar.

### Portada y línea de tiempo de servicios

La portada del paquete ya no acumula cifras. Se fueron la píldora de «N de M
servicios», «Carpeta lista» y la barra de pago: distraían de lo que el cliente
necesita ver de un golpe. El pie de la tarjeta es una sola franja fina, separada
por una línea, con dos datos discretos (nada de tarjetas grandes: «Elige tus
fotos» y «Liquidado» pesaban más que la propia foto):

- **Qué toca hacer ahora** — icono pequeño y una línea: «Elige tus fotos»
  cuando algún servicio con «Elegir fotos» todavía no tiene selección; «Envía
  tus fotos» si ya eligió y falta mandarlas; «En proceso» mientras el estudio
  trabaja; «Todo entregado» al terminar. Debajo, cuántos servicios están en ese
  estado.
- **El pago**, como el renglón de totales de un recibo (alineado a la derecha):
  «Liquidado» cuando ya no falta nada o **Faltan $X**, con el total y el
  porcentaje pagado como apoyo. Sin barra y sin caja.
- **Abrir mi carpeta**, si tiene una carpeta compartida.

La foto de la portada es la protagonista: el recorte es más alto, las esquinas
más suaves y el borde de arriba lleva un filo de luz. El pie queda fijo (no
cambia con las fotos del banner).

Los servicios se leen como una **línea de tiempo** vertical (riel con un nodo
por etapa) y en este orden:

1. **Elige tus fotos** — siempre primero, con fondo tenue y etiqueta «TE TOCA»:
   es lo único que depende del cliente. Dentro, arriba los que todavía no
   tienen selección y después los que solo esperan enviarla.
2. **En proceso** — primero los servicios que ya pueden **abrir su carpeta**.
3. **Completados** — primero los que pueden abrir carpeta y, después, los que
   ya tienen fotos elegidas.

Dentro de cada etapa manda el tipo de acción de la tarjeta: primero los
servicios cuyo **único botón es «Abrir carpeta»**, después los que además
tienen fotos (**«Ver fotos» / «Elegir fotos»**) y al final los que no ofrecen
ninguna de las dos.

Las tarjetas de las tres etapas comparten el MISMO fondo translúcido teñido con
el color del estado: antes solo las completadas dejaban ver la foto del fondo y
la lista se veía a parches.

## Notificaciones: quién recibe cada aviso

El módulo **Notificaciones** (`/api/admin/notifications`) tiene una tarjeta por
evento: **interruptor** para encenderlo/apagarlo y **Elegir roles** para decir
quién lo recibe. Sin configuración se usan los roles recomendados:

| Aviso | Roles por defecto | Abre |
|---|---|---|
| Avisar a fechas próximas a agenda | Cliente y Colaborador | Agendas |
| Avisar cuando se puedan seleccionar las fotos | Cliente | Mi paquete |
| Avisar el envío de fotos seleccionadas | Colaborador | Impresiones |
| Avisar cuando se termina un servicio | Cliente | Mi paquete |
| Avisar cuando se termina el paquete | Cliente | Mi paquete |
| Avisar cuando la impresión está lista | Cliente | Mi paquete |
| Avisos manuales del estudio | (se elige al enviar) | el módulo elegido |

Los avisos llegan a la **campanita** (`/api/reminders`) y, al tocarlos, abren su
módulo (`target`). Los avisos del **paquete** al cliente ("Ya puedes elegir tus
fotos", "Servicio terminado"…) son los mismos que el cliente ve en «Novedades»
dentro de Mi paquete: el endpoint los devuelve como `source: "package"` con
`target: my_package`, así que también aparecen en la campanita y, al tocarlos,
abren Mi paquete. Además suenan dentro de la app: una campanita
corta (`assets/sounds/aviso.wav`, reproducida con `audioplayers`) suena UNA vez
por aviso nuevo, igual que el toast nativo (`PackageNotificationsService`). El botón **Enviar aviso** escribe un aviso manual para los
roles marcados y elige a qué módulo lleva. El historial muestra lo ya enviado
con sus destinatarios. Migración:
`Hardstreet-DB/2026-10-20_notificaciones_ubicaciones.sql` (crea
`notification_rules`, `package_notifications`, `admin_notifications` con
`target`, `locations` y registra el módulo con sus permisos).

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
- El **paginado** del pie va en **UNA sola fila**: ‹ Página X de Y › a la
  izquierda y el selector de tamaño (solo el número) a la derecha. Antes tenía
  dos líneas —el resumen "1–30 de 240" y el "30 por página" encima— y se comía
  alto del teléfono. En el escritorio se mantiene la barra completa, con los
  números de página y el resumen.

## Personalizar paquete

El diálogo de alta/edición de paquete es visual e intuitivo:

- **En el CELULAR ocupa TODA la pantalla** (como el resto de modales del
  panel): antes conservaba un margen de 18 px y, con el texto grande, el pie
  con “Guardar cambios” se salía 72 px de la vista. La cabecera va solo con el
  título (el subtítulo se omite), los desplegables de **Tier** y **Categoría**
  van uno debajo del otro (lado a lado se salía su texto) y los botones del pie
  se acomodan en un `Wrap` (bajan de línea si no caben).

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

La barra de arriba (**Diseño de las cards**) se ve a la vista al abrir el
catálogo y abre el diseñador. En el **celular** el botón **Personalizar** baja a
su propia fila a todo lo ancho: apilado con el icono y el texto, la descripción
quedaba en una columna de ~37 px (una palabra por renglón) y los colores de los
tiers se salían 210 px de la tarjeta.

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
  crea la categoría de verdad → `POST /api/admin/categories`, y el **lápiz de
  cada portada** (requiere *update*) la **edita** → `PUT /api/admin/categories`.
  En los dos casos se pide el **nombre** y una **foto opcional**: un **enlace**
  o una foto **del Drive** (el mismo selector de toda la app; si el rol no
  puede ver el Drive, esa opción no se dibuja). La foto de la categoría manda
  sobre la del primer paquete; sin foto, la portada sigue usando la del
  paquete. No se pide icono: el panel y la web lo sacan del NOMBRE (Boda 💍,
  XV Años 👑…).
  Migración: `Hardstreet-DB/2026-10-16_categorias_imagen.sql`.
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

En el **celular** el diseñador ocupa toda la pantalla y va en dos pestañas
(Diseño / Vista previa), con la cabecera en una sola línea: antes, con el texto
grande, la cabecera se comía la pantalla y el botón de guardar quedaba 102 px
por debajo del borde.

- Pestaña **Global**: dorados de la marca, columnas del catálogo (1–4),
  separación, redondeo, borde, relleno, línea superior, elevación y sombra al
  pasar el mouse, tipografía del nombre (serif/MAYÚSCULAS), qué se muestra
  (categoría, subtítulo, cuántos servicios, lista, precio, botón), cuántos
  servicios se listan y los textos ("Desde"/"Cotizar"…).
- **Foto del paquete**: sin foto, en **banda arriba** (con su alto) o **de
  fondo**. De fondo, la foto se ve a TODO color y encima va un **velo** que
  oscurece más del lado donde está el texto (el nombre, los servicios y el
  precio) para que resalte.
  El degradado se **personaliza**: *fuerza* (0 = foto limpia), *color del velo*
  (muestras de un toque —el negro de fábrica— o un color propio) y *de dónde
  viene* (desde abajo o desde arriba), con una **vista previa** del velo sobre
  una foto de muestra justo debajo de los controles. Es el MISMO degradado en el
  panel, en el diseñador y en la web (`site.js` → `hsPhotoFade`).
  La foto es la del paquete (pestaña *Datos* del formulario, y puede elegirse
  del Drive). Un paquete **sin foto** se ve LIMPIO —sin banda, sin velo y sin
  una foto de relleno del sitio—: la tarjeta queda como la del panel.
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
relleno** (el del diseño; las secciones ya no suman el suyo), el **badge del
tier en flujo arriba a la izquierda** (no flotando sobre la foto), categoría →
nombre (22 px) → subtítulo → **descripción** → línea fina → cuántos servicios →
lista **con el mismo check** que el panel (antes la web dibujaba el icono de
cada servicio) → **pie a sangre completa** (12×20, con el tinte del acento de su
tier) con el precio a 22 px y el **botón en pastilla** (tinte del acento, sin
MAYÚSCULAS ni borde). El nombre va en blanco en TODOS los tiers y el ancho de
la tarjeta se topa en **450 px**, centrada, igual que en el panel.

Lo que NO se toca por paridad: la **animación de entrada** del catálogo
(`reveal` + `hsPkgIn`, la que elige el diseñador) y la elevación al pasar el
mouse, que son de la web; y el rótulo del botón del pie, que en el panel dice
**Editar** (esto es un formulario) y en la web el CTA del diseño (*Cotizar*).
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

### HTML propio de cada sección (vista previa REAL del sitio)

Cada tarjeta de sección trae **HTML de la sección**. Ahí se escribe el HTML
que la web pintará DENTRO de esa sección (conserva su `<section>`, su lugar y
su visibilidad); si se deja vacío, la sección se arma con sus campos y los
datos, como siempre. Lo que se escribe se guarda junto al resto del documento
(`landing.html`) al presionar **Guardar cambios**.

El editor tiene dos paneles: el HTML (con botones que insertan las etiquetas
que el sitio ya estiliza: título, etiqueta, párrafo, botón, imagen…) y la
**vista previa del sitio real**, no una maqueta de Flutter. El sitio
(`index.html`, `index.css`, `index.js`, `gallery/assets/…` e imágenes) viaja
EMPAQUETADO en la app (`assets/site/`) y se sirve en loopback
(`lib/site_preview_server_io.dart`); un `WebView` lo abre, oculta las demás
secciones y escribe dentro de la sección el HTML que se está editando. Así se
ven las tipografías, la rejilla, los botones y las fotos EXACTAMENTE como en la
web. **Cargar HTML actual** lee del sitio lo que la sección tiene ahora (con los
textos y fotos ya aplicados) para editar sobre eso en vez de reescribirlo.

Al cambiar la web hay que volver a copiarla dentro de la app antes de compilar
(las dos copias deben ser idénticas):

```bash
cd Hardstreet_Admin
node tool/sync_site_assets.mjs
```

El backend (`PUT /api/admin/site`) quita `<script>`, los manejadores en línea
(`onclick`, `onerror`…) y los enlaces `javascript:`, y topa cada sección a
100 KB. La web aplica el HTML al final de pintar el contenido (después de los
textos, las fotos y los datos), así que manda sobre todo lo demás
(`applySectionHtml` en `gallery/assets/site.js`), y vuelve a observar los
`.reveal` nuevos para que las animaciones de entrada funcionen.

Por ahora el módulo se ofrece **sólo en Windows** (en Android y en la web del
panel ni aparece en el menú): es un editor pensado para trabajar con el sitio a
la vista en la computadora.

Pruebas: `test/site_page_test.dart` comprueba que los ganchos del HTML y el
catálogo del panel coincidan, que los valores de fábrica sean los del sitio y
que editar/guardar haga lo que dice (incluido que un documento COMPLETO —el que
sube "Guardar lo actual en la base"— pinta la portada igual que los defaults:
`Hardstreet/tests/site-sections.test.mjs`). `test/site_html_test.dart` cubre el
HTML por sección de punta a punta (documento, editor y guardado) y
`test/site_preview_server_test.dart` pide el sitio empaquetado por HTTP
(contenido, tipos MIME, `..` y métodos).

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
- El listado va en **UNA sola columna**, con el mismo patrón que Clientes y
  Usuarios: una tarjeta con filas separadas por líneas y la fila entera como
  área de clic (sin rejilla de dos columnas ni saltos al pasar el ratón).
- La liga se administra aquí o directo desde la pestaña Servicios del
  paquete comprado del cliente.
- Requiere la migración `Hardstreet-DB/2026-10-13_services_url.sql`.

## Módulo Archivos (Drive)

Si el rol **no puede ver este módulo** (sin *read* en Archivos), las opciones de
**elegir una foto del Drive** desaparecen de todo el panel (formulario de
paquete, categorías, portadas del Sitio web y "Mis fotos" del cliente): quien no
ve el Drive tampoco elige archivos de ahí. La regla vive en
`HsAccess.instance.canUseDrive`.

- Carpetas anidadas (`ReynaCoot/SesionPrevia/Fiesta/...`), navegación por breadcrumbs.
- **Alcance del CLIENTE**: si el usuario es un cliente, el módulo muestra solo
  las carpetas que se le comparten en sus paquetes (ver "Carpeta compartida");
  el equipo del estudio ve el Drive completo.
- **Cambiar de cuenta o de empresa vuelve a la RAÍZ.** Cerrar sesión y entrar
  con otra cuenta (o el Superadministrador cambiando de empresa) reinicia el
  Drive: antes se quedaba en la carpeta de la sesión anterior, que para el
  usuario nuevo no existe, y el módulo abría ahí (vacío y sin permiso) en vez
  de en su propia raíz. Ver `DriveBase.resetSession()`.
- **La foto se ve nítida al abrirla**: el visor pide una vista de 2048px y el
  archivo ORIGINAL solo cuando ACERCAS (zoom > 1x). Antes bajaba el original
  entero en cuanto abría, así que la imagen cambiaba de "baja" a "alta"
  calidad un rato después.
- **Miniaturas**: se piden al servidor con caché en disco y límite de
  simultáneas (ver el README de `hardstreet-drive`); por eso aparecen de forma
  continua en vez de llegar todas de golpe.
- Sube varias imágenes a la vez desde el selector nativo del sistema.
- **También desde el navegador**: ahí el archivo elegido no tiene ruta en el
  disco (es un Blob), así que la subida va por BYTES — antes se intentaba
  abrirlo como archivo y salía `Unsupported operation: _Namespace`.
- **Fotos grandes**: a partir de 512 KB la subida va EN TROZOS de 512 KB y el
  servidor la arma al final. Un solo cuerpo mayor lo rechaza el proxy con
  `413 Request Entity Too Large` (una página HTML, no un error del servidor) y,
  si se cortaba, había que empezar la foto entera. El límite de fábrica del
  proxy (nginx: `client_max_body_size 1m`) es justo lo que manda aquí: **ninguna
  petición lleva más de lo que el proxy acepta**, así que una foto de 8 MB sube
  igual que una de 200 KB.
- **En el navegador el 413 del proxy no se puede ni leer**: nginx no pone las
  cabeceras CORS en su página de error, así que el navegador la bloquea y el
  panel recibe `Failed to fetch`. Por eso los trozos son chicos desde el primer
  intento, y un fallo de red al subir una foto (o un trozo) se trata como
  "rechazo de tamaño" y se rehace más chico en vez de gastar los tres
  reintentos. Era la razón de que la web no dejara subir fotos de más de ~1 MB
  mientras la app de escritorio sí (ella ve el 413 limpio).
- Vista de cuadrícula con miniaturas o vista de lista (nombre, fecha, tamaño).
- **En el TELÉFONO la tarjeta del módulo se va con el scroll** (título,
  buscador y contadores) para que la carpeta se quede con toda la pantalla. La
  **ruta** ("Mi Drive > Carpeta") tiene su propia barra: viaja justo debajo del
  encabezado y, en cuanto está a punto de salir de la vista, **se PEGA arriba**
  (sliver pegado, ver `_CrumbsHeaderDelegate`), siempre —en la raíz y dentro de
  cualquier carpeta—, así el camino nunca desaparece al bajar. El título
  tampoco lleva ya el botón de "Nueva carpeta": crear vive en el botón fijo.
- **La ruta se ve como siempre** (las migas sueltas sobre el fondo de la
  página, sin caja ni línea): el fondo de la barra solo existe para tapar lo
  que pasa por detrás al pegarse, y es **exactamente el de la página**
  (`scaffoldBackgroundColor`, no `surface`, que es otro tono y dejaba ver una
  franja con una línea de costura en el borde). Se pinta con un `ColoredBox`
  —sin borde, sombra ni elevación— y el `Material` de dentro es transparente:
  solo está para que el **resaltado del ratón** al pasar por una carpeta sí se
  pinte (antes la tinta quedaba debajo del fondo y no se veía nada). La barra
  mide **justo el alto de las migas** (34) y no lleva aire vertical: esos 4 px
  de arriba y 4 de abajo se veían como un hueco aparte.
- **En ventana ANGOSTA la barra superior ya no lleva línea debajo**
  (`AdminShell` omite ese `Divider` cuando `isCompact`): al pegarse la ruta, el
  divisor quedaba justo encima de las migas y se leía como una raya suelta
  sobre la barra. En escritorio ancho se conserva, porque ahí la ruta va dentro
  de la tarjeta del módulo.
- **La ruta se ACORTA cuando es larga**: no se listan todas las carpetas. Se ve
  la raíz, un **«…»** y las **dos últimas**: «Mi Drive > … > Carpeta2 >
  Carpeta3». Con tres migas o menos se ven completas. Antes la fila se
  desbordaba y había que deslizarla de lado para saber dónde estabas.
- **En la computadora, agarrar la barra de scroll NO selecciona**: el borde
  derecho del contenido (donde vive la barra) se ignora al iniciar la
  marquesina; antes, al arrastrar la barra caía en la zona vacía, encendía el
  modo «Seleccionar» y dibujaba el recuadro mientras te desplazabas.
- **Botón fijo de crear** (solo celular y solo con permiso de crear): un
  círculo con el degradado de la marca y el **+** blanco —sin texto, para no
  tapar las fotos— abajo a la derecha; abre la hoja con **Nueva carpeta** y
  **Subir archivos**. Se esconde mientras hay selección activa. Va **sin
  contorno** y el resaltado del toque es **redondo** (el `Material` recorta su
  tinta en círculo; antes se veía cuadrado).
- **Cuadrícula del teléfono**: DOS columnas con márgenes de 16 px y tarjetas
  casi cuadradas (proporción .96), así la miniatura manda y la tarjeta no se ve
  delgada; la portada de las carpetas se estira con la celda y su icono es más
  grande. En Archivos compartidos (también dos columnas) la portada se estira
  igual y la tarjeta es un poco más baja.
- **Recargar (solo computadora)**: un botón de icono al lado de «Nueva
  carpeta» vuelve a pedir el listado. En el celular no existe: ahí se recarga
  tirando hacia abajo, con el gesto de siempre.
- **Ya no hay franja «En línea · servidor · latencia»**: ocupaba una fila en
  todas las vistas para repetir lo que dicen la dirección configurada y el
  botón de recargar. El estado sigue donde importa: el aviso rojo cuando un
  refresco falla y la tarjeta completa (dirección, protocolo y qué revisar)
  cuando no hay nada que mostrar.
- Buscar dentro de la carpeta, renombrar, eliminar, crear carpetas.
- **Visor de imágenes a PANTALLA COMPLETA** (sin bordes curvos), con la
  información del archivo y su posición ("3 de 12") encima de la foto,
  botones de zoom, **Descargar** sin salir del visor, navegación con las
  flechas del teclado (← →) y cierre con Esc.
- **El Drive (y cada carpeta compartida) no es solo fotos**: la carpeta lista
  también vídeos, audio, PDF, texto y cualquier otro archivo, cada uno con su
  icono y su extensión. Al tocarlo se abre el visor que le toca: **vídeo/audio**
  se reproducen ahí mismo (se sirven por HTTP y se pueden adelantar) y con
  “Siguiente” se pasa al siguiente de la carpeta; los **texto** (txt, csv, json,
  log…) se leen dentro del panel; el **PDF** se ve en el navegador integrado (en
  Android no, allí se ofrece descargarlo); y lo que no tiene visor propio (zip,
  docx, psd…) lo dice y ofrece **Descargar** o **Abrir con el sistema** (el
  programa por defecto de la computadora). La subida desde el panel sigue
  aceptando solo imágenes: los demás archivos se ven si están en la carpeta.
- **Adelantar un vídeo NO lo reinicia**: los vídeos grandes se ven en *calidad
  ligera* (el servidor los reencoda al vuelo) y ese reencodado no admite saltos
  por bytes; mover la barra vuelve a pedir el vídeo **desde ese segundo**
  (`&t=`), así que sigue donde lo dejaste y el tiempo de la barra es el de
  verdad (no el del tramo). En un archivo normal el salto lo hace el navegador.
- **Si la calidad ligera no se puede ver, se prueba el ORIGINAL**: sin ffmpeg,
  con los reencodados ocupados o con un navegador que no acepta el MP4
  fragmentado, el reproductor pedía el vídeo reencodado, fallaba y se quedaba
  en "No se pudo reproducir" — justo lo que pasaba con los vídeos GRANDES.
  Ahora, ante el primer error, vuelve a pedir la URL **sin `play=low`** una vez
  y solo avisa si el original tampoco abre.
- **En el TELÉFONO el dedo SELECCIONA y el arrastre solo MUEVE lo ya
  seleccionado** (la app de Android/iOS y también la web abierta en el
  navegador del teléfono). Sostener una tarjeta que **no** estaba seleccionada
  y deslizar es el **barrido**: se marcan todos los elementos entre esa tarjeta
  y el dedo, y al llegar al borde la lista **se desplaza sola** para seguir
  marcando lo que queda más abajo (o más arriba). Si la tarjeta **ya** estaba
  seleccionada, el arrastre es el de siempre: levanta la selección para
  **moverla** (o copiarla) soltándola en una carpeta. En la **computadora** no
  cambia nada: arrastre inmediato con el mouse y marquesina con el recuadro.
- El gesto de presión larga ya no se "acepta" a los 350 ms si el dedo venía
  moviéndose: un scroll lento baja la lista en vez de levantar la tarjeta. En
  web tampoco hay animación de entrada al bajar (las filas aparecían
  deslizándose y parecía que las carpetas se movían solas).
- **El auto-scroll del barrido es fluido**: mientras seleccionas arrastrando y
  el dedo llega al borde, la lista se desplaza con un `Ticker` (un paso por
  fotograma) y la velocidad crece según cuánto entra el dedo en la zona del
  borde. Antes era un `Timer` de 50 ms que saltaba 16 px de golpe y se veía
  atorado, sobre todo al bajar.
- **Descargas**: en la **computadora** ya NO se pregunta el destino — el
  diálogo "Guardar como" siempre terminaba en Descargas—; el archivo (o el
  **ZIP** de una selección/carpeta) se guarda directo en la carpeta
  **Descargas** del sistema y se avisa dónde quedó (si ya existía, se guarda
  como `foto (1).ext` sin sobrescribir nada). En el **celular** —la app de
  Android/iOS y también la **web abierta en el navegador del teléfono**— NUNCA
  se arma un ZIP: se bajan **una por una** las fotos marcadas (una carpeta se
  expande a sus archivos), cada una a **Descargas** (`MediaStore` en Android).
  La descarga sigue en segundo plano si sales de la pantalla: vive en el panel
  de transferencias, con su progreso y su cancelar, y no bloquea la app.
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

## Avisos en tiempo real (aunque cierres la app)

Los avisos de EVENTOS (falta 1 semana / falta 1 día), los del PAQUETE («ya
puedes elegir tus fotos», «servicio terminado») y los de IMPRESIÓN salen como
notificación NATIVA del sistema, no solo en la campanita:

- **Con la app abierta** se consulta cada **15 s** los avisos y cada **20 s** los
del paquete (el widget de próximos eventos se actualiza una vez por minuto, que
es lo que cuesta pedir las agendas completas). Además se refresca al volver a
la app.
- **Computadora (Windows)**: cerrar la ventana ya NO cierra la app. Se queda en
la **bandeja del sistema** (el icono de Hardstreet junto al reloj) y sigue
consultando, así el toast aparece aunque el panel no esté abierto. Clic en el
icono = abrir; clic derecho = **Salir** (esa es la única forma de cerrarla de
verdad). Tocar una notificación trae la ventana al frente.
- **Teléfono**: con la app cerrada la consulta la hace un worker nativo
(`PackageNotificationsReceiver`) cada minuto con el token guardado —una alarma
`setAndAllowWhileIdle` que se re-agenda sola y sobrevive al reinicio— y publica
los avisos nuevos en los canales `reminders` y `paquete`. En Doze el sistema lo
espacia para no gastar batería; al despertar el teléfono vuelve a consultar.
Requiere el permiso de notificaciones (Android 13+).
- Los ids ya mostrados se comparten entre la app y el worker
(`app.notified.reminders` y `app.notified.package`), así un aviso no se repite
ni al reabrir ni entre los dos.
- **Límite conocido**: sin un servicio de push no hay entrega al segundo; en
**iOS** con la app cerrada no llega nada (no hay worker) y en la **web móvil**
las descargas dependen del navegador (si suspende la pestaña, se cortan).

## Archivos compartidos (entre usuarios)

Módulo **independiente** del Drive de los paquetes: aquí las personas comparten
una carpeta entre ellas (una carpeta de su computadora o una de su Drive), y se
navega **dentro del mismo módulo** —nunca salta al módulo Archivos— con el mismo
diseño que el Drive y en **solo lectura** (se ve, se amplía y se descarga; no se
escribe en la carpeta de otra persona).

El contenido de la carpeta se presenta como en **Archivos**: UNA sola
cuadrícula con las carpetas y las fotos juntas (sin rótulos de grupo, igual que
el Drive), con las mismas tarjetas (misma altura, mismo redondeo, misma
separación) y con la **vista de lista** cuando se conmuta a lista (icono o
miniatura, nombre, peso y el menú de acciones de cada elemento). Las fotos usan
el mismo tamaño de miniatura (480 px, que el servidor reduce una vez y guarda en
caché), los **vídeos también tienen la suya** (el servidor les saca el primer
fotograma con `ffmpeg-static`, que ahora es dependencia normal: si el servidor
viejo no lo tiene, `npm install` y reiniciar) y los **RAW (DNG, CR2, CR3, NEF,
ARW…)** muestran la vista previa JPEG que la cámara guarda dentro del archivo;
si un RAW no trae ninguna, se ve el icono del tipo, nunca un recuadro roto. Al
abrir la carpeta se dejan **pedidas** las primeras miniaturas, así la cuadrícula
aparece con las fotos en vez de ir llenándose a cuentagotas. El **visor de
vídeo** enseña esa miniatura como póster mientras carga, avisa «Cargando…» al
buffering y explica el error si el formato no se puede reproducir.

**Descargar y ver archivos grandes.** Un archivo de una carpeta compartida vive
en el servidor del drive (o en la computadora de su dueño), no en este disco: la
descarga pide los bytes por HTTP —directo al destino y por trozos, así un vídeo
de cientos de MB no se carga en memoria— y el ZIP de una selección se arma en la
app. Para **ver** un vídeo, el servidor entrega por rangos (`206`), de modo que
empieza a reproducirse sin bajarlo entero y se puede adelantar incluso cuando
la carpeta está en la computadora de quien comparte.

La **ficha** de cada compartido —de dónde es la carpeta, quién la comparte (o a
quiénes se la compartí), su estado y lo que se puede hacer— va **en el listado**,
junto a la carpeta: antes salía dentro de la carpeta abierta y tapaba justo lo
que se venía a ver. El menú "⋮" de cada tarjeta es el mismo del Drive: **Ver** el
contenido, **Descargar** (la carpeta entera, en ZIP —el servidor solo entrega
archivo por archivo, así que el ZIP se arma en la app, con sus subcarpetas y
guardándose en Descargas—) y, en una carpeta propia,
**Editar destinatarios** y **Eliminar el compartido**. En una carpeta que te
comparten solo se ofrecen Ver y Descargar: ahí el servidor no da escritura y no
se finge que se puede.

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
con `/api/local/status`): *Disponible* (está en el servidor), *Apagada ahora*
(su app no está abierta), *Servidor sin base de datos* (al servidor del drive le
falta `DRIVE_DB`), *Ya no está compartida* (el compartido se dio de baja) o *No
disponible*, con el motivo que manda el servidor. La carpeta que se sirve desde
la computadora del dueño **ya no lleva píldora**: "En línea" era el caso normal
y solo ocupaba sitio en cada tarjeta. Ese último caso también cubre un servidor
todavía sin actualizar, que contesta 404 con "La carpeta compartida no existe o
ya no está activa": el módulo lo traduce a "Ya no está compartida" y explica
qué hacer, en vez de mostrar el texto crudo.

## Conexión: servidores del Drive

**Solo la abre el Superadministrador** (usuario 1, rol Superadmin). El backend
lo exige en su cuenta (`/api/admin/drive-nodes` responde 403 a cualquier otro)
y el panel ni siquiera dibuja el módulo en el menú.

Los servidores se ven como un **diagrama de red interactivo** (no una tabla):
el **HUB** aparece como el router central, arriba, con una línea a **cada**
servidor; cada servidor es una **card** con toda su ficha —**nombre,
dirección, notas**, **estado** (En línea / Sin respuesta / Mantenimiento /
Apagado / Sin comprobar, con el motivo debajo), **versión**, **prioridad**,
**bibliotecas** (`sharp` y `ffmpeg` con ✓/✕), **espacio** (libre / total con su
barra), **RAM consumida** (usada / total con su barra, la informa cada nodo en
su `/api/health`), **ping** (lo que tardó ese servidor en contestar, medido por
el hub), su **descripción** (las notas del servidor, visibles en la card) y
**de quién depende**—. Las líneas del hub van **punteadas** cuando ese servidor
no responde, así se ve el tramo roto de un vistazo.

En computadora la pantalla va en **dos columnas**: a la izquierda queda **solo
el diagrama** (y los avisos que explican por qué no carga); el **estado del
HUB** —«Hub conectado» / «Hub sin respuesta», cuántos servidores están en
línea y la latencia, con el botón *Probar*— ya no ocupa una tarjeta encima del
diagrama: va en el panel fijo de la derecha, junto a la **dirección del Drive**
con *Configurar hub*, los **detalles de la conexión** y el aviso de conexión
local. En pantalla angosta todo se apila.

Se puede **hacer clic** en una card para iluminar SOLO sus conexiones (y volver
a hacer clic para quitar), **arrastrarla** para reacomodar el diagrama y usar su
menú **⋯**. En pantalla angosta no hay diagrama: son tarjetas con los mismos
datos, una debajo de otra.

El menú **⋯** de cada card trae: *Editar*, *Dependencias*, *Ver terminal*,
*Reiniciar servicio*, *Subir al proyecto*, *Apagar/Encender* y *Quitar*.

- **Dependencias** — un **modal propio** (ya no dentro de *Editar*): se marcan
  los servidores de los que éste depende, se ve el resumen («independiente» o
  «unificado con N servidores») y se guarda. Si la base no tiene todavía la
  columna `depends_on`, el modal dice qué migración ejecutar en vez de guardar
  sin avisar.
- **Ver terminal** — el log del servicio (`journalctl -u hardstreet-drive -n
  400`), en una ventana oscura de **solo lectura** con *Actualizar* y
  *Reiniciar servicio*. No es una consola: no se escriben comandos.
- **Reiniciar servicio** — pide confirmación y ejecuta `systemctl restart` en
  ese servidor. El Drive deja de responder unos segundos.
- **Subir al proyecto** — copia los archivos elegidos a la carpeta del proyecto
  del servidor (`/home/orion/hardstreet-drive`). No reinicia: si cambiaste
  código, reinicia después.

**Selección múltiple y subida en lote:** con *Seleccionar* cada card muestra
su casilla; se marcan varios servidores y *Subir proyecto a los marcados* elige
los archivos **una vez** y los manda a cada uno (el resumen dice a cuántos llegó
y cuáles fallaron).

**La dirección del Drive se configura en el HUB**, no suelta en la página:
botón ⚙ de la card del hub (o *Configurar hub* en el panel lateral) abre su
modal, con *Guardar dirección* y *Usar la de fábrica*
(`https://oriongo.ddns.net`).

El panel **no** guarda ningún secreto: pide al hub (`/api/admin/node/:id/...`),
el hub comprueba con el backend que la sesión es del Superadministrador y solo
entonces reenvía al servidor con su `DRIVE_HUB_TOKEN`. Ese secreto va en el
`.env` de **cada servidor de archivos** (`/home/orion/hardstreet-drive/.env`),
en el del hub y en el backend, siempre con el mismo valor; el servidor lo dice
en el error de la terminal si falta.

### Dependencia entre servidores (mantenimiento)

En *⋯ → **Dependencias*** se marcan los servidores de los que éste depende
(puede ser mutuo). En el diagrama cada dependencia es una **línea entre las dos
cards** con flecha hacia el servidor del que se depende; si es **mutua**, la
línea lleva flecha en **ambas puntas** (una sola línea, no dos). Si uno de ellos
**no responde**, este queda **bloqueado**: el
hub deja de listar, leer y guardar ahí, y el Drive muestra una tarjeta ámbar
**Mantenimiento** con el motivo, en vez de enseñar un árbol a medias. Los
servidores independientes siguen funcionando. Al volver el servidor caído, el
dependiente sale solo del mantenimiento.

## Botón ATRÁS (móvil y navegador)

Un solo sitio decide qué hace el atrás: la cadena de `BackNav`
(`lib/back_nav.dart`) y el `PopScope` raíz que instala el panel (`AdminHome`,
`canPop: false`). Antes cada pantalla tenía su propio `PopScope`; en la **web**
eso no alcanzaba: al estar en la raíz de un módulo el gesto se escapaba, el
motor llamaba a `SystemNavigator.pop()` y el navegador sacaba de la app. En la
web el motor ya convierte el botón del navegador en ese mismo `popRoute`
(mantiene su entrada de historial), así que ahora el gesto del celular y el
botón del navegador recorren LA MISMA cadena, de lo más específico a lo más
general:

1. **Deseleccionar**: con fotos marcadas, el primer atrás quita la selección
   (no se mueve de carpeta ni cierra nada).
2. **Carpeta padre**: dentro de una carpeta vuelve un nivel —en Archivos y en
   la carpeta compartida abierta desde su módulo—.
3. **Sub-vista**: una carpeta compartida abierta vuelve al listado del módulo
   Archivos compartidos.
4. **Módulo de inicio**: desde cualquier otro módulo vuelve al PRIMER módulo
   que el rol ve al entrar (`_homeSection`, el mismo que elige el arranque).
5. **¿Salir?**: ya en el módulo de inicio pregunta «¿Salir de la app?» con
   Cancelar / Salir; solo con **Salir** se cierra (en la web el motor retira
   sus entradas del historial y sale, no deja una página en blanco).

Cada página registra su paso en `initState` y lo quita en `dispose`; el orden
del registro es el de montaje, así que lo abierto DENTRO de un módulo atiende
antes que su listado y el panel siempre queda al final. Las pruebas
(`test/back_nav_test.dart` y `test/panel_start_test.dart`) mandan el mismo
mensaje `popRoute` que Android y el motor web.

## Barra de estado de la PWA (instalada desde la web)

Al instalar el panel desde el navegador, la barra de notificaciones de Android
toma el `theme_color` del **manifest** (Chrome no lee el
`meta[name=theme-color]` en la app instalada), que estaba en el azul de la
marca (`#2F6BFF`): se veía una franja azul sobre una app oscura. Ahora es el
fondo de la app (`#0C111C`), el mismo del arranque; `background_color` (la
pantalla de arranque de la PWA) y el meta del `web/index.html` van igual. En el
APK nativo no cambia nada: ahí manda `applySystemChromeStyle`.

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

## Actualizaciones internas (Windows) — la app en la bandeja

El actualizador baja el setup y lo lanza con `/SILENT`; la app espera 1.5 s y
sale (`exit(0)`) para liberar el `.exe` y las DLL, y el instalador la relanza
al terminar (el `[Run]` silencioso del `.iss`).

Pero al cerrar la ventana la app **no se apaga**: se queda en la bandeja (ver
«Avisos en tiempo real»). Windows Restart Manager, que es lo que Inno Setup usa
para detectar y cerrar lo que está en uso, solo le manda un `WM_CLOSE` y la app
lo interpretaba como «esconde la ventana»; el proceso seguía vivo y el
instalador mostraba *«El programa de instalación no pudo cerrar de forma
automática todas las aplicaciones…»* (Reintentar / Ignorar / Cancelar). Pasaba
en las computadoras donde la app llevaba días en la bandeja (o con más de una
instancia abierta), no en las que se abrió y cerró desde el menú de la bandeja.

El `.iss` ahora lleva `CloseApplications=force` (cierra a la fuerza lo que no
se cierra solo, en vez de preguntar) y `RestartApplications=no` (la app se
relanza con su propio `[Run]`; si no, abriría DOS instancias). Detalle menor: el
icono de la bandeja de la instancia cerrada a la fuerza puede quedar visible
hasta que el ratón pasa por encima.

## Marca: el mismo icono en todas las apps

El icono es **UNO**: `hs_icon.png` (raíz del repo). De ahí salen el `.ico` de
Windows (app e instalador de Inno Setup), los `mipmap` de Android, el favicon y
los iconos PWA del panel web, y el favicon del sitio y del portal del cliente
(`Hardstreet/images/hs_icon.png`, `Hardstreet/me/favicon.png`).

```bash
cd Hardstreet_Admin
node tool/generate_icons.mjs   # requiere sharp (usa el del backend hermano)
```

Al cambiar `hs_icon.png` hay que volver a correrlo: si no, el ejecutable, el
APK y la web seguirían con el icono viejo (`build_installer.ps1` lo llama solo).

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
