# HardStreet Admin

Panel de administración de HardStreet con diseño moderno (sidebar colapsable, modo claro/oscuro).

## Estado de los módulos

| Módulo | Estado |
|---|---|
| **Archivos (Drive)** | ✅ Funcional — estilo Google Drive |
| Dashboard | Placeholder con métricas de ejemplo |
| Usuarios, Clientes, Configuraciones, Reportes | 🚧 Próximamente |

## Módulo Archivos (Drive)

- Carpetas anidadas (`ReynaCoot/SesionPrevia/Fiesta/...`), navegación por breadcrumbs.
- Sube varias imágenes a la vez desde el selector nativo del sistema.
- Vista de cuadrícula con miniaturas o vista de lista (nombre, fecha, tamaño).
- Buscar dentro de la carpeta, renombrar, eliminar, crear carpetas.
- Visor de imágenes con zoom y navegación entre imágenes de la carpeta.

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
