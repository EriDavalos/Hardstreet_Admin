import 'package:flutter/material.dart';

import 'anim.dart';

/// Tarjeta con icono, título, descripción y botón principal.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onPrimary,
    this.primaryLabel,
    this.accent = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final bool accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent
                    ? scheme.primary.withValues(alpha: .12)
                    : scheme.surfaceContainerHighest.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent ? scheme.primary : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            if (primaryLabel != null) ...[
              const Spacer(),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Contenedor de página estándar con título, descripción y contenido.
class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions,
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Entrada suave del encabezado y del contenido (moderno y fluido).
        FadeSlideIn(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              ...?actions,
            ],
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(delayMs: 90, child: child),
      ],
    );
  }
}

/// Estado vacío reutilizable.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
