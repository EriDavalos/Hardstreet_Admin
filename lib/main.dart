import 'package:flutter/material.dart';

import 'drive_scope.dart';
import 'drive_service.dart';
import 'pages/admin_pages.dart';
import 'pages/drive_page.dart';
import 'pages/login_page.dart';
import 'theme.dart';
import 'widgets/admin_shell.dart';

void main() {
  runApp(const HardStreetAdminApp());
}

class HardStreetAdminApp extends StatefulWidget {
  const HardStreetAdminApp({super.key});

  @override
  State<HardStreetAdminApp> createState() => _HardStreetAdminAppState();
}

class _HardStreetAdminAppState extends State<HardStreetAdminApp> {
  bool _dark = false;
  bool _loggedIn = false;

  /// Reutiliza un DriveScope heredado si existe (útil en tests);
  /// si no, crea el servicio real de la app.
  DriveService? _injectedDrive;

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
        title: 'HardStreet Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: _loggedIn
            ? AdminHome(
                dark: _dark,
                onToggleTheme: () => setState(() => _dark = !_dark),
                onLogout: () => setState(() => _loggedIn = false),
              )
            : LoginPage(onLogin: () => setState(() => _loggedIn = true)),
      ),
    );
  }

  DriveService? _ownedDriveInstance;
  DriveService get _ownedDrive => _ownedDriveInstance ??= DriveService();
}

/// Índices de las secciones del panel.
enum _Section { dashboard, drive, users, clients, settings, reports }

class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    required this.dark,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  _Section _section = _Section.drive;
  bool _sidebarOpen = false;

  DriveService get _drive => DriveScope.of(context);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    final destinations = [
      AdminDestination(
        icon: Icons.space_dashboard_outlined,
        label: 'Dashboard',
        header: AdminDestination.headerNone,
      ),
      AdminDestination(
        icon: Icons.folder_copy_outlined,
        label: 'Archivos',
        header: 'Operación',
      ),
      AdminDestination(
        icon: Icons.people_alt_outlined,
        label: 'Usuarios',
        header: 'Administración',
      ),
      AdminDestination(
        icon: Icons.badge_outlined,
        label: 'Clientes',
        header: AdminDestination.headerNone,
      ),
      AdminDestination(
        icon: Icons.settings_outlined,
        label: 'Configuraciones',
        header: AdminDestination.headerNone,
      ),
      AdminDestination(
        icon: Icons.assessment_outlined,
        label: 'Reportes',
        header: AdminDestination.headerNone,
      ),
    ];

    final titles = {
      _Section.dashboard: 'Dashboard',
      _Section.drive: 'Archivos',
      _Section.users: 'Usuarios',
      _Section.clients: 'Clientes',
      _Section.settings: 'Configuraciones',
      _Section.reports: 'Reportes',
    };

    Widget body;
    switch (_section) {
      case _Section.dashboard:
        body = const DashboardPage();
        break;
      case _Section.drive:
        body = DrivePage(drive: _drive);
        break;
      case _Section.users:
        body = ComingSoonPage(
          title: 'Usuarios',
          section: adminSections[0],
        );
        break;
      case _Section.clients:
        body = ComingSoonPage(
          title: 'Clientes',
          section: adminSections[1],
        );
        break;
      case _Section.settings:
        body = ComingSoonPage(
          title: 'Configuraciones',
          section: adminSections[2],
        );
        break;
      case _Section.reports:
        body = ComingSoonPage(
          title: 'Reportes',
          section: adminSections[3],
        );
        break;
    }

    return AdminShell(
      title: titles[_section]!,
      selectedIndex: _section.index,
      destinations: destinations,
      onSelect: (i) {
        setState(() => _section = _Section.values[i]);
        if (_sidebarOpen) _sidebarOpen = false;
      },
      body: body,
      dark: widget.dark,
      onToggleTheme: widget.onToggleTheme,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      sidebarOpen: _sidebarOpen,
      isCompact: compact,
      userMenu: _UserMenu(onLogout: widget.onLogout),
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
              const Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Admin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'admin@hardstreet.app',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
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
