import 'dart:async';

import 'package:flutter/material.dart';

import '../app_awake.dart';

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
/// * Con [preload] el fundido NO empieza hasta que la foto ya está descargada
///   (y decodificada) en la caché. Sin eso, el fundido corría a ciegas: si la
///   foto tardaba, la capa que entraba estaba vacía, se veía un instante la
///   foto del paquete y luego la nueva aparecía DE GOLPE, sin transición.
///   La primera foto también entra con fundido (si no, el primer cambio era un
///   salto).
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
    this.preload,
    this.onPhoto,
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

  /// Deja la foto lista (descargada y decodificada) ANTES de fundirla. Se le
  /// pide la de la vuelta y además se adelanta la siguiente. Que falle no
  /// rompe nada: el banner cambia igual (las capas ya tienen su respaldo).
  final Future<void> Function(String url)? preload;

  /// Avisa qué foto se está viendo, para que el padre pueda teñir el fondo
  /// con sus colores.
  final ValueChanged<String>? onPhoto;

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

  /// Ya se pidió la foto que va a entrar (evita dos esperas a la vez si el
  /// temporizador vuelve a tocar mientras la imagen viaja).
  bool _switching = false;

  List<String> get _photos => widget.photos;

  /// Las dos capas del banner: abajo la foto que se ve, arriba la que entra.
  /// Con una sola foto también son dos (la de arriba arranca invisible y entra
  /// con el fundido cuando la imagen ya está lista).
  bool get _fades => widget.preload != null;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: widget.fade)
      ..addStatusListener(_onFadeStatus);
    _sync();
    if (_fades) {
      _fade.value = 0;
      _startIntro();
    } else {
      _notifyLater();
    }
  }

  /// La PRIMERA foto entra con el mismo fundido. Sin esto, mientras la foto de
  /// la carpeta se descargaba se veía la del paquete y después la nueva
  /// aparecía de golpe.
  void _startIntro() {
    final preload = widget.preload;
    if (preload == null || _photos.isEmpty) return;
    final url = _photos.first;
    _fade.value = 0;
    unawaited(() async {
      try {
        await preload(url);
      } catch (_) {
        // Sin foto: el banner se queda con la del paquete.
      }
      if (!mounted) return;
      _fade.forward(from: 0);
      // Ya se está viendo: ahora sí se avisa (el fondo no se tiñe con una foto
      // que todavía no ha aparecido).
      widget.onPhoto?.call(url);
    }());
  }

  /// El fundido terminó: la foto nueva queda también abajo, ya tapada por la
  /// de arriba (que está opaca), así el siguiente cambio no descubre un hueco.
  /// De paso se adelanta la descarga de la que sigue.
  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _base = _index);
    _ahead();
  }

  /// Adelanta la SIGUIENTE foto: cuando le toque, el fundido empieza al
  /// instante en vez de esperar a que baje.
  void _ahead() {
    final preload = widget.preload;
    if (preload == null || _photos.length < 2) return;
    final url = _photos[(_index + 1) % _photos.length];
    unawaited(() async {
      try {
        await preload(url);
      } catch (_) {
        // Se reintenta cuando toque el turno.
      }
    }());
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
      _switching = false;
      _fade.value = 0;
      _sync();
      if (_fades) {
        _startIntro();
      } else {
        _notifyLater();
      }
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
      // Con la app en segundo plano las fotos no se cambian: no hay quien las
      // mire y cada cambio pide una imagen (ver [AppAwake]). Al volver, la
      // sección se recarga entera.
      if (!AppAwake.instance.awake) return;
      _next();
    });
  }

  /// Avisa de la foto visible al terminar el frame (montar el banner no puede
  /// disparar el setState del padre).
  void _notifyLater() {
    final notify = widget.onPhoto;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _photos.isEmpty) return;
      notify(_photos[_index % _photos.length]);
    });
  }

  void _next() {
    if (_photos.length < 2 || _switching) return;
    final next = (_index + 1) % _photos.length;
    final preload = widget.preload;
    if (preload == null) {
      _show(next);
      return;
    }
    // Se espera a tener la foto lista: si tarda, la anterior sigue viéndose.
    _switching = true;
    final url = _photos[next];
    unawaited(() async {
      try {
        await preload(url);
      } catch (_) {
        // Se cambia igual: la capa nueva enseñará su respaldo y la foto
        // aparece cuando logre bajar.
      }
      if (!mounted) return;
      _switching = false;
      _show(next);
    }());
  }

  void _show(int next) {
    if (!mounted) return;
    setState(() {
      _base = _index;
      _index = next;
    });
    _fade.forward(from: 0);
    widget.onPhoto?.call(_photos[next % _photos.length]);
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
    // Una sola foto: no hay nada que rotar, pero sí que fundir la entrada.
    if (photos.length < 2) {
      final single = layer(current);
      if (!_fades) return stack([single]);
      return stack([FadeTransition(opacity: _fade, child: single)]);
    }
    // Dos capas SIEMPRE (el árbol no cambia de forma): abajo la foto que se
    // está viendo, arriba la que entra con el fundido.
    return stack([
      layer(photos[_base % photos.length]),
      FadeTransition(opacity: _fade, child: layer(current)),
    ]);
  }
}
