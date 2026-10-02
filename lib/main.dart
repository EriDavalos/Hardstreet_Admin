import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_constants.dart';
import 'app_platform.dart';
import 'app_settings.dart';
import 'drive_api_service.dart';
import 'hs_access.dart';
import 'hs_api.dart';
import 'drive_base.dart';
import 'drive_scope.dart';
import 'image_memory.dart';
import 'pages/admin_pages.dart';
import 'pages/clients_page.dart';
import 'pages/connection_page.dart';
import 'pages/drive_page.dart';
import 'pages/login_page.dart';
import 'pages/packages_page.dart';
import 'pages/roles_page.dart';
import 'pages/users_page.dart';
import 'theme.dart';
import 'version_checker.dart';
import 'widgets/admin_shell.dart';
import 'widgets/force_update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      systemNavigationBarColor: isDark ? const Color(0xFF0C111C) : Colors.white,
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

  bool get _hasSession => HsSession.isLogged || _sessionRestored;

  @override
  void initState() {
    super.initState();
    // Límites de RAM para imágenes (+ poda del caché en disco, solo nativo:
    // en web no hay dart:io y ese caché no existe).
    ImageMemory.configure();
    if (!kWeb) ImageMemory.pruneDiskCache();
    // Sesión expirada (401 con "Recordarme"): regresar al login.
    HsApi.onUnauthorized = () {
      if (!mounted) return;
      setState(() {
        _loggedIn = false;
        _sessionRestored = false;
      });
    };
    // Configuraciones persistentes (modo oscuro + "Recordarme") — funciona
    // también en web. La app ESCUCHA los cambios: alternar el tema desde el
    // login o desde el panel reconstruye el MaterialApp al instante.
    AppSettings.instance.addListener(_onSettingsChanged);
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
    });
    // Chequeo periódico mientras la app siga abierta (por si el servidor
    // publica una versión nueva en caliente). En web/tests se omite.
    _versionTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => _checkVersion(),
    );
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _versionTimer?.cancel();
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
      final url = info.downloads[plat] ?? '';
      final fallback = info.downloads.values.firstWhere(
        (u) => u.isNotEmpty,
        orElse: () => '',
      );
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
    setState(() => _loggedIn = true);
  }

  /// Cerrar sesión: descarta el token en el servidor y borra lo persistido
  /// ("Recordarme"). Al volver, siempre pasa por el login.
  Future<void> _onLogout() async {
    await HsApi.logout(); // cortesía en el servidor
    await AppSettings.instance.clearSession();
    HsAccess.reset(); // el siguiente login recarga permisos desde cero
    _sessionRestored = false;
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
        themeMode: AppSettings.instance.dark ? ThemeMode.dark : ThemeMode.light,
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
          return ColoredBox(
            color: isDark ? const Color(0xFF0C111C) : Colors.white,
            child: SafeArea(
              bottom: false,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: _versionError
            ? _VersionErrorScreen(
                onRetry: () async {
                  setState(() => _versionError = false);
                  await _checkVersion();
                },
              )
            : _loggedIn || (_hasSession && AppSettings.instance.loaded)
            ? AdminHome(
                dark: AppSettings.instance.dark,
                onToggleTheme: () {
                  final v = !AppSettings.instance.dark;
                  AppSettings.instance.setDark(v); // persiste
                  setState(() {});
                },
                onLogout: _onLogout,
                updateBanner: _buildUpdateBanner(context),
              )
            : LoginPage(onLogin: _onLogin),
      ),
    );
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
        final url = info.downloads[plat] ?? info.downloads.values.first;
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      onClose: () => setState(() => _pendingUpdate = null),
    );
  }

  DriveApiService? _ownedDriveInstance;
  DriveApiService get _ownedDrive => _ownedDriveInstance ??= DriveApiService();
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

/// Índices de las secciones del panel.
enum _Section {
  dashboard,
  drive,
  connection,
  users,
  roles,
  clients,
  packages,
  settings,
  reports,
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
  // El DASHBOARD es la sección inicial del panel.
  _Section _section = _Section.dashboard;
  bool _sidebarOpen = false;

  DriveBase get _drive => DriveScope.of(context);

  @override
  void initState() {
    super.initState();
    HsAccess.addListener(_onAccessChanged);
    _loadPermissions();
    // Al guardar permisos en Roles: el menú se adapta AL INSTANTE.
    HsApi.onPermissionsChanged = () async {
      await _loadPermissions();
      // Si la sección actual dejó de ser visible, regresa a Archivos.
      if (!mounted) return;
      final canSee = switch (_section) {
        _Section.users => _canSee('Usuarios'),
        _Section.roles => _canSee('Roles'),
        _Section.clients => _canSee('Clientes'),
        _Section.packages => _canSee('Paquetes'),
        _Section.dashboard => _canSee('Dashboard'),
        _Section.drive => _canSee('Archivos'),
        _ => true,
      };
      if (!canSee) {
        setState(() {
          _section = _canSee('Archivos') ? _Section.drive : _Section.dashboard;
        });
      }
    };
  }

  @override
  void dispose() {
    HsApi.onPermissionsChanged = null;
    HsAccess.removeListener(_onAccessChanged);
    super.dispose();
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  /// Descarga los permisos del usuario (HsAccess) y refresca el menú.
  Future<void> _loadPermissions() async {
    await HsAccess.load();
    if (mounted) setState(() {});
  }

  /// ¿Se muestra el módulo [name]? Exige "Ver" (read) según la BD, TAMBIÉN
  /// para Admin (si su rol no tiene "Ver" en un módulo, desaparece).
  /// Sin datos (backend viejo / sin conexión) el menú queda completo.
  bool _canSee(String module) =>
      HsAccess.instance.degraded || HsAccess.instance.canSee(module);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    // Destinos visibles según permisos REALES del rol (HsAccess). Conexión
    // es herramienta técnica: siempre visible. Los demás exigen "Ver" sobre
    // su módulo — con el nombre EXACTO de la tabla modules.
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
          icon: Icons.lan_outlined,
          label: 'Conexión',
          header: AdminDestination.headerNone,
        ),
        _Section.connection,
        '',
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
    final destinations = [
      for (final (dest, _, module) in all)
        if (module.isEmpty || _canSee(module))
          AdminDestination(
            icon: dest.icon,
            label: dest.label,
            header: dest.header,
          ),
    ];

    // Seleccionable → sección real (respetando los módulos ocultos).
    final visibleSections = [
      for (final (_, section, module) in all)
        if (module.isEmpty || _canSee(module)) section,
    ];
    final titles = {
      _Section.dashboard: 'Dashboard',
      _Section.drive: 'Archivos',
      _Section.connection: 'Conexión',
      _Section.users: 'Usuarios',
      _Section.roles: 'Roles',
      _Section.clients: 'Clientes',
      _Section.packages: 'Paquetes',
      _Section.settings: 'Configuraciones',
      _Section.reports: 'Reportes',
    };

    Widget body;
    switch (_section) {
      case _Section.dashboard:
        body = DashboardPage(
          // Accesos rápidos del dashboard: cambian de sección si el usuario
          // tiene permiso de ver ese módulo.
          onNavigate: (key) {
            final map = {
              'drive': _Section.drive,
              'clients': _Section.clients,
              'packages': _Section.packages,
              'roles': _Section.roles,
            };
            final target = map[key];
            if (target == null) return;
            final visible = switch (target) {
              _Section.drive => _canSee('Archivos'),
              _Section.clients => _canSee('Clientes'),
              _Section.packages => _canSee('Paquetes'),
              _Section.roles => _canSee('Roles'),
              _ => false,
            };
            if (visible) setState(() => _section = target);
          },
        );
        break;
      case _Section.drive:
        body = DrivePage(drive: _drive);
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
      case _Section.packages:
        body = const PackagesPage();
        break;
      case _Section.clients:
        body = const ClientsPage();
        break;
      case _Section.settings:
        body = ComingSoonPage(
          title: 'Configuraciones',
          section: adminSections[2],
        );
        break;
      case _Section.reports:
        body = ComingSoonPage(title: 'Reportes', section: adminSections[3]);
        break;
    }

    return AdminShell(
      title: titles[_section]!,
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
      body: body,
      updateBanner: widget.updateBanner,
      dark: widget.dark,
      onToggleTheme: widget.onToggleTheme,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      sidebarOpen: _sidebarOpen,
      isCompact: compact,
      userMenu: _UserMenu(onLogout: widget.onLogout),
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
