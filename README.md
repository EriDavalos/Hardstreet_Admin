# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| **Paquetes** | ✅ Catálogo estilo flyer (tier, categoría, servicios, imagen); el formulario tiene pestañas Datos / Servicios |
| **Servicios** | ✅ Catálogo con icono, nombre, descripción y liga del Drive (opcional) |
| **Clientes** | ✅ CRUD + modal de administración de paquetes |
| **Usuarios / Roles** | ✅ CRUD + permisos por módulo |
| **Agendas** | ✅ Calendario de eventos y abonos |
| Dashboard, Configuraciones, Reportes | 🚧 Próximamente |

## Modal de paquete (Clientes)

Al abrir un cliente se administran sus paquetes en un solo modal:

- **Primero las tarjetas** de sus paquetes ("targets"); al tocar una se
  entra al detalle con animación (la flecha del encabezado regresa).
- **Izquierda — la ficha del paquete**: el flyer del catálogo con el look
  de su tier (Premium = oro sobre negro, Gold = ámbar, Basic = acero),
  más dinero (abonado/saldo/pagado), avance y el botón Finalizar.
- **Derecha — la administración**: pestañas de Servicios (con la liga base
  del Drive de cada servicio, copiable y editable), Calendario (días en
  círculos, igual al módulo Agendas) y Movimientos (aquí vive Abonar;
  gastos, inversiones y abonos externos solo se reflejan aquí).

En ventanas angostas (menos de 1020 px de ancho, p. ej. un teléfono) la ficha
queda arriba y las pestañas abajo; la ficha, el precio y el pie del modal se
reacomodan en vez de recortar contenido.

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
