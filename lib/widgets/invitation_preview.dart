import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../drive_base.dart' show driveImagePreview, drivePhotoUrl;
import '../hs_api.dart' show HsSession;
import '../invitation_components/component_catalog.dart';
import '../invitation_html.dart';
import '../invitation_model.dart';
import 'invitation_html_preview.dart';

class _CartaStageClipper extends CustomClipper<Path> {
  const _CartaStageClipper();

  @override
  Path getClip(Size size) =>
      Path()
        ..addRect(Rect.fromLTRB(0, -size.height * .8, size.width, size.height));

  @override
  bool shouldReclip(covariant _CartaStageClipper oldClipper) => false;
}

class _CartaFlapClipper extends CustomClipper<Path> {
  const _CartaFlapClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CartaRibbonClipper extends CustomClipper<Path> {
  const _CartaRibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * .82)
    ..lineTo(size.width / 2, size.height)
    ..lineTo(0, size.height * .82)
    ..close();

  @override
  bool shouldReclip(covariant _CartaRibbonClipper oldClipper) => false;
}

class _CartaFlapLinePainter extends CustomPainter {
  const _CartaFlapLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .055, size.height * .075)
      ..lineTo(size.width * .945, size.height * .075)
      ..lineTo(size.width / 2, size.height * .90);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CartaFlapLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Pliegues del sobre: las dos diagonales inferiores y la juntura central.
/// Son muy tenues para dar volumen sin competir con el sello ni el nombre.
class _CartaFoldPainter extends CustomPainter {
  const _CartaFoldPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final meeting = Offset(size.width / 2, size.height * .52);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(meeting.dx, meeting.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height)
        ..lineTo(meeting.dx, meeting.dy),
      stroke,
    );
    final seamRect = Rect.fromLTWH(
      size.width / 2 - .5,
      meeting.dy,
      1,
      size.height - meeting.dy,
    );
    canvas.drawRect(
      seamRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, color, Colors.transparent],
        ).createShader(seamRect),
    );
  }

  @override
  bool shouldRepaint(covariant _CartaFoldPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ==================================================================
// VISTA PREVIA DE UNA INVITACIÓN (Flutter)
// ==================================================================
// Es el MISMO modelo que genera el HTML de la liga pública
// (`invitation_html.dart`), así que lo que se ve aquí es lo que verá el
// cliente: portada de sobre con «Abrir invitación», polaroids, cuenta
// regresiva en vivo, familias, detalles, hashtag, itinerario y pie.
//
// En la app nativa la vista completa usa el HTML real dentro de un WebView;
// la maqueta Flutter queda para miniaturas y para pruebas/web. Los controles
// del editor se inyectan en ese mismo HTML, sin sustituir su diseño.
//
// `compact` es la MINIATURA de las tarjetas (listado y catálogo): solo el
// diseño, el nombre y la fecha, sin datos secundarios.
//
// `allowCover` añade el conmutador Portada / Invitación para revisar cómo se
// abre la invitación sin salir del editor.
// ==================================================================

class InvitationPreview extends StatefulWidget {
  const InvitationPreview({
    super.key,
    required this.invitation,
    this.compact = false,
    this.maxWidth = 460,
    this.allowCover = false,
    this.coverOnly = false,
    this.startAtCover = false,
    this.editable = false,
    this.selectedSection,
    this.onSelectSection,
    this.onEditSection,
    this.onRemoveSection,
    this.onDropComponent,
  });

  final Invitation invitation;

  /// Miniatura (tarjetas y catálogo).
  final bool compact;

  /// Ancho máximo de la invitación en la vista completa.
  final double maxWidth;

  /// ¿Se puede alternar entre la portada y la invitación?
  final bool allowCover;

  /// Muestra únicamente la portada (para el panel de la portada en el
  /// editor visual).
  final bool coverOnly;

  /// Empieza en el sobre, como la liga pública. En el editor se usa para la
  /// pestaña «Todo»; la pestaña «Invitación» abre directamente el contenido.
  final bool startAtCover;

  /// Modo edición: los bloques se pueden editar, quitar y reordenar. En la
  /// app nativa las acciones viven dentro del HTML real; en pruebas/web se
  /// usa la capa Flutter equivalente.
  final bool editable;
  final String? selectedSection;
  final ValueChanged<String>? onSelectSection;
  final ValueChanged<String>? onEditSection;
  final ValueChanged<String>? onRemoveSection;

  /// `new:families` inserta un componente; `move:details` lo reordena.
  final void Function(String payload, String? beforeKey)? onDropComponent;

  @override
  State<InvitationPreview> createState() => _InvitationPreviewState();
}

class _InvitationPreviewState extends State<InvitationPreview> {
  bool _cover = false;
  bool _coverOpening = false;
  Timer? _ticker;
  Timer? _coverTimer;

  @override
  void initState() {
    super.initState();
    _cover = widget.startAtCover;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant InvitationPreview old) {
    super.didUpdateWidget(old);
    if (old.startAtCover != widget.startAtCover) {
      _coverTimer?.cancel();
      _cover = widget.startAtCover;
      _coverOpening = false;
    }
    if (old.invitation.eventAt != widget.invitation.eventAt ||
        old.invitation.sections != widget.invitation.sections ||
        old.compact != widget.compact ||
        old.coverOnly != widget.coverOnly ||
        old.startAtCover != widget.startAtCover) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _coverTimer?.cancel();
    super.dispose();
  }

  /// La cuenta regresiva se mueve sola (como en la liga publicada).
  void _syncTicker() {
    final inv = widget.invitation;
    final live =
        !widget.compact &&
        !widget.coverOnly &&
        !widget.startAtCover &&
        inv.sectionOn('countdown') &&
        inv.eventDate != null &&
        inv.eventDate!.isAfter(DateTime.now());
    if (!live) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invitation;
    final t = inv.design;
    final accent = inv.accentColor;

    // En la app de escritorio y el celular la vista en grande es la
    // invitación REAL: el mismo HTML/CSS/JS que se guarda y se publica. En
    // el editor se le inyecta la capa de acciones, pero el documento y su
    // diseño siguen siendo los mismos. En pruebas y en la web se mantiene la
    // maqueta (no hay WebView nativo).
    if (!widget.compact && !isTestEnvironment && !kWeb) {
      final showEditor = widget.editable && !widget.coverOnly;
      final html = InvitationHtmlPreview(
        html: buildInvitationHtml(_forPreview(inv)),
        editor: showEditor,
        openAtStart: showEditor && !widget.startAtCover,
        onEditComponent: widget.onEditSection,
        onRemoveComponent: widget.onRemoveSection,
        onMoveComponent: (key, before) =>
            widget.onDropComponent?.call('move:$key', before),
      );

      final content = showEditor && widget.onDropComponent != null
          ? DragTarget<String>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) =>
                  widget.onDropComponent!(details.data, null),
              builder: (context, candidate, rejected) => Stack(
                fit: StackFit.expand,
                children: [
                  html,
                  if (candidate.isNotEmpty)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .10),
                          border: Border.all(color: accent, width: 2),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Suelta para insertar al final',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accent.computeLuminance() > .45
                                    ? const Color(0xFF201B18)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : html;

      // «Todo» y la portada no llevan el conmutador de Flutter: el propio
      // documento ya empieza en el sobre y lo abre al tocarlo.
      if (widget.coverOnly ||
          !widget.editable ||
          !widget.allowCover ||
          widget.startAtCover) {
        return content;
      }

      return Column(
        children: [
          _coverToggle(accent),
          Expanded(child: content),
        ],
      );
    }

    if (widget.compact) return _compact(inv, t, accent);

    final hasCover =
        inv.sectionOn('cover') &&
        inv.displayTitle.trim().isNotEmpty &&
        t.cover != 'abierta';
    final showCover =
        hasCover && (widget.coverOnly || (widget.allowCover && _cover));

    return Column(
      children: [
        if (hasCover && widget.allowCover && !widget.coverOnly)
          _coverToggle(accent),
        Expanded(
          child: showCover
              ? _coverView(inv, t, accent)
              : _invitationView(inv, t, accent),
        ),
      ],
    );
  }

  /// La invitación con las fotos pedidas usando el TOKEN de la sesión.
  ///
  /// El HTML que se publica lleva la URL pública (`/files/…`, sin token),
  /// pero una foto recién elegida todavía no se ha hecho pública: el
  /// navegador la pedía sin permiso y la polaroid se quedaba en blanco. La
  /// vista previa usa la miniatura del servidor (`/thumb/…?apikey=…`), que sí
  /// la abre, y el token NUNCA se guarda porque este HTML es solo local.
  Invitation _forPreview(Invitation inv) {
    final token = (HsSession.token ?? '').trim();
    if (token.isEmpty) return inv;
    return inv.copyWith(
      photos: [
        for (final p in inv.photos)
          driveImagePreview(p, token: token, width: 1200),
      ],
      bgMedia: inv.bgMedia.trim().isEmpty
          ? inv.bgMedia
          : drivePhotoUrl(inv.bgMedia, token: token),
      detailsMedia: inv.detailsMedia.trim().isEmpty
          ? inv.detailsMedia
          : drivePhotoUrl(inv.detailsMedia, token: token),
    );
  }

  // ---------------------------------------------------------------
  // Miniatura
  // ---------------------------------------------------------------
  Widget _compact(Invitation inv, InvitationTemplate t, Color accent) {
    final occasion = (inv.occasion.trim().isEmpty ? t.occasion : inv.occasion)
        .toUpperCase();
    final photo = inv.photos.isEmpty ? '' : inv.photos.first;

    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          occasion,
          style: TextStyle(
            fontSize: 6.8,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          inv.displayTitle,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: _displayFamily(inv.fontKey),
            fontSize: 21,
            height: 1,
            fontStyle: inv.fontKey == 'romantica'
                ? FontStyle.italic
                : FontStyle.normal,
            color: t.ink,
          ),
        ),
        if (t.ornament != 'ninguno') ...[
          const SizedBox(height: 6),
          _Ornament(color: accent, width: 34),
        ],
        if (inv.dateText.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            inv.dateText.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 7.2, letterSpacing: .6, color: t.soft),
          ),
        ],
      ],
    );

    // La tarjeta cambia de forma según la plantilla: panel redondeado, hoja
    // con doble marco o texto directo sobre el fondo.
    Widget card;
    if (t.card == 'papel') {
      card = Container(
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: accent.withValues(alpha: .22)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: body,
        ),
      );
    } else if (t.card == 'plano') {
      card = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: body,
      );
    } else {
      card = Container(
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: .40)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: body,
      );
    }

    final showPhoto = t.cover == 'foto' && photo.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.bgAlt, t.bg],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.card == 'panel' ? 10 : 3),
        child: showPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _photo(photo),
                  ColoredBox(color: t.bg.withValues(alpha: .58)),
                  Center(child: card),
                ],
              )
            : card,
      ),
    );
  }

  // ---------------------------------------------------------------
  // Conmutador Portada / Invitación
  // ---------------------------------------------------------------
  Widget _coverToggle(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toggleChip('Invitación', !_cover, accent, () {
            _coverTimer?.cancel();
            setState(() {
              _cover = false;
              _coverOpening = false;
            });
          }),
          const SizedBox(width: 8),
          _toggleChip('Portada', _cover, accent, () {
            _coverTimer?.cancel();
            setState(() {
              _cover = true;
              _coverOpening = false;
            });
          }),
        ],
      ),
    );
  }

  Widget _toggleChip(
    String label,
    bool selected,
    Color accent,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? accent.withValues(alpha: .18)
          : scheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _startCoverOpen() {
    if (_coverOpening) return;
    _coverTimer?.cancel();
    setState(() => _coverOpening = true);
    _coverTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() {
        _cover = false;
        _coverOpening = false;
      });
    });
  }

  /// Hilo fino con rombo central: el divisor de la carta.
  Widget _cartaOrnament(Color accent, {double width = 30, double gap = 5}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: width,
          height: 1,
          color: accent.withValues(alpha: .36),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gap),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 3.4,
              height: 3.4,
              color: accent.withValues(alpha: .68),
            ),
          ),
        ),
        Container(
          width: width,
          height: 1,
          color: accent.withValues(alpha: .36),
        ),
      ],
    );
  }

  // La portada Carta es un sobre horizontal cerrado sobre una mesa de
  // novia. La carta vertical vive dentro: al tocarlo, la solapa gira y la
  // carta asoma por el borde superior sin quedar encima del frente. El resto
  // de la invitación aparece con el mismo temporizador de siempre.
  Widget _cartaCoverView(Invitation inv, InvitationTemplate t, Color accent) {
    final event = inv.eventDate;
    final parts = event == null ? null : invitationDateParts(event);
    final dateLabel = parts == null
        ? inv.dateText.trim()
        : '${_cap(parts.weekday).toUpperCase()} ${parts.day} · '
              '${_cap(parts.month).toUpperCase()} ${parts.year}';
    final title = inv.displayTitle.trim().isEmpty
        ? 'Para ti'
        : inv.displayTitle.trim();
    final label = inv.envelopeText.trim().isEmpty
        ? 'Tienes una invitación'
        : inv.envelopeText.trim();
    final initials = inv.displayTitle
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    final paper = Color.lerp(Colors.white, t.panel, .30)!;
    final paperDeep = Color.lerp(paper, t.bg, .30)!;
    final deep = Color.lerp(Color.lerp(t.bg, accent, .28)!, Colors.black, .4)!;
    final serif = _displayFamily(inv.fontKey);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * .74).clamp(220.0, 420.0).toDouble();
    final cardHeight = cardWidth / 1.55;
    final flapHeight = cardHeight * .46;
    final letterWidth = cardWidth * .58;
    final rotation = -45 * math.pi / 180;
    final rotatedWidth =
        cardWidth * math.cos(rotation).abs() +
        cardHeight * math.sin(rotation).abs();
    final rotatedHeight =
        cardWidth * math.sin(rotation).abs() +
        cardHeight * math.cos(rotation).abs();
    final ctaInk = accent.computeLuminance() > .45
        ? const Color(0xFF2C2520)
        : Colors.white;
    final tint = switch (inv.coverBackdropKey) {
      'jardin' => const Color(0xFF6F8060).withValues(alpha: .10),
      'seda' => const Color(0xFFCEAA7E).withValues(alpha: .10),
      _ => Colors.transparent,
    };

    final card = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: rotation, end: rotation),
      duration: const Duration(milliseconds: 1),
      builder: (context, angle, child) =>
          Transform.rotate(angle: angle, child: child),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipPath(
            clipper: const _CartaStageClipper(),
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [paperDeep, paper],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: .40),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: deep.withValues(alpha: .22),
                            blurRadius: 28,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 720),
                    curve: Curves.easeOutCubic,
                    left: (cardWidth - letterWidth) / 2,
                    width: letterWidth,
                    top: _coverOpening ? -cardHeight * .72 : cardHeight * .08,
                    height: cardHeight * .84,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: paper,
                        border: Border.all(
                          color: accent.withValues(alpha: .42),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: deep.withValues(alpha: .14),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.lerp(paper, Colors.white, .42)!,
                              paper,
                            ],
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: .16),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Center(
                                child: Text(
                                  initials.isEmpty ? '·' : initials,
                                  style: TextStyle(
                                    fontFamily: serif,
                                    fontSize: letterWidth * .34,
                                    height: 1,
                                    letterSpacing: 5,
                                    color: accent.withValues(alpha: .07),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _cartaOrnament(accent, width: 24),
                                const SizedBox(height: 4),
                                Text(
                                  'PARA TI',
                                  style: TextStyle(
                                    fontSize: 6.6,
                                    letterSpacing: 2.2,
                                    fontWeight: FontWeight.w600,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: serif,
                                    fontSize: letterWidth * .135,
                                    height: 1.02,
                                    color: t.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Acompáñanos a celebrar este día',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: serif,
                                    fontSize: 7.6,
                                    fontStyle: FontStyle.italic,
                                    color: t.soft,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: _cartaOrnament(accent, width: 30),
                                ),
                                Text(
                                  dateLabel,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 7.2,
                                    letterSpacing: 1.1,
                                    color: t.soft,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [paper, paperDeep],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: .42),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: deep.withValues(alpha: .14),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CartaFoldPainter(
                          accent.withValues(alpha: .13),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9,
                    right: 9,
                    top: 9,
                    bottom: 9,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: accent.withValues(alpha: .16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: flapHeight,
                    child: _cartaFlap(
                      paper: paper,
                      paperDeep: paperDeep,
                      accent: accent,
                      monogram: initials,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: flapHeight - 23,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: _coverOpening ? 0 : 1,
                      child: Center(
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                top: 33,
                                left: 15,
                                child: Transform.rotate(
                                  angle: .24,
                                  child: ClipPath(
                                    clipper: const _CartaRibbonClipper(),
                                    child: Container(
                                      width: 9,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            accent.withValues(alpha: .62),
                                            accent.withValues(alpha: .22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 33,
                                left: 24,
                                child: Transform.rotate(
                                  angle: -.24,
                                  child: ClipPath(
                                    clipper: const _CartaRibbonClipper(),
                                    child: Container(
                                      width: 9,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            accent.withValues(alpha: .70),
                                            accent.withValues(alpha: .26),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(24),
                                    topRight: Radius.circular(21),
                                    bottomLeft: Radius.circular(22),
                                    bottomRight: Radius.circular(26),
                                  ),
                                  gradient: RadialGradient(
                                    colors: [
                                      Color.lerp(accent, Colors.white, .38)!,
                                      accent,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .58),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: deep.withValues(alpha: .24),
                                      blurRadius: 10,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: .30,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Text(
                                        initials.isEmpty ? '♥' : initials,
                                        style: TextStyle(
                                          fontFamily: serif,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: ctaInk,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withValues(
                                                alpha: .18,
                                              ),
                                              offset: const Offset(0, 1),
                                              blurRadius: 1,
                                            ),
                                          ],
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/covers/pc_fondo_movil.webp', fit: BoxFit.cover),
        if (tint != Colors.transparent)
          Positioned.fill(child: ColoredBox(color: tint)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: .08),
                  Colors.transparent,
                  deep.withValues(alpha: .08),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: -18,
          bottom: -18,
          width: (screenWidth * .58).clamp(190.0, 360.0).toDouble(),
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -.035,
              alignment: Alignment.bottomLeft,
              child: Image.asset(
                'assets/covers/pc_flores.webp',
                fit: BoxFit.contain,
                alignment: Alignment.bottomLeft,
              ),
            ),
          ),
        ),
        Positioned(
          right: -26,
          top: -30,
          width: (cardWidth * .34).clamp(84.0, 112.0).toDouble(),
          height: cardHeight * 1.55,
          child: IgnorePointer(
            child: Image.asset(
              'assets/covers/pc_cinta.webp',
              fit: BoxFit.contain,
              alignment: Alignment.topRight,
            ),
          ),
        ),
        Positioned(
          left: 22,
          top: 34,
          width: (cardWidth * .38).clamp(96.0, 130.0).toDouble(),
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -.12,
              child: Image.asset(
                'assets/covers/pc_anillos.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    opacity: _coverOpening ? 0 : 1,
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: serif,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontStyle: FontStyle.italic,
                        color: t.ink.withValues(alpha: .82),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    button: true,
                    label: 'Abrir el sobre',
                    child: GestureDetector(
                      key: const ValueKey('carta-envelope'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _startCoverOpen,
                      child: SizedBox(
                        width: rotatedWidth + 12,
                        height: rotatedHeight + 28,
                        child: Center(child: card),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Toca el sobre para abrir',
                      style: TextStyle(
                        fontFamily: serif,
                        fontSize: 17,
                        fontStyle: FontStyle.italic,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cartaFlap({
    required Color paper,
    required Color paperDeep,
    required Color accent,
    required String monogram,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _coverOpening ? 1 : 0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: (1 - value).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .001)
              ..rotateX(value * math.pi),
            child: child,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipPath(
            clipper: const _CartaFlapClipper(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [paperDeep, paper],
                ),
                border: Border.all(color: accent.withValues(alpha: .16)),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CartaFlapLinePainter(accent.withValues(alpha: .30)),
            ),
          ),
          if (monogram.isNotEmpty)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Text(
                monogram,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  color: accent.withValues(alpha: .55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Portada (sobre)
  // ---------------------------------------------------------------
  Widget _coverView(Invitation inv, InvitationTemplate t, Color accent) {
    if (inv.coverStyleKey == 'carta') {
      return _cartaCoverView(inv, t, accent);
    }
    final event = inv.eventDate;
    final parts = event == null ? null : invitationDateParts(event);
    final photo = t.cover == 'foto' && inv.photos.isNotEmpty
        ? inv.photos.first
        : '';
    final style = inv.coverStyleKey;
    final dark = style == 'noche' || style == 'cortina';
    final coverInk = dark ? Color.lerp(Colors.white, t.panel, .18)! : t.ink;
    final coverSoft = dark ? Color.lerp(t.panel, accent, .24)! : t.soft;
    final coverAccent = dark ? Color.lerp(accent, Colors.white, .38)! : accent;
    final coverDeep = Color.lerp(
      Color.lerp(t.bg, accent, .32)!,
      Colors.black,
      .46,
    )!;
    final styleLabel = switch (style) {
      'carta' => 'Carta',
      'xv' => 'Portada de XV',
      'noche' => 'Noche estrellada',
      'cortina' => 'Cortina',
      'clasica' => 'Clásica',
      _ => 'Rosa Pastel',
    };
    final styleIcon = switch (style) {
      'carta' => Icons.mail_outline,
      'xv' => Icons.workspace_premium_outlined,
      'noche' => Icons.nightlight_round,
      'cortina' => Icons.theaters_outlined,
      'clasica' => Icons.diamond_outlined,
      _ => Icons.local_florist_outlined,
    };
    final bgColors = switch (style) {
      'carta' => [t.panel, Color.lerp(t.panel, t.bg, .55)!],
      'xv' => [Color.lerp(t.panel, accent, .1)!, t.bg],
      'noche' => [coverDeep, Color.lerp(coverDeep, Colors.black, .45)!],
      'cortina' => [Color.lerp(coverDeep, accent, .18)!, coverDeep],
      'clasica' => [t.panel, Color.lerp(t.panel, t.bg, .4)!],
      _ => [Color.lerp(t.panel, Colors.white, .25)!, t.bg],
    };
    final occasion = inv.occasion.trim().isEmpty
        ? t.occasion
        : inv.occasion.trim();
    final isXV =
        occasion.toLowerCase().contains('xv') ||
        occasion.toLowerCase().contains('quince');
    final initials = inv.displayTitle
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    final ctaLabel = switch (style) {
      'xv' => isXV ? 'ENTRAR A MIS XV' : 'ABRIR LA CELEBRACIÓN',
      'noche' => 'ABRIR BAJO LAS ESTRELLAS',
      'cortina' => 'ABRIR EL TELÓN',
      _ => 'ABRIR INVITACIÓN',
    };
    final coverLead = style == 'xv'
        ? Column(
            children: [
              Icon(styleIcon, size: 28, color: coverAccent),
              Text(
                isXV ? '15' : '✦',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 76,
                  height: .85,
                  color: coverAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
        : Icon(styleIcon, size: 30, color: coverAccent);
    final contentColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        coverLead,
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: dark
                ? Colors.black.withValues(alpha: .22)
                : t.panel.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'PORTADA · ${styleLabel.toUpperCase()}',
            style: TextStyle(
              fontSize: 7.5,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w700,
              color: coverSoft,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          inv.displayTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _displayFamily(inv.fontKey),
            fontSize: style == 'xv' ? 38 : 46,
            height: 1,
            fontStyle: inv.fontKey == 'romantica'
                ? FontStyle.italic
                : FontStyle.normal,
            color: coverInk,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 60,
          height: 1,
          color: coverAccent.withValues(alpha: .55),
        ),
        const SizedBox(height: 12),
        Text(
          parts != null
              ? '${_cap(parts.weekday)} ${parts.day} · '
                    '${_cap(parts.month)} ${parts.year}'
              : inv.dateText.trim(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9.5, letterSpacing: 1.8, color: coverSoft),
        ),
        if (style == 'xv') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: coverAccent,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              inv.envelopeText.trim().isEmpty
                  ? 'Mis XV años'
                  : inv.envelopeText.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 7.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: coverAccent.computeLuminance() > .45
                    ? const Color(0xFF3B2923)
                    : Colors.white,
              ),
            ),
          ),
        ],
        const SizedBox(height: 26),
        Material(
          color: coverAccent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _cover = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: Text(
                ctaLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                  color: coverAccent.computeLuminance() > .45
                      ? const Color(0xFF10131A)
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget framed = contentColumn;
    if (style == 'carta') {
      framed = Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, t.panel],
          ),
          border: Border.all(color: coverAccent.withValues(alpha: .45)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            contentColumn,
            Positioned(
              right: -7,
              bottom: -19,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: coverAccent,
                  border: Border.all(color: Colors.white.withValues(alpha: .6)),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: coverAccent.computeLuminance() > .45
                        ? const Color(0xFF3B2923)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (style == 'clasica') {
      framed = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: coverAccent.withValues(alpha: .7)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
          decoration: BoxDecoration(
            border: Border.all(color: coverAccent.withValues(alpha: .32)),
          ),
          child: contentColumn,
        ),
      );
    }

    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: framed,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo.isNotEmpty)
          _photo(photo)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bgColors,
              ),
            ),
          ),
        if (style == 'rosa') ...[
          Positioned(
            left: 30,
            right: 30,
            top: 62,
            bottom: 70,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: coverAccent.withValues(alpha: .3)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(180),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 30,
            top: 78,
            child: Icon(
              Icons.local_florist_outlined,
              size: 34,
              color: coverAccent.withValues(alpha: .42),
            ),
          ),
          Positioned(
            right: 28,
            bottom: 96,
            child: Icon(
              Icons.local_florist_outlined,
              size: 28,
              color: coverAccent.withValues(alpha: .35),
            ),
          ),
        ],
        if (style == 'xv') ...[
          Positioned(
            left: 28,
            top: 78,
            child: Transform.rotate(
              angle: .35,
              child: Container(
                width: 7,
                height: 18,
                color: coverAccent.withValues(alpha: .35),
              ),
            ),
          ),
          Positioned(
            right: 34,
            top: 150,
            child: Transform.rotate(
              angle: -.5,
              child: Container(
                width: 6,
                height: 15,
                color: coverAccent.withValues(alpha: .32),
              ),
            ),
          ),
          Positioned(
            left: 58,
            bottom: 170,
            child: Container(
              width: 5,
              height: 12,
              color: coverAccent.withValues(alpha: .28),
            ),
          ),
        ],
        if (style == 'noche')
          Positioned(
            top: 24,
            right: 24,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(Colors.white, coverAccent, .38),
                boxShadow: [
                  BoxShadow(
                    color: coverAccent.withValues(alpha: .35),
                    blurRadius: 36,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        if (style == 'cortina') ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: .38),
                    coverDeep.withValues(alpha: .78),
                    Colors.black.withValues(alpha: .30),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: .30),
                    coverDeep.withValues(alpha: .78),
                    Colors.black.withValues(alpha: .38),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (photo.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: (dark ? Colors.black : t.bg).withValues(alpha: .55),
            ),
          ),
        content,
      ],
    );
  }

  // ---------------------------------------------------------------
  // Invitación completa
  // ---------------------------------------------------------------
  Widget _invitationView(Invitation inv, InvitationTemplate t, Color accent) {
    final bg = inv.bgMedia.trim();
    final hasMedia = bg.isNotEmpty && isHttpUrl(bg);
    final isVideo = hasMedia && isVideoUrl(bg);
    final media = hasMedia && !isVideo ? bg : '';

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.maxWidth + 32;
        final scale = (width / 440).clamp(.78, 1.12);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 26),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(
                children: [
                  _mainCard(inv, t, accent, scale),
                  if (widget.editable) ..._editableFlow(inv, t, accent, scale),
                  if (!widget.editable)
                    for (final key in inv.flowSectionOrder)
                      if (inv.sectionOn(key))
                        _flowSection(key, inv, t, accent, scale),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (isVideo) {
      // El vídeo no se reproduce en el panel (sí en la liga): se avisa con
      // una cinta para que nadie piense que el fondo se perdió.
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: accent.withValues(alpha: .12),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              'Vídeo de fondo · se reproduce en la liga',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: .4,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    if (media.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [inv.backgroundColor, t.bgAlt],
          ),
        ),
        child: body,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _photo(media),
        DecoratedBox(
          decoration: BoxDecoration(
            color: inv.backgroundColor.withValues(alpha: .82),
          ),
          child: const SizedBox.expand(),
        ),
        body,
      ],
    );
  }

  /// Una sección del flujo, en el orden que guardó el panel de capas.
  Widget _flowSection(
    String key,
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) => switch (key) {
    'families' => _families(inv, t, accent, s),
    'details' => _details(inv, t, accent, s),
    'hashtag' => _hashtag(inv, t, accent, s),
    'itinerary' => _itinerary(inv, t, accent, s),
    'footer' => _footer(inv, t, accent, s),
    _ => const SizedBox.shrink(),
  };

  /// El flujo con zonas de inserción y bloques con acciones al pasar el
  /// ratón. Solo se usa en el editor visual; la liga pública conserva el
  /// documento de siempre.
  List<Widget> _editableFlow(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final out = <Widget>[];
    for (final key in inv.flowSectionOrder) {
      if (!inv.sectionOn(key)) continue;
      out.add(
        _InvitationDropSlot(
          key: ValueKey('invitation-drop-$key'),
          beforeKey: key,
          accent: accent,
          onDrop: widget.onDropComponent,
        ),
      );
      out.add(
        _EditableInvitationSection(
          key: ValueKey('invitation-preview-section-$key'),
          componentKey: key,
          label: invitationComponentLabel(key),
          accent: accent,
          selected: widget.selectedSection == key,
          onSelect: () => widget.onSelectSection?.call(key),
          onEdit: () => widget.onEditSection?.call(key),
          onRemove: () => widget.onRemoveSection?.call(key),
          child: _flowSection(key, inv, t, accent, s),
        ),
      );
    }
    out.add(
      _InvitationDropSlot(
        key: const ValueKey('invitation-drop-end'),
        beforeKey: null,
        accent: accent,
        onDrop: widget.onDropComponent,
      ),
    );
    return out;
  }

  Widget _mainCard(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final event = inv.eventDate;
    final parts = event == null ? null : invitationDateParts(event);
    final photos = inv.photos.take(3).toList(growable: false);
    final photosOn = inv.sectionOn('photos');
    final photosDesign = inv.componentDesign('photos');
    final quote = inv.quoteText;
    final quoteOn = inv.sectionOn('quote');
    final quoteDesign = inv.componentDesign('quote');

    final flat = t.card == 'plano';
    final paper = t.card == 'papel';
    return Container(
      margin: EdgeInsets.only(bottom: 16 * s),
      padding: flat
          ? EdgeInsets.fromLTRB(0, 12 * s, 0, 10 * s)
          : EdgeInsets.fromLTRB(18 * s, 26 * s, 18 * s, 22 * s),
      decoration: flat
          ? null
          : BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(paper ? 4 * s : 22 * s),
              border: Border.all(
                color: accent.withValues(alpha: paper ? .55 : .32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.light ? .12 : .42),
                  blurRadius: paper ? 18 : 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
      child: Column(
        children: [
          if (t.photos == 'portada' && photosOn && photos.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(flat ? 0 : 14 * s),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: _photo(photos.first),
              ),
            ),
            SizedBox(height: 16 * s),
          ],
          Text(
            (inv.occasion.trim().isEmpty ? t.occasion : inv.occasion)
                .toUpperCase(),
            style: TextStyle(
              fontSize: 7.5 * s,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          SizedBox(height: 10 * s),
          Text(
            inv.displayTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _displayFamily(inv.fontKey),
              fontSize: 42 * s,
              height: .98,
              fontStyle: inv.fontKey == 'romantica'
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: t.ink,
            ),
          ),
          if (inv.subheadline.trim().isNotEmpty) ...[
            SizedBox(height: 8 * s),
            Text(
              inv.subheadline.trim().toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 7.5 * s,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: t.soft,
              ),
            ),
          ],
          if (parts != null) ...[
            SizedBox(height: 16 * s),
            _dateCapsule(parts, t, accent, s),
          ] else if (inv.dateText.trim().isNotEmpty) ...[
            SizedBox(height: 16 * s),
            _dateCapsuleText(inv.dateText.trim(), t, accent, s),
          ],
          if (inv.timeText.trim().isNotEmpty) ...[
            SizedBox(height: 8 * s),
            Text(
              inv.timeText.trim().toUpperCase(),
              style: TextStyle(
                fontSize: 7.5 * s,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
          if (t.ornament == 'floral') ...[
            SizedBox(height: 12 * s),
            _TiaraMark(size: 34 * s, color: const Color(0xFFC9A45E)),
          ],
          if (photosOn && photos.isNotEmpty) ...[
            SizedBox(height: 22 * s),
            if (photosDesign == 'arco')
              Container(
                width: 170 * s,
                padding: EdgeInsets.all(5 * s),
                decoration: BoxDecoration(
                  color: t.panel,
                  border: Border.all(color: accent.withValues(alpha: .35)),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(200 * s),
                    topRight: Radius.circular(200 * s),
                    bottomLeft: Radius.circular(6 * s),
                    bottomRight: Radius.circular(6 * s),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(196 * s),
                    topRight: Radius.circular(196 * s),
                    bottomLeft: Radius.circular(4 * s),
                    bottomRight: Radius.circular(4 * s),
                  ),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _photo(photos.first),
                  ),
                ),
              )
            else if (photosDesign == 'mosaico')
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8 * s,
                runSpacing: 8 * s,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    SizedBox(
                      width: (i == 2 ? 112 : 92) * s,
                      child: Container(
                        padding: EdgeInsets.all(3 * s),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: accent.withValues(alpha: .25),
                          ),
                        ),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: _photo(photos[i]),
                        ),
                      ),
                    ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    Transform.translate(
                      offset: Offset(
                        photos.length == 1 ? 0 : (1 - i) * 14.0 * s,
                        0,
                      ),
                      child: Transform.rotate(
                        angle: i == 0
                            ? -.12
                            : i == photos.length - 1
                            ? .12
                            : 0,
                        child: Container(
                          width: (photos.length == 1 ? 104 : 78) * s,
                          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .22),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: AspectRatio(
                            aspectRatio: 3 / 4,
                            child: _photo(photos[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
          if (quoteOn && quote.isNotEmpty) ...[
            SizedBox(height: 18 * s),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all((quoteDesign == 'minimal' ? 8 : 14) * s),
              decoration: BoxDecoration(
                color: quoteDesign == 'comillas'
                    ? accent.withValues(alpha: .05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  quoteDesign == 'comillas'
                      ? 14 * s
                      : quoteDesign == 'marco'
                      ? 4 * s
                      : 0,
                ),
                border: quoteDesign == 'marco'
                    ? Border.all(color: accent.withValues(alpha: .65))
                    : quoteDesign == 'minimal'
                    ? Border(
                        top: BorderSide(color: accent.withValues(alpha: .3)),
                        bottom: BorderSide(color: accent.withValues(alpha: .3)),
                      )
                    : Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: Column(
                children: [
                  if (quoteDesign != 'minimal')
                    Text(
                      '“',
                      style: TextStyle(
                        fontFamily: _displayFamily(inv.fontKey),
                        fontSize: 24 * s,
                        height: .7,
                        color: accent,
                      ),
                    ),
                  if (quoteDesign != 'minimal') SizedBox(height: 4 * s),
                  Text(
                    quote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _displayFamily(inv.fontKey),
                      fontStyle: FontStyle.italic,
                      fontSize: (quoteDesign == 'minimal' ? 12 : 10.5) * s,
                      height: 1.7,
                      color: t.soft,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (inv.sectionOn('countdown') && event != null) ...[
            SizedBox(height: 18 * s),
            _countdown(event, t, accent, s, inv.componentDesign('countdown')),
          ],
          if (inv.placeName.trim().isNotEmpty ||
              inv.placeAddress.trim().isNotEmpty) ...[
            SizedBox(height: 18 * s),
            Text(
              'LUGAR',
              style: TextStyle(
                fontSize: 6.8 * s,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
                color: t.soft,
              ),
            ),
            SizedBox(height: 4 * s),
            if (inv.placeName.trim().isNotEmpty)
              Text(
                inv.placeName.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5 * s,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            if (inv.placeAddress.trim().isNotEmpty) ...[
              SizedBox(height: 2 * s),
              Text(
                inv.placeAddress.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9.5 * s, color: t.soft),
              ),
            ],
          ],
          if (inv.dressCode.trim().isNotEmpty) ...[
            SizedBox(height: 14 * s),
            Text(
              'CÓDIGO DE VESTIMENTA · ${inv.dressCode.trim().toUpperCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 6.8 * s,
                letterSpacing: 1.4,
                color: t.soft,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateCapsule(
    ({String weekday, String day, String month, String year, String time}) p,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(color: accent.withValues(alpha: .38)),
      ),
      child: Column(
        children: [
          Text(
            '✦ ${_cap(p.weekday)} ✦',
            style: TextStyle(
              fontSize: 7 * s,
              letterSpacing: 2.6,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          SizedBox(height: 5 * s),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32 * s,
                height: 32 * s,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  p.day,
                  style: TextStyle(
                    fontFamily: _displayFamily('clasica'),
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                    color: accent.computeLuminance() > .32
                        ? const Color(0xFF10131A)
                        : Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 9 * s),
              Text(
                '${_cap(p.month).toUpperCase()} · ${p.year}',
                style: TextStyle(
                  fontFamily: _displayFamily('clasica'),
                  fontSize: 12 * s,
                  letterSpacing: 1,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateCapsuleText(
    String text,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(color: accent.withValues(alpha: .38)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: _displayFamily('clasica'),
          fontSize: 12 * s,
          letterSpacing: .5,
          color: t.ink,
        ),
      ),
    );
  }

  Widget _countdown(
    DateTime target,
    InvitationTemplate t,
    Color accent,
    double s,
    String design,
  ) {
    final diff = target.difference(DateTime.now());
    final left = diff.isNegative ? Duration.zero : diff;
    String two(int v) => v.toString().padLeft(2, '0');
    final items = [
      (two(left.inDays), 'DÍAS'),
      (two(left.inHours % 24), 'HORAS'),
      (two(left.inMinutes % 60), 'MINUTOS'),
      (two(left.inSeconds % 60), 'SEGUNDOS'),
    ];
    return Column(
      children: [
        if (design != 'minimal')
          Text(
            'Faltan',
            style: TextStyle(
              fontFamily: _displayFamily('romantica'),
              fontStyle: FontStyle.italic,
              fontSize: 19 * s,
              color: accent,
            ),
          ),
        SizedBox(height: 6 * s),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0 && design != 'minimal')
                Padding(
                  padding: EdgeInsets.only(bottom: 12 * s),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 13 * s, color: accent),
                  ),
                ),
              Column(
                children: [
                  Text(
                    items[i].$1,
                    style: TextStyle(
                      fontFamily: _displayFamily('clasica'),
                      fontSize: 18 * s,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: t.ink,
                    ),
                  ),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontSize: 5.8 * s,
                      letterSpacing: 1.2,
                      color: t.soft,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _families(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final families = [
      for (final f in inv.families)
        if (!f.isEmpty) f,
    ];
    if (families.isEmpty) return const SizedBox.shrink();
    final design = inv.componentDesign('families');
    final minimal = design == 'minimal';
    return _sectionBlock(
      t,
      accent,
      s,
      title: 'Con mi familia',
      children: [
        for (final f in families)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: minimal ? 0 : 8 * s),
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: minimal ? Colors.transparent : t.panel,
              borderRadius: BorderRadius.zero,
              border: minimal
                  ? Border(
                      top: BorderSide(color: accent.withValues(alpha: .35)),
                    )
                  : Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: minimal
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  f.title,
                  textAlign: minimal ? TextAlign.left : TextAlign.center,
                  style: TextStyle(
                    fontFamily: _displayFamily('clasica'),
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                if (!minimal) ...[
                  SizedBox(height: 2 * s),
                  Text(
                    '♥',
                    style: TextStyle(fontSize: 8 * s, color: accent),
                  ),
                ],
                SizedBox(height: 4 * s),
                for (final n in f.names)
                  Padding(
                    padding: EdgeInsets.only(bottom: 2 * s),
                    child: Text(
                      n,
                      textAlign: minimal ? TextAlign.left : TextAlign.center,
                      style: TextStyle(fontSize: 10.5 * s, color: t.ink),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _details(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final details = [
      for (final d in inv.details)
        if (!d.isEmpty) d,
    ];
    if (details.isEmpty) return const SizedBox.shrink();
    final design = inv.componentDesign('details');
    final editorial = design == 'editorial';
    final rsvpDesign = inv.componentDesign('rsvp');
    final section = _sectionBlock(
      t,
      accent,
      s,
      title: 'Detalles',
      subtitle: 'Todo lo que necesitas saber para acompañarme',
      children: [
        for (final d in details)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: editorial ? 0 : 8 * s),
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: editorial ? Colors.transparent : t.panel,
              borderRadius: BorderRadius.circular(editorial ? 0 : 14 * s),
              border: editorial
                  ? Border(top: BorderSide(color: accent.withValues(alpha: .3)))
                  : Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: editorial
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (!editorial && t.ornament == 'floral') ...[
                  _RibbonMark(size: 22 * s, color: accent),
                  SizedBox(height: 3 * s),
                ],
                Text(d.icon, style: TextStyle(fontSize: 17 * s)),
                SizedBox(height: 5 * s),
                Text(
                  d.title,
                  textAlign: editorial ? TextAlign.left : TextAlign.center,
                  style: TextStyle(
                    fontFamily: _displayFamily('clasica'),
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (d.time.isNotEmpty) ...[
                  SizedBox(height: 4 * s),
                  Text(
                    d.time.toUpperCase(),
                    style: TextStyle(
                      fontSize: 7 * s,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
                if (d.place.isNotEmpty) ...[
                  SizedBox(height: 3 * s),
                  Text(
                    d.place,
                    textAlign: editorial ? TextAlign.left : TextAlign.center,
                    style: TextStyle(fontSize: 10.5 * s, color: t.ink),
                  ),
                ],
                if (d.note.isNotEmpty) ...[
                  SizedBox(height: 4 * s),
                  Text(
                    d.note,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _displayFamily('clasica'),
                      fontSize: 12 * s,
                      color: accent,
                    ),
                  ),
                ],
                if (d.mapUrl.trim().isNotEmpty) ...[
                  SizedBox(height: 8 * s),
                  _pill('VER UBICACIÓN', accent, s, outlined: true),
                ],
              ],
            ),
          ),
        if (inv.sectionOn('rsvp') && inv.rsvpPhone.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: rsvpDesign == 'tarjeta' ? t.panel : Colors.transparent,
              borderRadius: BorderRadius.circular(
                rsvpDesign == 'tarjeta' ? 14 * s : 0,
              ),
              border: rsvpDesign == 'tarjeta'
                  ? Border.all(color: accent.withValues(alpha: .25))
                  : Border(
                      top: BorderSide(color: accent.withValues(alpha: .3)),
                    ),
            ),
            child: Column(
              children: [
                if (rsvpDesign != 'minimal') ...[
                  if (t.ornament == 'floral')
                    _ButterflyMark(size: 24 * s, color: accent)
                  else
                    Text('💌', style: TextStyle(fontSize: 17 * s)),
                ],
                SizedBox(height: 5 * s),
                Text(
                  'Confirmar asistencia',
                  style: TextStyle(
                    fontFamily: _displayFamily('clasica'),
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                SizedBox(height: 3 * s),
                Text(
                  'Esperamos contar con tu presencia en este día tan especial.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9 * s, color: t.soft),
                ),
                SizedBox(height: 8 * s),
                _pill('CONFIRMAR', accent, s),
              ],
            ),
          ),
      ],
    );
    final media = inv.detailsMedia.trim();
    if (media.isEmpty || !isHttpUrl(media)) return section;
    if (isVideoUrl(media)) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: accent.withValues(alpha: .12),
            padding: EdgeInsets.symmetric(vertical: 5 * s),
            child: Text(
              'Vídeo en los detalles · se reproduce en la liga',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: .4,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          section,
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: Opacity(opacity: .24, child: _photo(media))),
        section,
      ],
    );
  }

  Widget _hashtag(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final tag = inv.hashtag.trim();
    if (tag.isEmpty) return const SizedBox.shrink();
    final design = inv.componentDesign('hashtag');
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16 * s),
      padding: EdgeInsets.symmetric(vertical: 18 * s, horizontal: 14 * s),
      decoration: BoxDecoration(
        color: design == 'minimal'
            ? Colors.transparent
            : accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(
          design == 'sello'
              ? 4 * s
              : design == 'minimal'
              ? 0
              : 16 * s,
        ),
        border: design == 'minimal'
            ? null
            : Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Column(
        children: [
          Text(
            'Captura momentos únicos con',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _displayFamily('romantica'),
              fontStyle: FontStyle.italic,
              fontSize: 12 * s,
              color: t.soft,
            ),
          ),
          SizedBox(height: 4 * s),
          Text(
            tag,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _displayFamily('clasica'),
              fontSize: 18 * s,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itinerary(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final stops = [
      for (final st in inv.itinerary)
        if (!st.isEmpty) st,
    ];
    if (stops.isEmpty) return const SizedBox.shrink();
    final design = inv.componentDesign('itinerary');
    return _sectionBlock(
      t,
      accent,
      s,
      title: 'Itinerario de actividades',
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 4 * s),
          decoration: BoxDecoration(
            color: design == 'compacto' ? Colors.transparent : t.panel,
            borderRadius: BorderRadius.circular(14 * s),
            border: design == 'compacto'
                ? null
                : Border.all(color: accent.withValues(alpha: .25)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < stops.length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (design == 'linea')
                      Column(
                        children: [
                          Container(
                            width: 7 * s,
                            height: 7 * s,
                            margin: EdgeInsets.only(top: 3 * s),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.panel,
                              border: Border.all(color: accent, width: 1.4),
                            ),
                          ),
                          if (i < stops.length - 1)
                            Container(
                              width: 1,
                              height: 26 * s,
                              color: accent.withValues(alpha: .35),
                            ),
                        ],
                      )
                    else
                      SizedBox(width: 4 * s),
                    SizedBox(width: 10 * s),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8 * s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stops[i].time.toUpperCase(),
                              style: TextStyle(
                                fontSize: 7 * s,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                            Text(
                              stops[i].title,
                              style: TextStyle(
                                fontSize: 10.5 * s,
                                color: t.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer(Invitation inv, InvitationTemplate t, Color accent, double s) {
    final design = inv.componentDesign('footer');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * s),
      child: Column(
        children: [
          if (design != 'minimal')
            Text('💗', style: TextStyle(fontSize: 14 * s)),
          SizedBox(height: 6 * s),
          Text(
            inv.displayTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _displayFamily(inv.fontKey),
              fontStyle: inv.fontKey == 'romantica'
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontSize: 32 * s,
              height: 1,
              color: t.ink,
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            'Tu presencia es el mejor regalo que puedo recibir.\n'
            '¡Te espero con mucho cariño!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5 * s, height: 1.8, color: t.soft),
          ),
          SizedBox(height: 14 * s),
          Text(
            'INVITACIÓN HECHA CON AMOR POR HARDSTREET',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 6.8 * s,
              letterSpacing: 1.8,
              color: t.soft.withValues(alpha: .8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionBlock(
    InvitationTemplate t,
    Color accent,
    double s, {
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * s),
      child: Column(
        children: [
          if (t.ornament != 'ninguno') ...[
            _Ornament(color: accent, width: 30 * s),
            SizedBox(height: 8 * s),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _displayFamily('clasica'),
              fontSize: 22 * s,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4 * s),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9 * s, color: t.soft),
            ),
          ],
          SizedBox(height: 10 * s),
          ...children,
        ],
      ),
    );
  }

  Widget _pill(String text, Color accent, double s, {bool outlined = false}) {
    final onAccent = accent.computeLuminance() > .32
        ? const Color(0xFF10131A)
        : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : accent,
        borderRadius: BorderRadius.circular(999),
        border: outlined
            ? Border.all(color: accent.withValues(alpha: .6))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 6.8 * s,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: outlined ? accent : onAccent,
        ),
      ),
    );
  }

  /// La foto, con el token de la sesión para que se vea ANTES de publicarla
  /// (la liga pública, en cambio, usa la URL pública).
  Widget _photo(String url) {
    return Image.network(
      driveImagePreview(url, token: HsSession.token, width: 900),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: Colors.black.withValues(alpha: .18),
        child: const Center(
          child: Icon(Icons.image_outlined, color: Colors.white54, size: 22),
        ),
      ),
    );
  }

  static String _displayFamily(String fontKey) =>
      fontKey == 'moderna' ? 'sans-serif' : 'serif';

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Un bloque del flujo en el editor: al pasar el ratón muestra arrastrar,
/// editar y eliminar. El texto y las fotos no se borran al ocultarlo: el
/// componente queda en la biblioteca de Items para volver a insertarlo.
class _EditableInvitationSection extends StatefulWidget {
  const _EditableInvitationSection({
    super.key,
    required this.componentKey,
    required this.label,
    required this.child,
    required this.accent,
    required this.selected,
    this.onSelect,
    this.onEdit,
    this.onRemove,
  });

  final String componentKey;
  final String label;
  final Widget child;
  final Color accent;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  State<_EditableInvitationSection> createState() =>
      _EditableInvitationSectionState();
}

class _EditableInvitationSectionState
    extends State<_EditableInvitationSection> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hover || widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active
                ? widget.accent.withValues(alpha: .035)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? widget.accent.withValues(alpha: .70)
                  : Colors.transparent,
              width: 1.3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Material(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Draggable<String>(
                            data: 'move:${widget.componentKey}',
                            feedback: Material(
                              elevation: 8,
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(9),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                child: Text(
                                  widget.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                            child: Tooltip(
                              message: 'Arrastrar ${widget.label}',
                              child: Padding(
                                key: ValueKey(
                                  'invitation-preview-drag-'
                                  '${widget.componentKey}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 5,
                                ),
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 15,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          _sectionAction(
                            key: ValueKey(
                              'invitation-preview-edit-'
                              '${widget.componentKey}',
                            ),
                            tooltip: 'Editar ${widget.label}',
                            icon: Icons.edit_outlined,
                            onTap: widget.onEdit,
                          ),
                          _sectionAction(
                            key: ValueKey(
                              'invitation-preview-remove-'
                              '${widget.componentKey}',
                            ),
                            tooltip: 'Eliminar ${widget.label}',
                            icon: Icons.delete_outline_rounded,
                            color: scheme.error,
                            onTap: widget.onRemove,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              widget.child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 26),
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: color),
    );
  }
}

/// La línea que aparece entre secciones mientras se arrastra un ítem desde
/// el panel. Suelta ahí para insertar o reordenar.
class _InvitationDropSlot extends StatelessWidget {
  const _InvitationDropSlot({
    super.key,
    required this.beforeKey,
    required this.accent,
    this.onDrop,
  });

  final String? beforeKey;
  final Color accent;
  final void Function(String payload, String? beforeKey)? onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        if (onDrop == null) return false;
        return details.data.startsWith('new:') ||
            details.data.startsWith('move:') ||
            details.data.startsWith('design:');
      },
      onAcceptWithDetails: (details) => onDrop?.call(details.data, beforeKey),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 34 : 8,
          margin: EdgeInsets.symmetric(vertical: active ? 3 : 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: .10) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: accent.withValues(alpha: .55))
                : null,
          ),
          child: active
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      'Suelta aquí para insertar',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

/// La tiara dorada de la invitación original.
class _TiaraMark extends StatelessWidget {
  const _TiaraMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * .64), painter: _TiaraPainter(color));
}

class _TiaraPainter extends CustomPainter {
  _TiaraPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final crown = Path()
      ..moveTo(w * .16, h * .78)
      ..lineTo(w * .16, h * .34)
      ..lineTo(w * .36, h * .5)
      ..lineTo(w * .5, h * .18)
      ..lineTo(w * .64, h * .5)
      ..lineTo(w * .84, h * .34)
      ..lineTo(w * .84, h * .78);
    canvas.drawPath(crown, stroke);
    canvas.drawLine(Offset(w * .06, h * .78), Offset(w * .94, h * .78), stroke);
    final fill = Paint()..color = color;
    for (final o in [
      Offset(w * .16, h * .28),
      Offset(w * .5, h * .12),
      Offset(w * .84, h * .28),
    ]) {
      canvas.drawCircle(o, w * .035, fill);
    }
  }

  @override
  bool shouldRepaint(_TiaraPainter old) => old.color != color;
}

/// El lazo de las tarjetas de detalle.
class _RibbonMark extends StatelessWidget {
  const _RibbonMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 1.05),
    painter: _RibbonPainter(color),
  );
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * .5, h * .34);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..cubicTo(w * .06, h * .04, w * .02, h * .58, c.dx, c.dy)
      ..cubicTo(w * .02, h * .58, w * .06, h * .04, c.dx, c.dy)
      ..cubicTo(w * .94, h * .04, w * .98, h * .58, c.dx, c.dy)
      ..cubicTo(w * .98, h * .58, w * .94, h * .04, c.dx, c.dy)
      ..moveTo(c.dx, c.dy)
      ..lineTo(w * .3, h * .96)
      ..moveTo(c.dx, c.dy)
      ..lineTo(w * .7, h * .96);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

/// La mariposa de la tarjeta de confirmación.
class _ButterflyMark extends StatelessWidget {
  const _ButterflyMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _ButterflyPainter(color));
}

class _ButterflyPainter extends CustomPainter {
  _ButterflyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final body = Offset(w * .5, h * .52);
    canvas.drawLine(Offset(w * .5, h * .3), Offset(w * .5, h * .8), p);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .28, h * .38),
        width: w * .34,
        height: h * .26,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .72, h * .38),
        width: w * .34,
        height: h * .26,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .3, h * .64),
        width: w * .28,
        height: h * .2,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .7, h * .64),
        width: w * .28,
        height: h * .2,
      ),
      p,
    );
    canvas.drawCircle(body, w * .025, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ButterflyPainter old) => old.color != color;
}

/// La línea con el rombo de las invitaciones.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: width, height: 1, color: color.withValues(alpha: .55)),
        const SizedBox(width: 8),
        Transform.rotate(
          angle: .785,
          child: Container(width: 5, height: 5, color: color),
        ),
        const SizedBox(width: 8),
        Container(width: width, height: 1, color: color.withValues(alpha: .55)),
      ],
    );
  }
}
