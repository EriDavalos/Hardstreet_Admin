/// Constantes globales de la app Hardstreet Admin.
/// Cambia aquí el nombre, la dirección del API y la versión — un solo lugar.
class AppConstants {
  AppConstants._();

  /// Nombre visible de la aplicación (título de ventana, web y Android).
  static const String appName = 'Hardstreet Admin';

  /// Base del API del drive.
  /// Se puede sobreescribir al compilar con: --dart-define=DRIVE_API=http://ip:4000
  static const String apiBase = String.fromEnvironment(
    'DRIVE_API',
    defaultValue: 'http://oriongo.ddns.net:4000',
  );

  /// Base del API de administración/CRUD (Hardstreet-Backend en Vercel):
  /// login, usuarios, roles, clientes y paquetes. Es LA MISMA API que usa la web.
  /// Override: --dart-define=CRUD_API=https://otro-backend.vercel.app
  static const String crudApiBase = String.fromEnvironment(
    'CRUD_API',
    defaultValue: 'https://apihardstreet.vercel.app',
  );

  /// Versión COMPILADA en el binario (referencia real del .exe/.apk).
  /// El instalador no puede leer pubspec en caliente; mantenla igual a
  /// pubspec.yaml o pásala con --dart-define=SP_VERSION=x.y.z al compilar.
  static const String buildVersion = String.fromEnvironment(
    'SP_VERSION',
    defaultValue: '1.0.2',
  );

  /// Override opcional (útil en desarrollo): --dart-define=APP_VERSION=x.y.z
  static const String appVersionOverride = String.fromEnvironment(
    'APP_VERSION',
  );

  /// Versión efectiva de esta build (la que se compara contra el servidor).
  static String get effectiveVersion =>
      appVersionOverride.isNotEmpty ? appVersionOverride : buildVersion;

  /// Delay para empezar a ARRASTRAR con presión larga (solo móvil).
  /// ~350ms: suficiente para distinguir scroll de arrastre intencional.
  static const Duration longPressDragDelay = Duration(milliseconds: 350);
}
