# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| **Paquetes** | ✅ Catálogo estilo flyer (tier, categoría, servicios, imagen); el formulario tiene pestañas Datos / Servicios, vista previa en vivo y permite AGREGAR servicios sin salir |
| **Servicios** | ✅ Catálogo con icono, nombre, descripción y liga del Drive (opcional) |
| **Clientes** | ✅ CRUD + tarjeta interactiva que abre el modal de administración de paquetes |
| **Finanzas** | ✅ Ganancias, inversiones, gastos y ahorro (con gráfica por mes y "abonar al ahorro") |
| **Usuarios / Roles** | ✅ CRUD + permisos por módulo |
| **Agendas** | ✅ Calendario de eventos con franja de próximos eventos y **alta de eventos** eligiendo cliente → su paquete → servicio |
| Dashboard, Configuraciones, Reportes | 🚧 Próximamente |

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
  próximos primero) y Movimientos.

El **directorio de clientes** también es interactivo: toda la tarjeta (nombre,
correo, teléfono y el número de paquetes) abre el administrador de paquetes al
tocarla, sin quitar los botones de siempre (Paquetes / Editar / Eliminar). En
pantallas angostas esas acciones se guardan en el menú **⋮** de la tarjeta.

En ventanas angostas (menos de 1020 px de ancho, p. ej. un teléfono) la ficha
queda arriba y las pestañas abajo; la ficha, el precio y el pie del modal se
reacomodan en vez de recortar contenido.

### Movimientos y ahorro

La pestaña **Movimientos** concentra el dinero del paquete:

- Arriba, las tarjetas de control: **Disponible** (abonado − gastado, ya no
  repite el abonado que muestra la ficha), **Ahorro**, **Abono externo**,
  **Invertido** y **Gastado**. Se reacomodan solas (2, 3 o 4 por fila) según
  el ancho.
- **Abonar** (tabla de abonos: mantiene el total pagado) y **Registrar
  movimiento**: inversión, gasto, **ahorro** o abono externo.
- El **ahorro** se captura como cantidad o como **porcentaje del disponible**,
  que además deja constancia del % aplicado en su concepto.
- Estos movimientos son informativos: no tocan el total abonado ni el saldo
  del paquete (eso lo hacen los abonos).

## Módulo Finanzas

Todo lo monetario del negocio en una sola vista (`/api/admin/finance`,
permiso sobre el módulo "Finanzas"):

- **Resumen del dinero**: cuadros horizontales con ganancias (abonos
  cobrados), por cobrar, disponible, ahorro, inversiones, gastos y abono
  externo.
- **Gráfica de los últimos 6 meses**: lo que ENTRÓ contra lo que SALIÓ
  (gastos, inversión, ahorro y abono externo), con su leyenda.
- **Ahorro**: el total apartado y **Abonar al ahorro**, que destina dinero de
  UN paquete por cantidad o por porcentaje del disponible.
- **Por paquete**: el dinero de cada paquete activo con su cliente.

El **Dashboard** añade esa misma información en versión compacta (cuadros +
gráfica) y un acceso rápido al módulo. Todo es *best effort*: si el usuario no
tiene permiso o no hay conexión, el resto del dashboard sigue viéndose.

Requiere la migración `Hardstreet-DB/2026-10-14_modulo_finanzas.sql`, que
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
- Sube varias imágenes a la vez desde el selector nativo del sistema.
- Vista de cuadrícula con miniaturas o vista de lista (nombre, fecha, tamaño).
- Buscar dentro de la carpeta, renombrar, eliminar, crear carpetas.
- Visor de imágenes con zoom y navegación entre imágenes de la carpeta.
- Si un refresco de fondo falla (servidor ocupado mientras subes fotos), el
  listado se queda a la vista y solo aparece el aviso “Sin conexión ·
  reintentar”: el directorio no se vacía ni cambia por un fallo pasajero.

Las imágenes se guardan en carpetas reales del sistema dentro de
`Documentos/HardStreetDrive` (multiplataforma: Windows, macOS, Linux). Puedes
abrir esa carpeta con el explorador de archivos y verás la misma estructura.

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
