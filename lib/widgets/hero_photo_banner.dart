import 'dart:async';

import 'package:flutter/material.dart';

/// BANNER de fotos que van cambiando con un FUNDIDO.
///
/// Detalles que importan (portada de «Mi paquete»):
///
/// * Cada foto ocupa TODO el espacio del banner ([SizedBox.expand]): no se
///   respeta la proporción de la foto, se recorta al centro (la foto la pinta
///   [builder], que debe usar «cover»). Así una foto vertical y una horizontal
///   llenan igual el banner.
/// * La foto que se va queda ABAJO, opaca, y la siguiente entra ENCIMA con el
///   fundido. Nunca hay dos fotos a media opacidad al mismo tiempo, que era lo
///   que hacía que el fondo del banner asomara y pareciera que \"quitan\" la
///   imagen un instante.
/// * Cuando el fundido termina, la capa de abajo se pone al día por debajo de
///   la de arriba (ya opaca), así el cambio no se ve.
/// * Si una foto tarda en cargar, la anterior sigue viéndose hasta que la nueva
///   aparece: el banner nunca queda en blanco.
/// * [background] se pinta SIEMPRE debajo (la foto del paquete). Así, mientras
///   las fotos de la carpeta se están bajando, el banner sigue enseñando la
///   foto del paquete en vez de quedarse vacío.
class HeroPhotoBanner extends StatefulWidget {
  const HeroPhotoBanner({
    super.key,
    required this.photos,
    required this.builder,
    this.background,
    this.every = const Duration(seconds: 5),
    this.fade = const Duration(milliseconds: 1200),
  });

  /// Fotos a rotar. Con una sola (o ninguna) no hay rotación.
  final List<String> photos;

  /// Lo que se ve debajo de todo (y cuando no hay fotos que rotar).
  final Widget? background;

  /// Pinta la foto de [url] llenando el espacio que se le da.
  final Widget Function(BuildContext context, String url) builder;

  /// Cada cuánto entra la siguiente foto.
  final Duration every;

  /// Lo que dura el fundido de entrada.
  final Duration fade;

  @override
  State<HeroPhotoBanner> createState() => _HeroPhotoBannerState();
}

class _HeroPhotoBannerState extends State<HeroPhotoBanner>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _fade;
  int _index = 0;

  /// Qué foto está en la capa de ABAJO (siempre opaca). Empieza en la primera:
  /// así el árbol no cambia de forma en el primer cambio (no se vuelve a montar
  /// la imagen y no hay parpadeo).
  int _base = 0;

  List<String> get _photos => widget.photos;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: widget.fade)
      ..addStatusListener(_onFadeStatus);
    _sync();
  }

  /// El fundido terminó: la foto nueva queda también abajo, ya tapada por la
  /// de arriba (que está opaca), así el siguiente cambio no descubre un hueco.
  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _base = _index);
  }

  @override
  void didUpdateWidget(covariant HeroPhotoBanner old) {
    super.didUpdateWidget(old);
    if (old.fade != widget.fade) _fade.duration = widget.fade;
    // Otra ronda de fotos (otro paquete o una recarga): se empieza por la
    // primera y se reinicia el ritmo. La lista se compara por contenido porque
    // el padre la vuelve a crear en cada build.
    if (!_samePhotos(old.photos, widget.photos)) {
      _base = 0;
      _index = 0;
      _fade.value = 0;
      _sync();
    }
  }

  static bool _samePhotos(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (_photos.length < 2) return;
    _timer = Timer.periodic(widget.every, (_) {
      if (!mounted) return;
      _next();
    });
  }

  void _next() {
    if (_photos.length < 2) return;
    setState(() {
      _base = _index;
      _index = (_index + 1) % _photos.length;
    });
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final background = widget.background;
    if (photos.isEmpty) return background ?? const SizedBox.shrink();
    Widget layer(String url) =>
        SizedBox.expand(child: widget.builder(context, url));
    final current = photos[_index % photos.length];
    // El respaldo va SIEMPRE abajo: mientras una foto carga, se ve él.
    Widget stack(List<Widget> layers) =>
        Stack(fit: StackFit.expand, children: [?background, ...layers]);
    // Una sola foto: no hay nada que rotar (ni capas que montar).
    if (photos.length < 2) return stack([layer(current)]);
    // Dos capas SIEMPRE (el árbol no cambia de forma): abajo la foto que se
    // está viendo, arriba la que entra con el fundido.
    return stack([
      layer(photos[_base % photos.length]),
      FadeTransition(opacity: _fade, child: layer(current)),
    ]);
  }
}
