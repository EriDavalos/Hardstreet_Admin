import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_awake.dart';
import 'app_constants.dart';
import 'app_platform.dart';
import 'app_settings.dart';
import 'back_nav.dart';
import 'drive_api_service.dart';
import 'drive_host.dart';
import 'event_widget.dart';
import 'hs_access.dart';
import 'hs_api.dart';
import 'drive_scope.dart';
import 'image_memory.dart';
import 'local_share_agent.dart';
import 'pages/activity_page.dart';
import 'pages/admin_pages.dart';
import 'pages/agendas_page.dart';
import 'pages/notes_page.dart';
import 'pages/clients_page.dart';
import 'pages/client_dashboard_page.dart';
import 'pages/companies_page.dart';
import 'pages/connection_page.dart';
import 'pages/drive_page.dart';
import 'pages/finance_page.dart';
import 'pages/login_page.dart';
import 'pages/notifications_page.dart';
import 'pages/packages_page.dart';
import 'pages/roles_page.dart';
import 'pages/services_page.dart';
import 'pages/settings_page.dart';
import 'pages/shared_files_page.dart';
import 'pages/site_page.dart';
import 'pages/print_page.dart';
import 'pages/storage_page.dart';
import 'pages/users_page.dart';
import 'package_notifications_service.dart';
import 'reminder_notifications_native.dart';
import 'reminders_service.dart';
import 'theme.dart';
import 'version_checker.dart';
import 'widgets/admin_shell.dart';
import 'widgets/company_selector.dart';
import 'widgets/brand_badge.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/force_update_dialog.dart';
import 'widgets/hs_toast.dart';
import 'widgets/startup_intro.dart';
import 'widgets/wheel_fix.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // En el NAVEGADOR, el clic derecho es NUESTRO: abre el menú de la app
  // (Descargar / Renombrar / Eliminar) y no el del navegador con "Inspeccionar"
  // y demás. En escritorio y móvil nativo esta llamada no existe.
  if (kIsWeb) {
    unawaited(
      BrowserContextMenu.disableContextMenu().catchError((_) {
        // Navegador sin soporte para desactivarlo: la app sigue igual.
      }),
    );
  }
  applySystemChromeStyle(isDark: false);
  runApp(const HardStreetAdminApp());
}

/// ÚNICO punto donde se configura el estilo de las barras del sistema
/// (status bar y barra de navegación).
///
/// Antes cada página llamaba SystemChrome.setSystemUIOverlayStyle en su
/// build y se pisaban entre sí (el estilo quedaba indeterminado y la barra
/// de notificaciones se veía NEGRA). Ahora:
/// - [SystemUiMode.edgeToEdge]: el sistema dibuja la app de borde a borde y
///   Flutter controla el color detrás de las barras (en Android 15+ el
///   sistema IGNORA statusBarColor y usa el color del contenido).
/// - statusBarColor transparente + iconos según el tema activo: la barra de
///   notificaciones muestra el fondo real de la app (blanco/oscuro), nunca
///   negro.
/// - La barra de navegación (gestos/botones) toma el color del scaffold.
void applySystemChromeStyle({required bool isDark}) {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      // La barra del sistema toma el fondo de la PALETA vigente, no un color
      // fijo: con «Vino» o «Marfil» la franja no puede quedar azul noche.
      systemNavigationBarColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
}

class HardStreetAdminApp extends StatefulWidget {
  const HardStreetAdminApp({super.key});

  @override
  State<HardStreetAdminApp> createState() => _HardStreetAdminAppState();
}

class _HardStreetAdminAppState extends State<HardStreetAdminApp> {
  /// Llave del Navigator raíz: permite mostrar diálogos globales (ventana
  /// de actualización obligatoria) desde FUERA del árbol de MaterialApp.
  /// Antes se usaba el context del State (que está POR ENCIMA del Navigator)
  /// y showDialog crasheaba en silencio: la app se bloqueaba sin mostrar
  /// nunca la ventana de "Actualización requerida".
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  bool _loggedIn = false;

  /// Actualización DISPONIBLE (no obligatoria): se muestra un banner
  /// discreto, sin bloquear el uso del panel.
  AppVersionInfo? _pendingUpdate;

  /// true mientras el diálogo OBLIGATORIO de actualización esté activo
  /// (evita re-mostrarlo en cada chequeo periódico).
  bool _forceUpdateShown = false;

  /// true cuando NO se pudo contactar al servidor para revisar la versión:
  /// bloquea el login con una ventana de "reintentar".
  bool _versionError = false;
  bool _checkingVersion = false;
  Timer? _versionTimer;

  /// Reutiliza un DriveScope heredado si existe (útil en tests);
  /// si no, crea el cliente del drive remoto (192.168.1.72:4000).
  DriveBase? _injectedDrive;

  /// true cuando la app abrió con una sesión restaurada ("Recordarme"): el
  /// primer chequeo de versión se comportará como entrada YA logueada.
  bool _sessionRestored = false;

  /// true cuando la animación de arranque terminó (antes, la intro ocupa la
  /// pantalla). Así el arranque se siente continuo en Windows y en Android.
  bool _introDone = false;

  bool get _hasSession => HsSession.isLogged || _sessionRestored;

  @override
  void initState() {
    super.initState();
    // La caché de imágenes se configura para evitar picos de memoria en
    // galerías grandes; al minimizar no se vacía para conservar la vista.
    ImageMemory.configure();
    if (!kWeb) ImageMemory.pruneDiskCache();
    // Sesión expirada (401 con "Recordarme"): regresar al login.
    HsApi.onUnauthorized = () {
      if (!mounted) return;
      // Sesión caída: el Drive tampoco puede seguir mostrando la carpeta de la
      // cuenta anterior.
      (_injectedDrive ?? _ownedDrive).resetSession();
      setState(() {
        _loggedIn = false;
        _sessionRestored = false;
      });
    };
    // Configuraciones persistentes (modo oscuro + "Recordarme") — funciona
    // también en web. La app ESCUCHA los cambios: alternar el tema desde el
    // login o desde el panel reconstruye el MaterialApp al instante.
    AppSettings.instance.addListener(_onSettingsChanged);
    // ¿Ventana a la vista? El estado se usa en todo el panel (ver [AppAwake]):
    // en segundo plano solo siguen consultando los avisos.
    AppAwake.instance.start();
    // Preferencia del panel de eventos de escritorio (Windows): se lee ANTES
    // de que el servicio de avisos empiece a alimentarlo.
    UpcomingEventsWidget.load();
    // Toques del widget nativo (Android y Windows): tocar un evento abre su
    // detalle y el botón "Agregar agenda" abre el alta. El widget AVISA; quien
    // navega es el panel (AdminHome + AgendasPage).
    UpcomingEventsWidget.listen();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ¿El widget lanzó la app en frío con una acción? (arranque en frío)
      await UpcomingEventsWidget.consumePending();
      // Permiso de notificaciones (Android 13+ / iOS) al arrancar, no en el
      // primer aviso: sin él, el teléfono DESCARTA los avisos del paquete.
      // En WINDOWS prepara el toast nativo para que el aviso salga aunque
      // estés en otra ventana (no solo dentro de la campanita).
      if (!kIsWeb) {
        unawaited(NativeReminderPlugin.instance.init());
      }
    });
    AppSettings.instance.load().then((_) {
      if (!mounted) return;
      setState(() {});
      // ¿Hay sesión guardada ("Recordarme")? Se restaura ANTES del primer
      // chequeo de versión: si el token expiró, la primera llamada a la API
      // devolverá 401 y el login pedirá credenciales de nuevo.
      if (AppSettings.instance.hasSavedSession) {
        AppSettings.instance.restoreSession();
        _sessionRestored = true;
      }
      // REVISIÓN DE VERSIÓN en CADA entrada (login o ya logueado):
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVersion());
      // Sesión restaurada ("Recordarme"): los avisos también empiezan ya.
      if (_sessionRestored) {
        RemindersService.instance.start();
        PackageNotificationsService.instance.start();
      }
      // Si este usuario comparte carpetas de SU computadora, la app empieza a
      // servirlas (agente): así los demás las ven mientras la app esté abierta.
      if (_sessionRestored) {
        unawaited(LocalShareAgent.instance.syncWithShares());
      }
    });
    // Chequeo periódico mientras la app está a la vista (por si el servidor
    // publica una versión nueva en caliente). En segundo plano solo siguen
    // activos los servicios de notificaciones.
    _versionTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (!AppAwake.instance.awake) return;
      _checkVersion();
    });
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    // El widget de eventos vive FUERA de la app: se le recuerda el tema nuevo
    // (el acento o el modo se pueden cambiar desde Configuraciones).
    UpcomingEventsWidget.refresh();
  }

  /// ¿La app se ve oscura AHORA? (el modo "sistema" sigue al equipo)
  bool get _isDarkNow {
    final mode = AppSettings.instance.themeMode;
    if (mode == HsThemeMode.dark) return true;
    if (mode == HsThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _versionTimer?.cancel();
    RemindersService.instance.stop();
    PackageNotificationsService.instance.stop();
    LocalShareAgent.instance.stop();
    super.dispose();
  }

  /// Base contra la que se consulta /api/version: el CRUD (Hardstreet-Backend,
  /// desplegado en Vercel). Antes se consultaba el servidor del drive.
  String get _versionBase => HsApi.base;

  /// Consulta la versión publicada por el servidor y decide:
  /// - obligatoria (current < minVersion) → diálogo que NO se puede cerrar;
  /// - disponible (current < version)     → banner no bloqueante.
  Future<void> _checkVersion() async {
    if (_forceUpdateShown || _checkingVersion) return;
    // En web y tests NO usar dart:io (Platform.* lanza UnsupportedError).
    if (skipVersionCheck) return;
    _checkingVersion = true;
    if (mounted) setState(() {});
    try {
      await _doCheckVersion();
    } finally {
      _checkingVersion = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _doCheckVersion() async {
    final info = await VersionChecker(_versionBase).check();
    if (!mounted) return;
    // Sin conexión al servidor: ventana con REINTENTAR (no pasa de aquí).
    if (info == null) {
      setState(() => _versionError = true);
      return;
    }
    setState(() => _versionError = false);
    final current = AppConstants.effectiveVersion;
    // Comparación por COMPONENTES (1.2.10 > 1.2.9) contra ambas versiones
    // del servidor: minVersion (obligatoria) y version (disponible).
    if (info.isOutdated(current)) {
      debugPrint(
        '[version] OBLIGATORIA: instalada $current < '
        'mínima ${info.minVersion} (servidor: ${info.version})',
      );
      _forceUpdateShown = true;
      final plat = isAndroidPlatform ? 'android' : 'windows';
      // El APK/EXE se descarga DEL HUB: es el único servidor del Drive al que
      // la app tiene que llegar, y él reenvía `/downloads/<archivo>` al
      // servidor que tenga el release (aunque no sea el principal).
      final url = info.downloadUrlFor(plat, viaBase: DriveHost.base);
      final fallback = info.downloadUrlFor('', viaBase: DriveHost.base);
      // Contexto del NAVIGATOR (dentro de MaterialApp): usar el context del
      // State hace que showDialog falle en silencio y la ventana jamás salga.
      final navCtx = _navKey.currentContext;
      if (navCtx == null || !navCtx.mounted) {
        // Primer frame aún no montado: reintentar en el siguiente.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _forceUpdateShown) {
            final ctx = _navKey.currentContext;
            if (ctx != null && ctx.mounted) {
              ForceUpdateDialog.show(
                ctx,
                currentVersion: current,
                requiredVersion: info.minVersion,
                notes: info.notes,
                downloadUrl: url.isNotEmpty ? url : fallback,
              );
            }
          }
        });
        return;
      }
      await ForceUpdateDialog.show(
        navCtx,
        currentVersion: current,
        requiredVersion: info.minVersion,
        notes: info.notes,
        downloadUrl: url.isNotEmpty ? url : fallback,
      );
      return;
    }
    debugPrint('[version] OK: instalada $current · servidor ${info.version}');
    setState(() {
      _pendingUpdate = info.hasUpdate(current) ? info : null;
    });
  }

  /// Al entrar al panel (por login O por sesión restaurada): valida versión
  /// y bloquea si es obsoleta o si no hay conexión (ventana con reintentar).
  Future<void> _onLogin() async {
    await _checkVersion();
    if (!mounted || _forceUpdateShown) return; // NO entra al panel
    if (_versionError) return; // la ventana de reintento ya está visible
    // Otra cuenta = otro Drive. Sin esto, el módulo Archivos abría en la
    // carpeta de la sesión anterior (que para este usuario no existe) y se
    // veía su raíz sin poder entrar. Siempre se empieza en la raíz propia.
    _resetDriveForSession();
    setState(() => _loggedIn = true);
    // Avisos de eventos próximos + widget: empiezan a consultarse en segundo
    // plano (el widget también se alimenta desde ahí).
    RemindersService.instance.start();
    // Avisos del PAQUETE (fotos disponibles / servicio terminado).
    PackageNotificationsService.instance.start();
    // Carpetas compartidas DESDE esta computadora: el agente empieza a
    // atenderlas (solo si el usuario comparte alguna de su PC).
    unawaited(LocalShareAgent.instance.syncWithShares());
  }

  /// Deja el Drive como recién abierto: raíz de la cuenta (y empresa) nueva.
  ///
  /// La carpeta que estaba viendo la sesión anterior NO se hereda: para la
  /// nueva cuenta esa ruta no existe (o es de otra empresa) y el módulo
  /// Archivos aparecía en una carpeta ajena, vacía y sin permiso.
  void _resetDriveForSession({bool refresh = true}) {
    final drive = _injectedDrive ?? _ownedDrive;
    drive.resetSession();
    // Las imágenes en RAM se indexan por URL, y la misma ruta relativa puede
    // ser una foto distinta en cada empresa: se tiran para no enseñar la de
    // antes durante un instante.
    ImageMemory.clearRam();
    if (refresh) unawaited(drive.refresh());
  }

  /// Cerrar sesión: descarta el token en el servidor y borra lo persistido
  /// ("Recordarme"). Al volver, siempre pasa por el login.
  Future<void> _onLogout() async {
    await HsApi.logout(); // cortesía en el servidor
    await AppSettings.instance.clearSession();
    _resetDriveForSession(refresh: false); // sin token no hay nada que pedir
    HsAccess.reset(); // el siguiente login recarga permisos desde cero
    _sessionRestored = false;
    RemindersService.instance.reset(); // la campanita no recuerda avisos viejos
    PackageNotificationsService.instance.reset();
    // Las carpetas de esta computadora dejan de servirse al salir: sin sesión
    // no hay a quién autorizar.
    LocalShareAgent.instance.stop();
    if (mounted) setState(() => _loggedIn = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _injectedDrive ??= DriveScope.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final drive = _injectedDrive ?? _ownedDrive;
    return DriveScope(
      drive: drive,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // Apariencia elegida en Configuraciones: sistema / claro / oscuro.
        themeMode: switch (AppSettings.instance.themeMode) {
          HsThemeMode.system => ThemeMode.system,
          HsThemeMode.light => ThemeMode.light,
          HsThemeMode.dark => ThemeMode.dark,
        },
        // Rueda del ratón: traduce deltas horizontales (drivers que mandan
        // la rueda vertical en dx) a scroll vertical en TODOS los módulos.
        scrollBehavior: const HsScrollBehavior(),
        title: AppConstants.appName,
        // SafeArea GLOBAL: ninguna pantalla (login, panel, errores) dibuja
        // detrás de la barra de notificaciones en Android.
        builder: (context, child) {
          // Estilo de las barras del sistema alineado al TEMA ACTIVO (único
          // punto de verdad; las páginas ya NO lo repiten en su build).
          final isDark = Theme.of(context).brightness == Brightness.dark;
          applySystemChromeStyle(isDark: isDark);
          // Edge-to-edge: la app SÍ dibuja detrás de la barra de estado;
          // este ColoredBox pinta esa franja con el color del fondo y la
          // SafeArea empuja el contenido debajo de la barra.
          //
          // HsToastHost envuelve TODO: las notificaciones laterales (verde
          // al éxito / rojo al error) flotan encima del panel y de cualquier
          // diálogo abierto.
          return HsToastHost(
            child: ColoredBox(
              color: isDark ? AppColors.bgDark : AppColors.bgLight,
              child: SafeArea(
                bottom: false,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        // ARRANQUE: primero la animación de marca y, al terminar, un fundido
        // cruzado hacia el contenido (login o panel). La clave del contenido
        // es estable, así que el cruce ocurre UNA vez: la intro nunca vuelve.
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _introDone
              ? KeyedSubtree(
                  key: const ValueKey('hs-home'),
                  child: _home(context),
                )
              : StartupIntro(
                  key: const ValueKey('hs-intro'),
                  onDone: () => setState(() => _introDone = true),
                ),
        ),
      ),
    );
  }

  /// Contenido real de la app (lo que aparece tras la animación de arranque).
  Widget _home(BuildContext context) {
    if (_versionError) {
      return _VersionErrorScreen(
        onRetry: () async {
          setState(() => _versionError = false);
          await _checkVersion();
        },
      );
    }
    if (_loggedIn || (_hasSession && AppSettings.instance.loaded)) {
      return AdminHome(
        dark: _isDarkNow,
        onToggleTheme: () {
          final v = !AppSettings.instance.dark;
          AppSettings.instance.setDark(v); // persiste
          // El widget de eventos vive FUERA de la app: hay que
          // recordarle el modo nuevo para que se repinte igual.
          UpcomingEventsWidget.refresh();
          setState(() {});
        },
        onLogout: _onLogout,
        updateBanner: _buildUpdateBanner(context),
      );
    }
    return LoginPage(onLogin: _onLogin);
  }

  /// Banner discreto de "actualización disponible" (NO bloqueante).
  Widget? _buildUpdateBanner(BuildContext context) {
    final info = _pendingUpdate;
    if (info == null) return null;
    return UpdateBanner(
      latestVersion: info.version,
      currentVersion: AppConstants.effectiveVersion,
      notes: info.notes,
      onDownload: () async {
        final plat = isAndroidPlatform ? 'android' : 'windows';
        // Se descarga del HUB (ver [AppVersionInfo.downloadUrlFor]).
        final url = info.downloadUrlFor(plat, viaBase: DriveHost.base);
        // Mismo modal de actualización (descarga interna con barra de
        // progreso + instalación); NO abre el navegador.
        final ctx = _navKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        await ForceUpdateDialog.show(
          ctx,
          currentVersion: AppConstants.effectiveVersion,
          requiredVersion: info.version,
          notes: info.notes,
          downloadUrl: url,
          optional: true,
        );
      },
      onClose: () => setState(() => _pendingUpdate = null),
    );
  }

  DriveApiService? _ownedDriveInstance;
  DriveApiService get _ownedDrive => _ownedDriveInstance ??= DriveApiService();
}

/// Pantalla de CARGA del panel: se ve mientras se leen los permisos del usuario
/// (de ellos dependen el menú y el módulo con el que abre la app).
///
/// Existe para que el arranque no muestre un módulo y luego otro: el panel
/// aparece YA en su módulo, o aquí si todavía no se sabe cuál es.
class PanelLoadingScreen extends StatelessWidget {
  const PanelLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    // Mismo fondo que la animación de arranque: la intro cede el paso a esta
    // pantalla sin costura, sin un parpadeo blanco de por medio.
    final background = dark ? AppColors.bgDark : AppColors.bgLight;
    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandBadge(size: 64, radius: 20, elevated: false),
            const SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Preparando tu panel…',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla cuando NO se pudieron leer los permisos: sin conexión con el
/// servidor no se sabe qué módulos puede ver el usuario, así que no se dibuja
/// el panel completo. Explica el problema y ofrece REINTENTAR.
class PanelNoConnectionScreen extends StatelessWidget {
  const PanelNoConnectionScreen({super.key, required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 72, color: scheme.error),
              const SizedBox(height: 18),
              Text(
                'Falta la conexión',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'No se pudieron comprobar tus permisos, así que todavía no se '
                'sabe qué módulos puede ver tu usuario.\n\n'
                'Revisa tu conexión a internet e inténtalo de nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla bloqueante cuando NO se pudo revisar la versión (sin conexión):
/// explica el problema y ofrece REINTENTAR. No se puede saltar.
class _VersionErrorScreen extends StatelessWidget {
  const _VersionErrorScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 72, color: scheme.error),
              const SizedBox(height: 18),
              Text(
                'No hay conexión con el servidor',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'No se pudo verificar la versión de la aplicación '
                '(${AppConstants.apiBase}). '
                'Revisa tu conexión e inténtalo de nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nombre del MÓDULO (permiso de la BD) que respalda cada sección.
///
/// Se usa para saber a qué secciones se tiene acceso SIN depender del menú
/// dibujado: elegir el módulo de arranque y reaccionar cuando los permisos
/// cambian. El orden es el del panel (mismo criterio que el sidebar).
/// Nombre de RESPALDO de cada sección. El nombre visible real es
/// `modules.name` y llega en [HsAccess.catalog]; esto solo se usa si el
/// backend todavía no lo reporta (modo degradado o pruebas).
const Map<_Section, String> _kSectionModules = {
  _Section.dashboard: 'Dashboard',
  _Section.clientDashboard: 'Mi paquete',
  _Section.drive: 'Archivos',
  _Section.sharedFiles: 'Archivos compartidos',
  _Section.agendas: 'Agendas',
  _Section.notes: 'Notas',
  _Section.finance: 'Finanzas',
  _Section.storage: 'Almacenamiento',
  _Section.prints: 'Impresiones',
  _Section.connection: 'Conexión',
  _Section.users: 'Usuarios',
  _Section.roles: 'Roles',
  _Section.clients: 'Clientes',
  _Section.packages: 'Paquetes',
  _Section.services: 'Servicios',
  _Section.activity: 'Actividad',
  _Section.site: kSiteModuleName,
  _Section.settings: 'Configuraciones',
  _Section.reports: 'Reportes',
  _Section.companies: 'Empresas',
  _Section.notifications: 'Notificaciones',
};

/// CLAVE de módulo (`modules.module`) de cada sección. Es la identidad que
/// manda: los permisos, el nombre y la descripción se buscan por ella, así
/// que renombrar un módulo en la BD no rompe el menú.
const Map<_Section, String> _kSectionKeys = {
  _Section.dashboard: 'dashboard',
  _Section.clientDashboard: 'my_package',
  _Section.drive: 'drive',
  _Section.sharedFiles: 'shared_files',
  _Section.agendas: 'schedules',
  _Section.notes: 'notes',
  _Section.finance: 'finance',
  _Section.storage: 'storage',
  _Section.prints: 'print',
  _Section.connection: 'connection',
  _Section.users: 'users',
  _Section.roles: 'rols',
  _Section.clients: 'clients',
  _Section.packages: 'packages',
  _Section.services: 'services',
  _Section.activity: 'activity',
  _Section.site: 'web',
  _Section.settings: 'settings',
  _Section.reports: 'reports',
  _Section.companies: 'companies',
  _Section.notifications: 'notifications',
};

/// Índices de las secciones del panel.
enum _Section {
  dashboard,
  clientDashboard,
  companies,
  drive,
  sharedFiles,
  agendas,
  notes,
  finance,
  connection,
  users,
  roles,
  clients,
  packages,
  services,
  activity,
  storage,
  prints,
  settings,
  reports,
  site,
  notifications,
}

class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    required this.dark,
    required this.onToggleTheme,
    required this.onLogout,
    this.updateBanner,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  /// Banner opcional de "actualización disponible" bajo la barra superior.
  final Widget? updateBanner;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  // Sección visible. Arranca en Dashboard, pero en cuanto se conocen los
  // permisos se salta al PRIMER módulo que el rol puede ver (ver
  // [_pickStartSection]): el Dashboard solo si es el primero permitido.
  _Section _section = _Section.dashboard;

  /// MÓDULO DE INICIO: «el primer módulo que le sale a cada usuario» (por
  /// permisos y orden del menú). Es a donde vuelve el atrás cuando ya no queda
  /// nada más que deshacer —carpeta, selección o sub-vista—.
  _Section _homeSection = _Section.dashboard;

  /// Paso de ATRÁS del panel: el ÚLTIMO de la cadena (ver [BackNav]).
  late final BackStep _backStep = _handleBack;

  /// true mientras está abierto el aviso «¿Salir de la app?».
  bool _askingExit = false;

  /// El arranque se decide UNA vez (si no, cada rebuild volvería a saltar).
  bool _startPicked = false;

  /// Orden REAL del menú en la última build (lo fija la BD): es de donde sale
  /// el "primer módulo" y el respaldo cuando la sección actual deja de ser
  /// visible.
  List<_Section?> _menuOrder = const [];

  bool _sidebarOpen = false;

  /// Sube cada vez que el Superadministrador cambia de empresa: fuerza a
  /// remontar la página actual para que pida los datos de la nueva.
  int _companyEpoch = 0;

  void _onCompanyChanged() {
    if (!mounted) return;
    // El Superadministrador cambia de empresa: el Drive vuelve a la RAÍZ de la
    // empresa nueva (antes se quedaba en la carpeta de la anterior, que para
    // esta empresa no existe) y se recargan sus carpetas compartidas.
    final drive = _drive;
    drive.resetSession();
    ImageMemory.clearRam();
    unawaited(() async {
      await _loadDriveScope();
      await drive.refresh();
    }());
    setState(() => _companyEpoch++);
  }

  /// Ya se pidió el alcance al abrir el panel. Se conserva esa carga inicial;
  /// al entrar de nuevo a Archivos se vuelve a consultar por si el cliente
  /// recibió carpetas mientras tenía abierta la sesión.
  bool _driveScopeLoaded = false;
  bool _driveWasActive = false;

  DriveBase get _drive => DriveScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_driveScopeLoaded) return;
    _driveScopeLoaded = true;
    unawaited(_loadDriveScope());
  }

  /// Limita el drive a las carpetas COMPARTIDAS cuando el usuario es un
  /// CLIENTE (sus paquetes comprados definen qué ve); el equipo del estudio
  /// sigue viendo el drive completo. Best effort: sin conexión o con un
  /// backend viejo, el drive se queda como estaba.
  Future<void> _loadDriveScope() async {
    // El drive se guarda ANTES de cualquier await: después, el contexto puede
    // estar desmontado y no se debe volver a mirar el árbol.
    final drive = _drive;
    try {
      final info = await HsApi.myDriveDirectories();
      if (!mounted) return;
      await drive.setSharedRoots(
        [for (final p in info.paths) (p['path'] ?? '').toString()],
        isClient: info.isClient,
        refresh: false,
      );
      await drive.refresh();
    } catch (_) {
      // Sin permiso/sin red: no se toca el alcance del drive.
    }
    // El drive remoto se crea al construir la app, ANTES de que exista la
    // sesión: su primer refresco se omite a propósito (saldría sin `Apikey` y
    // el servidor lo rechazaría). Ya con la sesión en marcha, se pide.
    if (drive is DriveApiService && drive.waitingSession) {
      unawaited(drive.refresh());
    }
  }

  @override
  void initState() {
    super.initState();
    // El panel se apunta al FINAL de la cadena del atrás: las páginas de los
    // módulos se registran después y por eso se atienden primero.
    BackNav.add(_backStep);
    HsAccess.addListener(_onAccessChanged);
    // En segundo plano el panel conserva la vista; los servicios de
    // notificaciones siguen consultando en su propio ciclo.
    _loadPermissions();
    // Toques del widget nativo: tocar un evento (o el botón "Agregar agenda")
    // lleva a Agendas; la página abre el detalle o el alta.
    UpcomingEventsWidget.requested.addListener(_onWidgetRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (UpcomingEventsWidget.requested.value != null) _onWidgetRequest();
    });
    // Al guardar permisos en Roles: el menú se adapta AL INSTANTE.
    HsApi.onPermissionsChanged = () async {
      await _loadPermissions();
      // Si la sección actual dejó de ser visible, regresa a Archivos.
      if (!mounted) return;
      final canSee = switch (_section) {
        _Section.users => _canSee('users'),
        _Section.roles => _canSee('rols'),
        _Section.clients => _canSee('clients'),
        _Section.packages => _canSee('packages'),
        _Section.agendas => _canSee('schedules'),
        _Section.finance => _canSee('finance'),
        _Section.dashboard => _canSee('dashboard'),
        _Section.clientDashboard => _canSee('my_package'),
        _Section.drive => _canSee('drive'),
        _Section.activity => _canSee('activity'),
        _Section.storage => _canSee('storage'),
        _Section.connection => _canSee('connection'),
        _Section.settings => _canSee('settings'),
        _Section.reports => _canSee('reports'),
        _Section.companies => _canSee('companies'),
        _ => true,
      };
      if (!canSee) {
        // La sección actual ya no es visible: se cae al PRIMER módulo permitido
        // (mismo criterio que el arranque), no siempre a Archivos/Dashboard.
        setState(() {
          _section = _firstAllowedSection();
        });
      }
    };
  }

  @override
  void dispose() {
    BackNav.remove(_backStep);
    HsApi.onPermissionsChanged = null;
    HsAccess.removeListener(_onAccessChanged);
    UpcomingEventsWidget.requested.removeListener(_onWidgetRequest);
    super.dispose();
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  /// El widget nativo pidió abrir algo: se salta a Agendas (si el rol puede
  /// verlas) y la página se encarga del detalle o del alta.
  void _onWidgetRequest() {
    if (!mounted || UpcomingEventsWidget.requested.value == null) return;
    if (_canSee('schedules')) setState(() => _section = _Section.agendas);
  }

  /// Descarga los permisos del usuario (HsAccess) y refresca el menú.
  Future<void> _loadPermissions() async {
    await HsAccess.load();
    // El widget nativo también vive de los permisos (el botón "Agregar
    // agenda"): se le recuerda el estado nuevo en cuanto se conocen.
    UpcomingEventsWidget.refresh();
    if (mounted) setState(() {});
  }

  /// Primer módulo PERMITIDO según el orden del panel (no el del dibujo: se
  /// calcula con los permisos, así sirve incluso antes de la primera build
  /// del menú). Respaldo final: Dashboard, que siempre existe.
  _Section _firstAllowedSection() {
    // Primero el orden REAL del menú (lo fija la BD y ya viene filtrado por
    // permisos); si todavía no hay menú dibujado, el orden del panel.
    for (final s in _menuOrder) {
      if (s != null && _canSee(_kSectionKeys[s] ?? '')) return s;
    }
    for (final entry in _kSectionKeys.entries) {
      if (_canSee(entry.value)) return entry.key;
    }
    return _Section.dashboard;
  }

  /// Elige con qué sección se ABRE la app: el primer módulo del menú que el rol
  /// puede ver (con el orden que manda la BD). Si todavía no hay permisos o el
  /// menú está vacío, se espera a la siguiente build.
  ///
  /// Se fija AQUÍ, dentro del build que ya tiene el menú armado (y antes de
  /// construir el cuerpo), no en un post-frame: el panel aparece DIRECTO en su
  /// módulo. Antes se dibujaba el Dashboard un frame y el usuario veía el salto
  /// de un módulo a otro (y su carga de datos a medias). El arranque se decide
  /// UNA vez ([_startPicked]): asignar el campo sin setState es seguro porque su
  /// efecto se usa más abajo, en este mismo build.
  void _pickStartSection(
    bool degraded,
    List<_Section?> menu,
    bool catalogReady,
  ) {
    if (_startPicked) return;
    if (degraded || !catalogReady || menu.isEmpty) return;
    _startPicked = true;
    _section = _firstAllowedSection();
    // Este es el módulo de INICIO: a él vuelve el atrás desde cualquier otro.
    _homeSection = _section;
  }

  /// Paso de ATRÁS del PANEL (el último de la cadena).
  ///
  /// En otro módulo, vuelve al módulo de inicio; ya en él, pregunta antes de
  /// salir. Las carpetas, la selección y las sub-vistas las atienden antes las
  /// propias pantallas (ver [BackNav]).
  bool _handleBack() {
    if (!mounted) return false;
    if (_section != _homeSection) {
      setState(() => _section = _homeSection);
      return true;
    }
    unawaited(_askExit());
    return true;
  }

  /// «¿Salir de la app?»: manda la app al segundo plano sin cerrar la sesión.
  Future<bool> _moveAppToBackground() async {
    if (kWeb || (!isAndroidPlatform && !isWindowsPlatform)) return false;
    try {
      return await const MethodChannel('hardstreet/app_background')
              .invokeMethod<bool>('moveToBackground') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _askExit() async {
    if (_askingExit) return;
    _askingExit = true;
    try {
      final leave = await confirmExitApp(context);
      if (leave && mounted) {
        final moved = await _moveAppToBackground();
        if (!moved && mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('No se pudo enviar la app al segundo plano.'),
            ),
          );
        }
      }
    } finally {
      _askingExit = false;
    }
  }

  /// Abre el MÓDULO al que lleva un aviso de la campanita.
  ///
  /// El backend manda `target` con la clave del módulo (`print`, `schedules`,
  /// `my_package`, `clients`…). Si el rol no puede verlo, no se mueve nada:
  /// el aviso ya quedó marcado como leído.
  void _openNotificationTarget(String target) {
    final map = <String, _Section>{
      'notifications': _Section.notifications,
      'schedules': _Section.agendas,
      'my_package': _Section.clientDashboard,
      'print': _Section.prints,
      'clients': _Section.clients,
      'packages': _Section.packages,
      'finance': _Section.finance,
      'drive': _Section.drive,
      'shared_files': _Section.sharedFiles,
      'settings': _Section.settings,
    };
    final section = map[target.trim().toLowerCase()];
    if (section == null || section == _section) return;
    if (!_canSee(_kSectionKeys[section] ?? '')) return;
    setState(() => _section = section);
  }

  /// ¿Se muestra el módulo [name]? Exige "Ver" (read) según la BD, TAMBIÉN
  /// para Admin (si su rol no tiene "Ver" en un módulo, desaparece).
  /// Sin datos (backend viejo / sin conexión) el menú queda completo.
  bool _canSee(String module) {
    // CONEXIÓN: SOLO el Superadministrador (usuario 1, rol Superadmin).
    //
    // Desde ahí se agregan y quitan servidores del Drive, se reinicia su
    // servicio, se lee su terminal y se le suben archivos al proyecto. El
    // backend ya lo exige por su cuenta; aquí se quita del menú para que
    // nadie más vea una pantalla que le va a responder 403.
    if (module == 'connection') return HsSession.isSuperAdmin;
    return HsAccess.instance.degraded || HsAccess.instance.canSee(module);
  }

  /// Como [_canSee], pero además muestra los módulos que el backend TODAVÍA
  /// no registra (migración pendiente): una función nueva no desaparece del
  /// menú solo porque falte el SQL. En cuanto la BD los tiene, mandan los
  /// permisos normales.
  bool _showModule(String module) =>
      _canSee(module) || !HsAccess.instance.knows(module);

  /// Igual que [_showModule], salvo los módulos que dependen de una migración
  /// reciente (Actividad, Archivos compartidos): esos solo aparecen si el rol
  /// tiene "Ver" de verdad, para no ofrecer una pantalla que el backend va a
  /// rechazar.
  bool _visibleModule(String module) =>
      (module == 'activity' ||
          module == 'shared_files' ||
          module == 'print' ||
          // Notas: sin la migración aplicada el backend responde 403.
          module == 'notes' ||
          // Notificaciones exige su permiso real: sin la migración aplicada
          // no se ofrece una pantalla que el backend va a rechazar.
          module == 'notifications' ||
          // Empresas es SOLO del Superadministrador: no se ofrece "por si la
          // migración falta".
          module == 'companies')
      ? _canSee(module)
      : _showModule(module);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final access = HsAccess.instance;

    // ARRANQUE: mientras no se conocen los permisos NO se dibuja ningún módulo.
    // De ellos depende el menú Y con qué módulo abre la app; antes el Dashboard
    // se dibujaba con los permisos aún cargando, empezaba a pedir sus datos y al
    // llegar la respuesta la app saltaba al primer módulo permitido: ese cambio
    // de módulo no se debe ver. La pantalla de carga tapa ese momento.
    if (access.loading) return const PanelLoadingScreen();
    // Tampoco se dibuja el panel completo si los permisos no se pudieron leer
    // (sin conexión): mostrar todos los módulos como si el rol pudiera verlos es
    // peor que decirlo claro y ofrecer reintentar.
    if (access.degraded) {
      return PanelNoConnectionScreen(onRetry: _loadPermissions);
    }

    // Destinos visibles según permisos REALES del rol (HsAccess). TODOS exigen
    // "Ver" sobre su módulo — con el nombre EXACTO de la tabla modules
    // (Conexión, Configuraciones y Reportes incluidos: también son módulos con
    // permisos y por ahora solo ofrecen "Ver").
    final all = <(AdminDestination, _Section?, String)>{
      (
        const AdminDestination(
          icon: Icons.space_dashboard_outlined,
          label: 'Dashboard',
          header: AdminDestination.headerNone,
        ),
        _Section.dashboard,
        'Dashboard',
      ),
      // EMPRESAS: solo el Superadministrador. Cada empresa encierra sus
      // agendas, finanzas, archivos, paquetes, usuarios y sitio web.
      (
        const AdminDestination(
          icon: Icons.apartment_outlined,
          label: 'Empresas',
          header: 'Administración',
        ),
        _Section.companies,
        'Empresas',
      ),
      (
        const AdminDestination(
          icon: Icons.workspace_premium_outlined,
          label: 'Mi paquete',
          header: AdminDestination.headerNone,
        ),
        _Section.clientDashboard,
        'Mi paquete',
      ),
      (
        const AdminDestination(
          icon: Icons.folder_copy_outlined,
          label: 'Archivos',
          header: 'Operación',
        ),
        _Section.drive,
        'Archivos',
      ),
      (
        const AdminDestination(
          icon: Icons.folder_shared_outlined,
          label: 'Archivos compartidos',
          header: 'Operación',
        ),
        _Section.sharedFiles,
        'Archivos compartidos',
      ),
      (
        const AdminDestination(
          icon: Icons.event_available_outlined,
          label: 'Agendas',
          header: AdminDestination.headerNone,
        ),
        _Section.agendas,
        'Agendas',
      ),
      // NOTAS: bloc personal (texto, listas de actividades y dibujo).
      (
        const AdminDestination(
          icon: Icons.sticky_note_2_outlined,
          label: 'Notas',
          header: AdminDestination.headerNone,
        ),
        _Section.notes,
        'Notas',
      ),
      (
        const AdminDestination(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Finanzas',
          header: 'Dinero',
        ),
        _Section.finance,
        'Finanzas',
      ),
      (
        const AdminDestination(
          icon: Icons.sd_storage_outlined,
          label: 'Almacenamiento',
          header: 'Operación',
        ),
        _Section.storage,
        'Almacenamiento',
      ),
      (
        const AdminDestination(
          icon: Icons.print_outlined,
          label: 'Impresiones',
          header: 'Operación',
        ),
        _Section.prints,
        'Impresiones',
      ),
      (
        const AdminDestination(
          icon: Icons.lan_outlined,
          label: 'Conexión',
          header: AdminDestination.headerNone,
        ),
        _Section.connection,
        'Conexión',
      ),
      (
        const AdminDestination(
          icon: Icons.people_alt_outlined,
          label: 'Usuarios',
          header: 'Administración',
        ),
        _Section.users,
        'Usuarios',
      ),
      (
        const AdminDestination(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Roles',
          header: AdminDestination.headerNone,
        ),
        _Section.roles,
        'Roles',
      ),
      // AVISOS: qué roles reciben cada notificación y envío manual de avisos.
      (
        const AdminDestination(
          icon: Icons.notifications_active_outlined,
          label: 'Notificaciones',
          header: AdminDestination.headerNone,
        ),
        _Section.notifications,
        'Notificaciones',
      ),
      (
        const AdminDestination(
          icon: Icons.badge_outlined,
          label: 'Clientes',
          header: AdminDestination.headerNone,
        ),
        _Section.clients,
        'Clientes',
      ),
      (
        const AdminDestination(
          icon: Icons.card_giftcard_outlined,
          label: 'Paquetes',
          header: AdminDestination.headerNone,
        ),
        _Section.packages,
        'Paquetes',
      ),
      (
        const AdminDestination(
          icon: Icons.miscellaneous_services_outlined,
          label: 'Servicios',
          header: AdminDestination.headerNone,
        ),
        _Section.services,
        'Servicios',
      ),
      (
        const AdminDestination(
          icon: Icons.history_rounded,
          label: 'Actividad',
          header: AdminDestination.headerNone,
        ),
        _Section.activity,
        'Actividad',
      ),
      // Diseñador de la página web (portada). SOLO para Windows: en móvil y en
      // la web del panel el destino no se ofrece (el backend ya lo exige con el
      // permiso del módulo "Sitio web").
      if (siteModuleSupported())
        (
          const AdminDestination(
            icon: Icons.language_rounded,
            label: 'Sitio web',
            header: 'Administración',
          ),
          _Section.site,
          kSiteModuleName,
        ),
      (
        const AdminDestination(
          icon: Icons.settings_outlined,
          label: 'Configuraciones',
          header: AdminDestination.headerNone,
        ),
        _Section.settings,
        'Configuraciones',
      ),
      (
        const AdminDestination(
          icon: Icons.assessment_outlined,
          label: 'Reportes',
          header: AdminDestination.headerNone,
        ),
        _Section.reports,
        'Reportes',
      ),
    };
    // CATEGORÍAS + ORDEN desde la BD (modules.module_categories): los módulos
    // SUELTOS (sin categoría, como Dashboard) van primero; luego cada
    // categoría por su `order` (menor = arriba) con sus módulos por `order`.
    // Sin datos del backend se conserva el orden y los encabezados de siempre.
    final useCatalog = !access.degraded && access.catalog.isNotEmpty;

    final allList = all.toList();
    // La CLAVE (`modules.module`) es la identidad del módulo: con ella se
    // consultan permisos, nombre y categoría, aunque el nombre visible cambie.
    final entries = <(int, _Section?, String, AdminDestination)>[
      for (var i = 0; i < allList.length; i++)
        if (allList[i].$2 != null &&
            _visibleModule(_kSectionKeys[allList[i].$2] ?? ''))
          (i, allList[i].$2, _kSectionKeys[allList[i].$2] ?? '', allList[i].$1),
    ];

    if (useCatalog) {
      entries.sort((a, b) {
        final ma = access.metaOf(a.$3);
        final mb = access.metaOf(b.$3);
        // Sueltos primero (rank 0), luego las categorías por su orden.
        final ca = ma?.categoryOrder ?? 0;
        final cb = mb?.categoryOrder ?? 0;
        if (ca != cb) return ca - cb;
        // Dentro de la categoría, por el `order` del módulo (menor primero).
        final oa = ma?.order ?? 1 << 30;
        final ob = mb?.order ?? 1 << 30;
        if (oa != ob) return oa - ob;
        return a.$1 - b.$1; // empate: orden original (estable)
      });
    }

    final destinations = <AdminDestination>[];
    final visibleSections = <_Section?>[];
    String? prevCategory;
    for (final (_, section, module, dest) in entries) {
      String? header;
      if (useCatalog) {
        final category = (access.metaOf(module)?.categoryName ?? '').trim();
        if (category.isNotEmpty) {
          // Encabezado solo al ABRIR una categoría nueva.
          if (category != prevCategory) header = category;
          prevCategory = category;
        }
      } else {
        header = dest.header; // modo degradado: encabezados estáticos
      }
      final fallback = section == null
          ? dest.label
          : (_kSectionModules[section] ?? dest.label);
      destinations.add(
        AdminDestination(
          icon: dest.icon,
          // NOMBRE desde `modules.name`; el de siempre solo si la BD aún no
          // lo reporta.
          label: access.nameOf(module, fallback: fallback),
          header: header ?? AdminDestination.headerNone,
        ),
      );
      visibleSections.add(section);
    }
    // El menú ya está armado: con él se decide el arranque (y el respaldo si
    // los permisos cambian). `useCatalog` evita elegir con un menú incompleto
    // mientras el catálogo de módulos todavía no llega.
    _menuOrder = visibleSections;
    _pickStartSection(access.degraded, visibleSections, useCatalog);

    final driveIsActive = _section == _Section.drive;
    if (driveIsActive && !_driveWasActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _section == _Section.drive) {
          unawaited(_loadDriveScope());
        }
      });
    }
    _driveWasActive = driveIsActive;

    Widget body;
    switch (_section) {
      case _Section.dashboard:
        body = DashboardPage(
          drive: _drive,
          // Accesos rápidos del dashboard: cambian de sección si el usuario
          // tiene permiso de ver ese módulo.
          onNavigate: (key) {
            final map = {
              'drive': _Section.drive,
              'agendas': _Section.agendas,
              'finance': _Section.finance,
              'clients': _Section.clients,
              'packages': _Section.packages,
              'roles': _Section.roles,
            };
            final target = map[key];
            if (target == null) return;
            final visible = switch (target) {
              _Section.drive => _canSee('drive'),
              _Section.clients => _canSee('clients'),
              _Section.packages => _canSee('packages'),
              _Section.agendas => _canSee('schedules'),
              _Section.finance => _canSee('finance'),
              _Section.roles => _canSee('rols'),
              _ => false,
            };
            if (visible) setState(() => _section = target);
          },
        );
        break;
      case _Section.clientDashboard:
        body = ClientDashboardPage(
          // "Entrar a mi Drive": si la liga del paquete apunta a ESTE drive,
          // entra a esa carpeta y salta a la sección Archivos.
          onOpenDrive: (segments) {
            // Se pasa por openPath: respeta el alcance del CLIENTE (una carpeta
            // de fuera de lo compartido lo dejaría en su raíz en vez de abrir
            // un listado vacío) y carga ESA carpeta (descarta lo que estaba a
            // la vista: si no, Archivos abriría con el contenido de otra).
            unawaited(_drive.openPath(segments));
            setState(() => _section = _Section.drive);
          },
        );
        break;
      case _Section.drive:
        body = DrivePage(
          drive: _drive,
          title: access.nameOf('drive', fallback: 'Archivos'),
        );
        break;
      case _Section.sharedFiles:
        body = const SharedFilesPage();
        break;
      case _Section.connection:
        body = ConnectionPage(driveApi: _drive as DriveApiService);
        break;
      case _Section.users:
        body = const UsersPage();
        break;
      case _Section.roles:
        body = const RolesPage();
        break;
      case _Section.notifications:
        body = const NotificationsPage();
        break;
      case _Section.packages:
        body = const PackagesPage();
        break;
      case _Section.services:
        body = const ServicesPage();
        break;
      case _Section.activity:
        body = const ActivityPage();
        break;
      case _Section.site:
        body = const SitePage();
        break;
      case _Section.storage:
        body = const StoragePage();
        break;
      case _Section.prints:
        body = const PrintPage();
        break;
      case _Section.clients:
        body = const ClientsPage();
        break;
      case _Section.agendas:
        body = const AgendasPage();
        break;
      case _Section.notes:
        body = const NotesPage();
        break;
      case _Section.finance:
        body = const FinancePage();
        break;
      case _Section.settings:
        // APARIENCIA (tema y color) + lo que el panel necesita a mano.
        body = const SettingsPage();
        break;
      case _Section.companies:
        body = CompaniesPage(onCompanyChanged: _onCompanyChanged);
        break;
      case _Section.reports:
        body = ComingSoonPage(
          module: 'reports',
          title: access.nameOf('reports', fallback: 'Reportes'),
          section: adminSections[3],
        );
        break;
    }

    final shell = AdminShell(
      title: access.nameOf(
        _kSectionKeys[_section] ?? '',
        fallback: _kSectionModules[_section] ?? 'Dashboard',
      ),
      selectedIndex: () {
        // Índice DENTRO de los destinos visibles (el sidebar filtra módulos
        // sin permiso, así que el índice del enum ya no coincide).
        final i = visibleSections.indexOf(_section);
        return i < 0 ? 0 : i;
      }(),
      destinations: destinations,
      onSelect: (i) {
        setState(() {
          _section = (i >= 0 && i < visibleSections.length)
              ? (visibleSections[i] ?? _Section.dashboard)
              : _Section.dashboard;
        });
        if (_sidebarOpen) _sidebarOpen = false;
      },
      // La empresa activa del Superadministrador cambia el CONTEXTO de todos
      // los módulos: la llave remonta la página para que vuelva a pedir sus
      // datos con la empresa nueva.
      // Cambia solo al cambiar la empresa. Minimizar y restaurar conserva la
      // vista y el estado de cada módulo.
      body: KeyedSubtree(
        key: ValueKey('company-${HsSession.activeCompanyId ?? 0}-$_companyEpoch'),
        child: body,
      ),
      companySelector: CompanySelector(onChanged: _onCompanyChanged),
      updateBanner: widget.updateBanner,
      dark: widget.dark,
      onToggleTheme: widget.onToggleTheme,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      sidebarOpen: _sidebarOpen,
      isCompact: compact,
      userMenu: _UserMenu(onLogout: widget.onLogout),
      onOpenNotification: _openNotificationTarget,
    );
    // ATRÁS del sistema o del NAVEGADOR: se atiende SIEMPRE aquí (canPop
    // false), nunca deja que el navegador cierre la app por su cuenta. La
    // cadena decide: deseleccionar → carpeta padre → sub-vista → módulo de
    // inicio → «¿Salir?». En la web el motor convierte el atrás del navegador
    // en esta misma llamada (mantiene su entrada de historial), así que el
    // gesto del celular y el botón del navegador se comportan igual.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        BackNav.handle();
      },
      child: shell,
    );
  }
}

/// Banner discreto NO bloqueante: "hay una versión nueva disponible".
/// Se puede cerrar y no interfiere con el trabajo del panel.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.latestVersion,
    required this.currentVersion,
    required this.notes,
    required this.onDownload,
    required this.onClose,
  });

  final String latestVersion;
  final String currentVersion;
  final String notes;
  final Future<void> Function() onDownload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: .10),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: 'Actualización disponible ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: '(v$latestVersion · tienes v$currentVersion)',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (notes.isNotEmpty)
                        TextSpan(
                          text: ' — $notes',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onDownload,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Descargar'),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menú de usuario con cierre de sesión.
class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      offset: const Offset(0, 44),
      onSelected: (v) {
        if (v == 'logout') onLogout();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: .15),
                child: Icon(Icons.person, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      HsSession.displayName.isEmpty
                          ? 'Admin'
                          : HsSession.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      (HsSession.user?['email'] ?? '').toString().isEmpty
                          ? 'admin@hardstreet.app'
                          : (HsSession.user?['email'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 8),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: scheme.primary.withValues(alpha: .15),
          child: Icon(Icons.person, size: 18, color: scheme.primary),
        ),
      ),
    );
  }
}
