import 'drive_host.dart';

/// Constantes globales de la app Hardstreet Platform.
/// Cambia aquí el nombre, la dirección del API y la versión — un solo lugar.
class AppConstants {
  AppConstants._();

  /// Nombre visible de la aplicación (título de ventana, web y Android).
  static const String appName = 'Hardstreet Platform';

  /// Base del API del drive.
  ///
  /// Sale de [DriveHost]: la de fábrica (`https://oriongo.ddns.net`, o la que
  /// se pase con `--dart-define=DRIVE_API=http://ip:4000`) o la que el usuario
  /// haya guardado en la app (p. ej. `http://192.168.1.72:4000` para trabajar
  /// desde la red de la oficina, donde el nombre público no resuelve al
  /// servidor).
  static String get apiBase => DriveHost.base;

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
    defaultValue: '1.1.6',
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
