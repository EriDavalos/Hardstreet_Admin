import 'dart:async';

import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../drive_base.dart' show driveImagePreview, drivePhotoUrl;
import '../hs_api.dart' show HsSession;
import '../invitation_html.dart';
import '../invitation_model.dart';
import 'invitation_html_preview.dart';

// ==================================================================
// VISTA PREVIA DE UNA INVITACIÓN (Flutter)
// ==================================================================
// Es el MISMO modelo que genera el HTML de la liga pública
// (`invitation_html.dart`), así que lo que se ve aquí es lo que verá el
// cliente: portada de sobre con «Abrir invitación», polaroids, cuenta
// regresiva en vivo, familias, detalles, hashtag, itinerario y pie.
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
  });

  final Invitation invitation;

  /// Miniatura (tarjetas y catálogo).
  final bool compact;

  /// Ancho máximo de la invitación en la vista completa.
  final double maxWidth;

  /// ¿Se puede alternar entre la portada y la invitación?
  final bool allowCover;

  @override
  State<InvitationPreview> createState() => _InvitationPreviewState();
}

class _InvitationPreviewState extends State<InvitationPreview> {
  bool _cover = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant InvitationPreview old) {
    super.didUpdateWidget(old);
    if (old.invitation.eventAt != widget.invitation.eventAt ||
        old.invitation.sections != widget.invitation.sections ||
        old.compact != widget.compact) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// La cuenta regresiva se mueve sola (como en la liga publicada).
  void _syncTicker() {
    final inv = widget.invitation;
    final live =
        !widget.compact &&
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
    // pruebas y en la web se mantiene la maqueta (no hay WebView nativo).
    if (!widget.compact && !isTestEnvironment && !kWeb) {
      return InvitationHtmlPreview(html: buildInvitationHtml(_forPreview(inv)));
    }

    if (widget.compact) return _compact(inv, t, accent);

    final hasCover =
        inv.sectionOn('cover') &&
        inv.displayTitle.trim().isNotEmpty &&
        t.cover != 'abierta';
    final showCover = hasCover && widget.allowCover && _cover;

    return Column(
      children: [
        if (hasCover && widget.allowCover) _coverToggle(accent),
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
            setState(() => _cover = false);
          }),
          const SizedBox(width: 8),
          _toggleChip('Portada', _cover, accent, () {
            setState(() => _cover = true);
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

  // ---------------------------------------------------------------
  // Portada (sobre)
  // ---------------------------------------------------------------
  Widget _coverView(Invitation inv, InvitationTemplate t, Color accent) {
    final event = inv.eventDate;
    final parts = event == null ? null : invitationDateParts(event);
    final photo = t.cover == 'foto' && inv.photos.isNotEmpty
        ? inv.photos.first
        : '';

    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.panel.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'TIENES UNA INVITACIÓN',
                style: TextStyle(
                  fontSize: 7.5,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  color: t.soft,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              inv.displayTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _displayFamily(inv.fontKey),
                fontSize: 46,
                height: 1,
                fontStyle: inv.fontKey == 'romantica'
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 60,
              height: 1,
              color: accent.withValues(alpha: .55),
            ),
            const SizedBox(height: 12),
            Text(
              parts != null
                  ? '${_cap(parts.weekday)} ${parts.day} · '
                        '${_cap(parts.month)} ${parts.year}'
                  : inv.dateText.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 1.8,
                color: t.soft,
              ),
            ),
            const SizedBox(height: 26),
            Material(
              color: accent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() => _cover = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 13,
                  ),
                  child: Text(
                    'ABRIR INVITACIÓN ✨',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                      color: accent.computeLuminance() > .32
                          ? const Color(0xFF10131A)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
              gradient: RadialGradient(
                center: const Alignment(0, -.2),
                radius: 1.1,
                colors: [t.panel, t.bg],
              ),
            ),
          ),
        if (photo.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(color: t.bg.withValues(alpha: .55)),
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
                  if (inv.sectionOn('families'))
                    _families(inv, t, accent, scale),
                  if (inv.sectionOn('details')) _details(inv, t, accent, scale),
                  if (inv.sectionOn('hashtag')) _hashtag(inv, t, accent, scale),
                  if (inv.sectionOn('itinerary'))
                    _itinerary(inv, t, accent, scale),
                  if (inv.sectionOn('footer')) _footer(inv, t, accent, scale),
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

  Widget _mainCard(
    Invitation inv,
    InvitationTemplate t,
    Color accent,
    double s,
  ) {
    final event = inv.eventDate;
    final parts = event == null ? null : invitationDateParts(event);
    final photos = inv.photos.take(3).toList(growable: false);
    final quote = inv.quoteText;

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
          if (t.photos == 'portada' && photos.isNotEmpty) ...[
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
          if (t.photos != 'portada' && photos.isNotEmpty) ...[
            SizedBox(height: 22 * s),
            if (t.photos == 'arco')
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
          if (quote.isNotEmpty) ...[
            SizedBox(height: 18 * s),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14 * s),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(14 * s),
                border: Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: Column(
                children: [
                  Text(
                    '“',
                    style: TextStyle(
                      fontFamily: _displayFamily(inv.fontKey),
                      fontSize: 24 * s,
                      height: .7,
                      color: accent,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    quote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _displayFamily(inv.fontKey),
                      fontStyle: FontStyle.italic,
                      fontSize: 10.5 * s,
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
            _countdown(event, t, accent, s),
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
              if (i > 0)
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
    return _sectionBlock(
      t,
      accent,
      s,
      title: 'Con mi familia',
      children: [
        for (final f in families)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: 8 * s),
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(14 * s),
              border: Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: Column(
              children: [
                Text(
                  f.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _displayFamily('clasica'),
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                SizedBox(height: 2 * s),
                Text(
                  '♥',
                  style: TextStyle(fontSize: 8 * s, color: accent),
                ),
                SizedBox(height: 4 * s),
                for (final n in f.names)
                  Padding(
                    padding: EdgeInsets.only(bottom: 2 * s),
                    child: Text(
                      n,
                      textAlign: TextAlign.center,
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
            margin: EdgeInsets.only(bottom: 8 * s),
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(14 * s),
              border: Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: Column(
              children: [
                if (t.ornament == 'floral') ...[
                  _RibbonMark(size: 22 * s, color: accent),
                  SizedBox(height: 3 * s),
                ],
                Text(d.icon, style: TextStyle(fontSize: 17 * s)),
                SizedBox(height: 5 * s),
                Text(
                  d.title,
                  textAlign: TextAlign.center,
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
                    textAlign: TextAlign.center,
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
        if (inv.rsvpPhone.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 12 * s),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(14 * s),
              border: Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: Column(
              children: [
                if (t.ornament == 'floral')
                  _ButterflyMark(size: 24 * s, color: accent)
                else
                  Text('💌', style: TextStyle(fontSize: 17 * s)),
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
        Positioned.fill(
          child: Opacity(opacity: .24, child: _photo(media)),
        ),
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
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16 * s),
      padding: EdgeInsets.symmetric(vertical: 18 * s, horizontal: 14 * s),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: accent.withValues(alpha: .25)),
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
            color: t.panel,
            borderRadius: BorderRadius.circular(14 * s),
            border: Border.all(color: accent.withValues(alpha: .25)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < stops.length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    ),
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * s),
      child: Column(
        children: [
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
