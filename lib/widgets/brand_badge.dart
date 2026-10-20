import 'package:flutter/material.dart';

import '../theme.dart';

/// Marca de HardStreet: el ICONO de la app (`assets/hs_icon.png`, el mismo con
/// el que se generan los iconos de Windows, Android y el navegador).
///
/// Vive aquí (y no dentro del login) porque la usan el panel, el login y la
/// animación de arranque, y así son EXACTAMENTE la misma pieza. Antes dibujaba
/// un icono de edificio (`Icons.apartment_rounded`) sobre el degradado azul;
/// ahora se enseña el icono de verdad, recortado con la misma esquina.
class BrandBadge extends StatelessWidget {
  const BrandBadge({
    super.key,
    required this.size,
    required this.radius,
    this.elevated = true,
  });

  /// Ruta del icono de la marca (declarado en pubspec.yaml).
  static const String iconAsset = 'assets/hs_icon.png';

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
        // El PNG del icono llena su cuadro (no trae esquinas transparentes),
        // así que el degradado de marca queda por detrás como respaldo: se ve
        // si el archivo faltara (y entonces aparece el icono de abajo).
        gradient: LinearGradient(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          iconAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // Si el archivo faltara, la app no se cae: se ve la marca dibujada.
          errorBuilder: (_, _, _) => Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: size * .58,
          ),
        ),
      ),
    );
  }
}
