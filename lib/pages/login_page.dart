import 'package:flutter/material.dart';

import '../theme.dart';

/// Pantalla de inicio de sesión (demostración).
/// La autenticación real llegará cuando el backend de admin esté listo:
/// por ahora cualquier credencial entra al panel.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscure = true;
  bool _remember = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width > 860;

    final form = SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                Align(
                  child: _BrandBadge(size: 56, radius: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  'HardStreet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                'Bienvenido',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Inicia sesión para entrar al panel de administración.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.alternate_email, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => widget.onLogin(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Wrap: en pantallas muy angostas el botón pasa a otra línea
              // en lugar de desbordar.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _remember,
                          onChanged: (v) =>
                              setState(() => _remember = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Recordarme',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        _snack('Recuperación de contraseña: próximamente'),
                    child: const Text(
                      '¿Olvidaste tu contraseña?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.onLogin,
                child: const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: widget.onLogin,
                child: const Text('Ver el panel como invitado'),
              ),
              const SizedBox(height: 22),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.science_outlined,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Modo demostración: la autenticación real estará disponible próximamente. Puedes entrar con cualquier dato.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          // Fondo decorativo
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: isDark
                      ? [
                          const Color(0xFF0C111C),
                          AppColors.surfaceDark,
                        ]
                      : [
                          const Color(0xFFF7F9FC),
                          scheme.primary.withValues(alpha: .06),
                        ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: wide
                  ? _WideLayout(form: form)
                  : form,
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout ancho: panel de marca a la izquierda + formulario a la derecha.
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.form});

  final Widget form;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 0 : 2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 640),
        child: SizedBox(
          width: 940,
          height: 620,
          child: Row(
            children: [
              // Panel de marca
              Expanded(
                flex: 5,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.brand, AppColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Círculos decorativos
                      Positioned(
                        right: -60,
                        top: -60,
                        child: _circle(200, Colors.white.withValues(alpha: .08)),
                      ),
                      Positioned(
                        left: -40,
                        bottom: -80,
                        child: _circle(240, Colors.white.withValues(alpha: .06)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                _BrandBadge(size: 44, radius: 12),
                                SizedBox(width: 12),
                                Text(
                                  'HardStreet',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              'Administra todo\ndesde un solo lugar',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tu drive de archivos y, próximamente,\nusuarios, clientes y configuraciones.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .85),
                                height: 1.4,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _feature(Icons.folder_copy_outlined,
                                'Drive de archivos con carpetas e imágenes'),
                            _feature(Icons.people_alt_outlined,
                                'Gestión de usuarios y clientes'),
                            _feature(Icons.settings_outlined,
                                'Configuraciones y reportes'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Formulario
              Expanded(
                flex: 5,
                child: Center(child: form),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _feature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: .9), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .92),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brand, AppColors.brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: .35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.apartment_rounded, color: Colors.white, size: size * .58),
    );
  }
}
