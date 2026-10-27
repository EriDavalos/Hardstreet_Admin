import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../app_settings.dart';
import '../drive_host.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';

// ==================================================================
// MÓDULO CONFIGURACIONES
// ==================================================================
// Antes era una página de "Próximamente". Ahora guarda la PERSONALIZACIÓN de
// la app, que se aplica al instante y se recuerda al reabrirla:
//
//   * TEMA: sistema / claro / oscuro.
//   * PALETA: el diseño entero (medianoche, zafiro, grafito, océano, esmeralda,
//     amatista, cobre). Cambia fondos, tarjetas, barra lateral y acento a la
//     vez: no hay un selector de color suelto que pueda desentonar.
//
// El cambio lo aplica [AppSettings] y la app escucha: el MaterialApp se
// reconstruye solo (no hay que reiniciar ni volver a entrar).
// ==================================================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return PageContainer(
      module: 'settings',
      title: 'Configuraciones',
      description:
          'Personaliza la app: el modo (claro/oscuro) y la paleta de diseño '
          'completa, que cambia fondos, tarjetas, barra lateral y acento.',
      icon: Icons.settings_rounded,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PopIn(
                    child: _SettingsCard(
                      icon: Icons.dark_mode_outlined,
                      title: 'Tema',
                      subtitle:
                          '«Sistema» sigue al teléfono o a la computadora',
                      child: _ThemePicker(
                        value: settings.themeMode,
                        onChanged: (m) => settings.setThemeMode(m),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PopIn(
                    delayMs: 40,
                    child: _SettingsCard(
                      icon: Icons.grid_view_rounded,
                      title: 'Paleta de diseño',
                      subtitle:
                          'Cambia la app entera: fondo, tarjetas, barra lateral '
                          'y acento',
                      child: _PalettePicker(
                        value: settings.palette,
                        onChanged: (key) => settings.setPalette(key),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PopIn(
                    delayMs: 60,
                    child: const _SettingsCard(
                      icon: Icons.equalizer_rounded,
                      title: 'Colores de los datos',
                      subtitle:
                          'Los colores con los que Almacenamiento separa cada '
                          'dato (archivos, carpetas, cuota y disco)',
                      child: _DataPalette(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PopIn(
                    delayMs: 90,
                    child: _SettingsCard(
                      icon: Icons.visibility_outlined,
                      title: 'Así se verá',
                      subtitle: 'Lo que cambia en el resto del panel',
                      child: const _Preview(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PopIn(delayMs: 120, child: _AboutCard()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta con icono, título, explicación y su control.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.brand),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Sistema / Claro / Oscuro.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});

  final HsThemeMode value;
  final ValueChanged<HsThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<HsThemeMode>(
        key: const ValueKey('settings-theme'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: HsThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined, size: 18),
            label: Text('Sistema'),
          ),
          ButtonSegment(
            value: HsThemeMode.light,
            icon: Icon(Icons.light_mode_outlined, size: 18),
            label: Text('Claro'),
          ),
          ButtonSegment(
            value: HsThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined, size: 18),
            label: Text('Oscuro'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (set) {
          if (set.isNotEmpty) onChanged(set.first);
        },
      ),
    );
  }
}

/// Las PALETAS COMPLETAS de diseño: cada tarjeta enseña cómo queda la app en
/// oscuro (mitad izquierda) y en claro (mitad derecha).
class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = HsPalette.byKey(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final p in HsPalette.all) _tile(context, p)],
        ),
        const SizedBox(height: 10),
        Text(
          'Paleta elegida: ${current.name}. Cambia el fondo, las tarjetas, la '
          'barra lateral y el acento de todas las pantallas.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, HsPalette p) {
    final scheme = Theme.of(context).colorScheme;
    final on = p.key == value;
    return InkWell(
      key: ValueKey('settings-palette-${p.key}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(p.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 176,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? p.accent : scheme.outlineVariant.withValues(alpha: .7),
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mini pantalla: izquierda OSCURA, derecha CLARA.
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                height: 54,
                child: Row(
                  children: [_mini(p.dark, p.accent), _mini(p.light, p.accent)],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (on)
                  Icon(Icons.check_circle_rounded, size: 16, color: p.accent),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              p.hint,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.25,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Media mini pantalla: barra lateral, una tarjeta y el acento.
  Widget _mini(HsSurfaces s, Color accent) => Expanded(
    child: Container(
      color: s.bg,
      padding: const EdgeInsets.fromLTRB(5, 7, 5, 7),
      child: Row(
        children: [
          Container(
            width: 8,
            decoration: BoxDecoration(
              color: s.sidebar,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: s.card,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: s.line, width: .6),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: s.card,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: s.line, width: .6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Paleta de los datos del módulo Almacenamiento.
///
/// No es una paleta aparte: son los MISMOS colores de [AppColors.accents]
/// (incluidos los nuevos ámbar, menta y cian), así que se pueden elegir como
/// acento y todo el panel sigue hablando el mismo idioma visual.
class _DataPalette extends StatelessWidget {
  const _DataPalette();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <(Color, String)>[
      (AppColors.dataFiles, 'Archivos'),
      (AppColors.dataFolders, 'Carpetas'),
      (AppColors.dataQuota, 'Cuota'),
      (AppColors.dataDisk, 'Disco'),
      (AppColors.dataFree, 'Libre'),
      (AppColors.danger, 'Alerta'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (color, label) in items)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: .28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          'Almacenamiento los usa para separar visualmente cada cifra. '
          'Acompañan al acento de la paleta elegida.',
          style: TextStyle(
            fontSize: 11,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Vista en vivo: lo que cambia con el tema y el color.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Botón principal'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Secundario'),
              ),
              Chip(
                avatar: Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: AppColors.brand,
                ),
                label: const Text('Seleccionado'),
                backgroundColor: AppColors.brand.withValues(alpha: .12),
                side: BorderSide(color: AppColors.brand.withValues(alpha: .35)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Una mini-pantalla: el encabezado y la tarjeta con el acento.
        Container(
          width: 190,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Módulo',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: .62,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'El acento pinta la selección y el progreso.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Datos de la app (versión y servidor) y un recordatorio de dónde se cambia
/// la conexión.
class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = DriveHost.custom ?? DriveHost.compiled;
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return _SettingsCard(
      icon: Icons.info_outline,
      title: 'Acerca de',
      subtitle: 'Lo que esta app tiene configurado',
      child: Column(
        children: [
          row(
            Icons.phone_iphone_outlined,
            'Versión',
            AppConstants.effectiveVersion,
          ),
          row(Icons.dns_outlined, 'Servidor', host),
          Text(
            'La dirección del servidor se cambia en el módulo Conexión; aquí '
            'se elige cómo se ve la app.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
