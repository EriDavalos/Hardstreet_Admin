import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// FONDO DE LA VISTA con la foto que se está viendo, DESENFOCADA.
///
/// Va DETRÁS de todo el contenido: no se pinta encima de ninguna tarjeta ni
/// alrededor de ellas (eso era el halo, que ensuciaba la portada). Aquí la
/// foto se estira a todo el espacio disponible y se desenfoca; encima lleva un
/// VELO del color del panel ([opacity]) para que el texto y el héroe del módulo
/// sigan leyéndose.
///
/// El cambio de foto entra con un FUNDIDO ([fade]): la nueva se funde encima de
/// la anterior, así al pasar de una foto a otra no hay un instante en blanco.
/// El ritmo lo marca quien la usa (el banner de la portada avisa qué foto se
/// está viendo); aquí solo se pinta.
class PhotoBackdrop extends StatelessWidget {
  const PhotoBackdrop({
    super.key,
    required this.image,
    this.blur = 38,
    this.fade = const Duration(milliseconds: 1200),
    this.opacity,
  });

  /// Foto de la que sale el fondo. Con `null` no se pinta NADA: la vista queda
  /// exactamente como estaba (sin velo).
  final ImageProvider? image;

  /// Radio del desenfoque (en píxeles lógicos).
  final double blur;

  /// Lo que tarda una foto en sustituir a la anterior.
  final Duration fade;

  /// Fuerza del velo (null = según el tema: en claro el panel ya es blanco y
  /// hace falta más, en oscuro la foto se aguanta con menos).
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final scrim = (dark ? AppColors.bgDark : AppColors.bgLight).withValues(
      alpha: opacity ?? (dark ? 0.90 : 0.95),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: fade,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            // La que entra se funde ENCIMA de la que se va (las dos llenan el
            // espacio): nunca se ve el fondo del panel a media transición.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            // La CLAVE es la foto (NetworkImage compara por URL): un rebuild
            // del padre con la misma foto no reinicia el fundido.
            child: _PhotoLayer(key: ValueKey(image), image: image, blur: blur),
          ),
        ),
        // El velo va por encima de la foto y por debajo del contenido.
        IgnorePointer(child: ColoredBox(color: scrim)),
      ],
    );
  }
}

class _PhotoLayer extends StatelessWidget {
  const _PhotoLayer({super.key, required this.image, required this.blur});

  final ImageProvider image;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          // `decal` deja transparentes los bordes: no se estira el último
          // píxel en una franja rara en los lados de la pantalla.
          tileMode: TileMode.decal,
        ),
        // Un poco de zoom para que el borde desenfocado no asome dentro del
        // recorte (si no, los cuatro lados quedaban medio difuminados).
        child: Transform.scale(
          scale: 1.12,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            // Si la foto falla, el fondo simplemente desaparece: se ve el
            // fondo normal del panel, sin recuadro de error.
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
