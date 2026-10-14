import 'package:flutter/material.dart';

import '../theme.dart';

/// Marca de HardStreet: el cuadro con el degradado azul de la app y el icono
/// del estudio. Vive aquí (y no dentro del login) porque la usan tanto el
/// login como la animación de arranque, y así son EXACTAMENTE la misma pieza.
class BrandBadge extends StatelessWidget {
  const BrandBadge({
    super.key,
    required this.size,
    required this.radius,
    this.elevated = true,
  });

  final double size;
  final double radius;

  /// Sombra azulada suave (se apaga cuando la pieza ya está en movimiento).
  final bool elevated;

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
          if (elevated)
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
