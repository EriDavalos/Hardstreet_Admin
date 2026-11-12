import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hardstreet_admin/modules/drive/services/drive_api_service.dart'
    show DriveApiService;
import 'package:hardstreet_admin/modules/drive/services/drive_base.dart'
    show driveImagePreview, drivePublicUrl;
import 'package:hardstreet_admin/modules/drive/services/drive_scope.dart';
import 'package:hardstreet_admin/core/access/hs_access.dart';
import 'package:hardstreet_admin/core/api/hs_api.dart';
import 'package:hardstreet_admin/modules/invitations/components/component_catalog.dart';
import 'package:hardstreet_admin/modules/invitations/components/templates/custom_invitation_templates.dart';
import 'package:hardstreet_admin/modules/invitations/components/templates/invitation_templates.dart';
import 'package:hardstreet_admin/modules/invitations/templates/invitation_html.dart';
import 'package:hardstreet_admin/modules/invitations/models/invitation_model.dart';
import 'package:hardstreet_admin/core/platform/open_html.dart';
import 'package:hardstreet_admin/core/platform/open_url.dart';
import 'package:hardstreet_admin/app/theme.dart';
import 'package:hardstreet_admin/widgets/common.dart';
import 'package:hardstreet_admin/modules/drive/widgets/drive_folder_picker.dart';
import 'package:hardstreet_admin/modules/drive/widgets/drive_photo_picker.dart';
import 'package:hardstreet_admin/widgets/hs_modal.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';
import 'package:hardstreet_admin/modules/invitations/widgets/invitation_preview.dart';
import 'package:hardstreet_admin/modules/invitations/widgets/invitation_template_dialog.dart';

// ==================================================================
// MÓDULO INVITACIONES
// ==================================================================
// Se elige una PLANTILLA (agrupadas por ocasión: XV, Boda, Cumpleaños), se
// personaliza el diseño y se comparte una liga con el cliente.
//
//   · El LISTADO enseña la miniatura de cada invitación, si está publicada
//     y sus acciones (editar, compartir, publicar, eliminar).
//   · El EDITOR es una ventana de trabajo: las herramientas viven en un
//     riel lateral y la VISTA PREVIA EN VIVO ocupa el lienzo. La vista previa
//     usa el mismo modelo que el HTML público, así que no hay sorpresas al
//     compartir.
//   · COMPARTIR publica la invitación (la liga se crea al publicar) y deja
//     la dirección lista para copiar, abrir o mandar por WhatsApp.
//
// El módulo NO guarda categorías: `occasion` es solo la etiqueta que hereda
// de la plantilla para el encabezado del diseño.
// ==================================================================

class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key});

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  List<Invitation> _items = const [];
  bool _loading = true;
  bool _ready = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _allowed(String action) {
    final access = HsAccess.instance;
    // Sin permisos cargados (modo degradado) el panel ya no llega aquí; si
    // pasara, no se esconden las acciones: el backend vuelve a comprobar.
    return access.degraded || access.can(kInvitationsModuleKey, action);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // El catálogo local tiene que estar listo antes de pintar las miniaturas:
    // una invitación con plantilla propia debe conservar su portada y colores.
    await InvitationTemplateStore.load();
    if (!mounted) return;
    try {
      final result = await HsApi.invitations();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _ready = result.ready;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las invitaciones';
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------

  /// Nueva invitación: primero se elige la plantilla y el editor se abre
  /// con una muestra de ese diseño.
  Future<void> _newInvitation() async {
    await InvitationTemplateStore.load();
    if (!mounted) return;
    final key = await showHsModal<String>(
      context: context,
      builder: (_) => const _TemplateChooser(),
    );
    if (key == null || !mounted) return;
    await _edit(Invitation.samplePreset(key));
  }

  Future<void> _edit(Invitation invitation) async {
    await InvitationTemplateStore.load();
    if (!mounted) return;
    final saved = await showHsModal<Invitation>(
      context: context,
      builder: (_) => _InvitationEditor(invitation: invitation),
    );
    if (saved == null || !mounted) return;
    await _load();
  }

  Future<void> _delete(Invitation invitation) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('¿Eliminar «${invitation.panelName}»?'),
        content: const Text(
          'La invitación deja de aparecer en el panel y su liga deja de '
          'funcionar. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await HsApi.deleteInvitation(invitation.id);
      await _load();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    }
  }

  /// Publica o despublica. Despublicar deja la liga guardada pero sin servir.
  Future<void> _togglePublished(Invitation invitation) async {
    final goingOff = invitation.published;
    if (goingOff) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('¿Despublicar la invitación?'),
          content: const Text(
            'La liga que ya compartiste deja de abrirse. La invitación se '
            'queda guardada y la puedes volver a publicar cuando quieras.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Despublicar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await HsApi.publishInvitation(invitation.id, !goingOff);
      await _load();
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
    }
  }

  /// Compartir: regenera el HTML con el diseño actual (el guardado puede ser
  /// de una versión anterior), publica si hace falta y enseña la dirección.
  Future<void> _share(Invitation invitation) async {
    var current = invitation;
    if (!current.shareable) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Publicar para compartir'),
          content: Text(
            'Se crea la liga pública de «${current.panelName}» y cualquiera '
            'que la tenga podrá abrir la invitación en su navegador.\n\n'
            'Puedes despublicarla cuando quieras: la liga deja de abrirse.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.public_rounded, size: 18),
              label: const Text('Publicar y compartir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      // El HTML guardado puede ser de antes del rediseño: se regenera con la
      // plantilla y los datos actuales para que la liga sea la misma que la
      // vista previa (y conserve la animación).
      current = await HsApi.saveInvitation(current);
      if (!current.shareable) {
        current = await HsApi.publishInvitation(current.id, true);
      }
    } on ApiException catch (e) {
      HsToast.error(e.message, details: e.details);
      return;
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    if (current.shareUrl.isEmpty) {
      HsToast.error(
        'La invitación no tiene liga',
        details: 'Vuelve a guardarla.',
      );
      return;
    }
    final changed = await showHsModal<bool>(
      context: context,
      builder: (_) => _ShareDialog(invitation: current),
    );
    if (changed == true && mounted) await _load();
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final published = _items.where((i) => i.published).length;
    final drafts = _items.length - published;

    return PageContainer(
      module: kInvitationsModuleKey,
      title: kInvitationsModuleName,
      description:
          'Plantillas de invitaciones para XV, bodas y cumpleaños: '
          'personaliza el diseño, velo antes de guardar y comparte una liga '
          'con el cliente.',
      icon: Icons.mail_outline_rounded,
      onRefresh: _load,
      stats: [
        StatPill(
          icon: Icons.celebration_outlined,
          label:
              '${_items.length} ${_items.length == 1 ? 'invitación' : 'invitaciones'}',
        ),
        StatPill(
          icon: Icons.public_rounded,
          label: '$published ${published == 1 ? 'publicada' : 'publicadas'}',
        ),
        StatPill(
          icon: Icons.edit_note_outlined,
          label: '$drafts ${drafts == 1 ? 'borrador' : 'borradores'}',
        ),
      ],
      actions: [
        HsActionButton(
          icon: Icons.add_rounded,
          label: 'Nueva invitación',
          onPressed: _allowed('create') ? _newInvitation : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_ready) ...[
            _MigrationNotice(scheme: scheme),
            const SizedBox(height: 14),
          ],
          if (_loading)
            const ListSkeleton(lines: 3, cardHeight: 190)
          else if (_error != null)
            _errorCard(scheme)
          else if (_items.isEmpty)
            EmptyState(
              icon: Icons.mail_outline_rounded,
              title: 'Todavía no hay invitaciones',
              message:
                  'Elige una plantilla para XV, boda o cumpleaños, '
                  'cámbiale los textos, las fotos y los colores, y comparte '
                  'la liga con tu cliente.',
              actionLabel: _allowed('create') ? 'Crear una invitación' : null,
              onAction: _allowed('create') ? _newInvitation : null,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1080
                    ? 3
                    : width >= 700
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: columns == 1 ? 322 : 300,
                  ),
                  itemBuilder: (context, i) => _card(context, _items[i]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Invitation inv) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _allowed('update') ? () => _edit(inv) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InvitationPreview(invitation: inv, compact: true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            inv.panelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              inv.templateRecipe.name,
                              if (inv.dateText.trim().isNotEmpty)
                                inv.dateText.trim(),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          _StatusChip(published: inv.published),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Compartir',
                      onPressed: inv.id > 0 ? () => _share(inv) : null,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Acciones de ${inv.panelName}',
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _edit(inv);
                          case 'share':
                            _share(inv);
                          case 'publish':
                            _togglePublished(inv);
                          case 'delete':
                            _delete(inv);
                        }
                      },
                      itemBuilder: (_) => [
                        if (_allowed('update'))
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('Compartir'),
                        ),
                        if (_allowed('update'))
                          PopupMenuItem(
                            value: 'publish',
                            child: Text(
                              inv.published ? 'Despublicar' : 'Publicar',
                            ),
                          ),
                        if (_allowed('delete'))
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

/// Aviso cuando falta la migración (la lista llega vacía a propósito).
class _MigrationNotice extends StatelessWidget {
  const _MigrationNotice({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warn.withValues(alpha: .30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded, size: 18, color: AppColors.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Falta aplicar la migración del módulo '
              '(Hardstreet-DB/2026-10-30_modulo_invitaciones.sql) en la base '
              'del panel. Hasta entonces no se pueden guardar invitaciones.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Publicada» / «Borrador».
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.published});

  final bool published;

  @override
  Widget build(BuildContext context) {
    final color = published ? const Color(0xFF2F9E5B) : AppColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        published ? 'Publicada' : 'Borrador',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ==================================================================
// CATÁLOGO DE PLANTILLAS
// ==================================================================

/// Los efectos de ambiente que puede llevar la invitación.
///
/// El HTML original trae pétalos; estos son los que se pueden elegir en su
/// lugar. `petalos` es el valor por defecto (una invitación vieja sin efecto
/// guardado también se ve así).
const List<({String key, String label, String hint, IconData icon})> _effects =
    [
      (
        key: 'petalos',
        label: 'Pétalos',
        hint: 'Flotan y caen suave',
        icon: Icons.local_florist_outlined,
      ),
      (
        key: 'burbujas',
        label: 'Burbujas',
        hint: 'Suben y brillan',
        icon: Icons.bubble_chart_outlined,
      ),
      (
        key: 'destellos',
        label: 'Destellos',
        hint: 'Estrellas doradas',
        icon: Icons.auto_awesome_outlined,
      ),
      (
        key: 'corazones',
        label: 'Corazones',
        hint: 'Flotan con latido',
        icon: Icons.favorite_border_rounded,
      ),
      (
        key: 'confeti',
        label: 'Confeti',
        hint: 'Fiesta que gira',
        icon: Icons.celebration_outlined,
      ),
      (
        key: 'ninguno',
        label: 'Sin efectos',
        hint: 'Solo el diseño',
        icon: Icons.block_outlined,
      ),
    ];

class _InvitationEditor extends StatefulWidget {
  const _InvitationEditor({required this.invitation});

  final Invitation invitation;

  @override
  State<_InvitationEditor> createState() => _InvitationEditorState();
}

/// Fondos claros y oscuros que combinan con las plantillas.
const List<String> _bgPalette = [
  'FFFBF7',
  'E8CFCD',
  'FDF2E9',
  'EAF2ED',
  'EDE9F7',
  '1B1030',
  '0B1220',
];

/// Las portadas disponibles. Son independientes de la plantilla: el mismo
/// sobre se puede combinar con flores, papel, noche o terciopelo.
const List<({String key, String label, String hint, IconData icon})> _covers = [
  (
    key: 'rosa',
    label: 'Rosa Pastel',
    hint: 'Arco floral, pétalos y brillo suave.',
    icon: Icons.local_florist_outlined,
  ),
  (
    key: 'carta',
    label: 'Carta',
    hint: 'Papel doblado, sello de cera y caligrafía.',
    icon: Icons.mail_outline,
  ),
  (
    key: 'xv',
    label: 'Portada de XV',
    hint: 'Corona, el número 15, listones y confeti.',
    icon: Icons.workspace_premium_outlined,
  ),
  (
    key: 'noche',
    label: 'Noche estrellada',
    hint: 'Luna, constelaciones y aire de gala.',
    icon: Icons.auto_awesome,
  ),
  (
    key: 'cortina',
    label: 'Cortina',
    hint: 'Terciopelo, luces y apertura de teatro.',
    icon: Icons.theaters_outlined,
  ),
  (
    key: 'clasica',
    label: 'Clásica',
    hint: 'Monograma, doble marco y papel fino.',
    icon: Icons.diamond_outlined,
  ),
];

/// Las herramientas del editor. El riel lateral y el encabezado del panel
/// usan la misma lista para no desincronizarse.
const List<({IconData icon, String label, String hint})> _editorTools = [
  (
    icon: Icons.edit_note_rounded,
    label: 'Datos',
    hint: 'Textos, fecha y lugar',
  ),
  (
    icon: Icons.widgets_outlined,
    label: 'Items',
    hint: 'Arrastra, edita y ordena',
  ),
  (
    icon: Icons.palette_outlined,
    label: 'Diseño',
    hint: 'Plantilla, color y efectos',
  ),
  (
    icon: Icons.photo_library_outlined,
    label: 'Fotos',
    hint: 'Polaroids y fondos',
  ),
  (
    icon: Icons.article_outlined,
    label: 'Contenido',
    hint: 'Familias, detalles y música',
  ),
  (
    icon: Icons.ios_share_rounded,
    label: 'Publicar',
    hint: 'Liga y visibilidad',
  ),
];

class _InvitationEditorState extends State<_InvitationEditor> {
  late final TextEditingController _title;
  late final TextEditingController _headline;
  late final TextEditingController _subheadline;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _place;
  late final TextEditingController _address;
  late final TextEditingController _message;
  late final TextEditingController _dress;
  late final TextEditingController _phone;
  late final TextEditingController _eventAt;
  late final TextEditingController _quote;
  late final TextEditingController _occasionText;
  late final TextEditingController _verticalTitle;
  late final TextEditingController _arcTitle;
  late final TextEditingController _envelopeText;
  late final TextEditingController _familiesTitle;
  late final TextEditingController _detailsTitle;
  late final TextEditingController _detailsIntro;
  late final TextEditingController _itineraryTitle;
  late final TextEditingController _hashtagIntro;
  late final TextEditingController _memoriesTitle;
  late final TextEditingController _memoriesIntro;
  late final TextEditingController _memoriesFolder;
  late final TextEditingController _footerMessage;
  late final TextEditingController _bgMedia;
  late final TextEditingController _detailsMedia;
  late final List<_FamilyRow> _familyRows;
  late final List<_DetailRow> _detailRows;
  late final List<_StopRow> _stopRows;
  late final TextEditingController _hashtag;
  late final TextEditingController _music;

  late String _template;
  late String _preset;
  late Map<String, String> _componentDesigns;
  late String _accent;
  late String _font;
  late String _bgColor;
  late String _effect;
  late String _coverStyle;
  late String _coverBackdrop;
  late List<String> _sections;
  late List<String> _sectionOrder;
  late List<String> _photos;
  late bool _published;

  /// El componente que se está inspeccionando en el panel «Componentes».
  String? _selectedLayer;

  bool _saving = false;
  String? _error;

  /// Herramienta activa del editor.
  int _designTab = 0;

  /// Estado del panel lateral. `null` significa automático: abierto en
  /// escritorio y cerrado en pantallas angostas para que la vista previa
  /// tenga todo el espacio.
  bool? _panelOpen;

  /// El lienzo alterna entre una vista de teléfono y una de computadora.
  bool _previewDesktop = false;

  /// Pestaña del lienzo: 0 = Portada, 1 = Invitación, 2 = Todo.
  int _canvasTab = 2;

  bool get _editing => widget.invitation.id > 0;

  @override
  void initState() {
    super.initState();
    final inv = widget.invitation;
    _title = TextEditingController(text: inv.title);
    _headline = TextEditingController(text: inv.headline);
    _subheadline = TextEditingController(text: inv.subheadline);
    _date = TextEditingController(text: inv.dateText);
    _time = TextEditingController(text: inv.timeText);
    _place = TextEditingController(text: inv.placeName);
    _address = TextEditingController(text: inv.placeAddress);
    _message = TextEditingController(text: inv.message);
    _dress = TextEditingController(text: inv.dressCode);
    _phone = TextEditingController(text: inv.rsvpPhone);
    _eventAt = TextEditingController(text: inv.eventAt);
    _quote = TextEditingController(text: inv.quote);
    _occasionText = TextEditingController(text: inv.occasion);
    _verticalTitle = TextEditingController(text: inv.verticalTitle);
    _arcTitle = TextEditingController(text: inv.arcTitle);
    _envelopeText = TextEditingController(text: inv.envelopeText);
    _familiesTitle = TextEditingController(text: inv.familiesTitle);
    _detailsTitle = TextEditingController(text: inv.detailsTitle);
    _detailsIntro = TextEditingController(text: inv.detailsIntro);
    _itineraryTitle = TextEditingController(text: inv.itineraryTitle);
    _hashtagIntro = TextEditingController(text: inv.hashtagIntro);
    _memoriesTitle = TextEditingController(text: inv.memoriesTitle);
    _memoriesIntro = TextEditingController(text: inv.memoriesIntro);
    _memoriesFolder = TextEditingController(text: inv.memoriesFolder);
    _footerMessage = TextEditingController(text: inv.footerMessage);
    _bgMedia = TextEditingController(text: inv.bgMedia);
    _detailsMedia = TextEditingController(text: inv.detailsMedia);
    _familyRows = [for (final f in inv.families) _FamilyRow(f)];
    _detailRows = [for (final d in inv.details) _DetailRow(d)];
    _stopRows = [for (final s in inv.itinerary) _StopRow(s)];
    _hashtag = TextEditingController(text: inv.hashtag);
    _music = TextEditingController(text: inv.musicUrl);
    _template = inv.template;
    _preset = inv.preset;
    _componentDesigns = {
      for (final c in kInvitationComponents) c.key: inv.componentDesign(c.key),
    };
    _accent = inv.accent;
    _font = inv.font;
    _bgColor = inv.bgColor;
    _effect = inv.effect;
    _coverStyle = inv.coverStyleKey;
    _coverBackdrop = inv.coverBackdropKey;
    _sections = List<String>.of(inv.sections);
    _sectionOrder = List<String>.of(inv.flowSectionOrder);
    _photos = List<String>.of(inv.photos.take(3), growable: true);
    _published = inv.published;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _headline,
      _subheadline,
      _date,
      _time,
      _place,
      _address,
      _message,
      _dress,
      _phone,
      _eventAt,
      _quote,
      _occasionText,
      _verticalTitle,
      _arcTitle,
      _envelopeText,
      _familiesTitle,
      _detailsTitle,
      _detailsIntro,
      _itineraryTitle,
      _hashtagIntro,
      _memoriesTitle,
      _memoriesIntro,
      _memoriesFolder,
      _footerMessage,
      _bgMedia,
      _detailsMedia,
      _hashtag,
      _music,
    ]) {
      c.dispose();
    }
    for (final r in _familyRows) {
      r.dispose();
    }
    for (final r in _detailRows) {
      r.dispose();
    }
    for (final r in _stopRows) {
      r.dispose();
    }
    super.dispose();
  }

  /// La invitación tal como está ahora (lo que ve la vista previa).
  Invitation get _current => widget.invitation.copyWith(
    title: _title.text,
    template: _template,
    preset: _preset,
    componentDesigns: {..._componentDesigns, 'cover': _coverStyle},
    occasion: _occasionText.text,
    headline: _headline.text,
    subheadline: _subheadline.text,
    dateText: _date.text,
    timeText: _time.text,
    placeName: _place.text,
    placeAddress: _address.text,
    message: _message.text,
    dressCode: _dress.text,
    rsvpPhone: _phone.text,
    accent: _accent,
    font: _font,
    photos: [
      for (final p in _photos)
        if (p.trim().isNotEmpty) p.trim(),
    ],
    bgMedia: _bgMedia.text,
    detailsMedia: _detailsMedia.text,
    bgColor: _bgColor,
    effect: _effect,
    coverStyle: _coverStyle,
    coverBackdrop: _coverBackdrop,
    sections: _sections,
    sectionOrder: _sectionOrder,
    eventAt: _eventAt.text,
    quote: _quote.text,
    verticalTitle: _verticalTitle.text,
    arcTitle: _arcTitle.text,
    envelopeText: _envelopeText.text,
    familiesTitle: _familiesTitle.text,
    detailsTitle: _detailsTitle.text,
    detailsIntro: _detailsIntro.text,
    itineraryTitle: _itineraryTitle.text,
    hashtagIntro: _hashtagIntro.text,
    memoriesTitle: _memoriesTitle.text,
    memoriesIntro: _memoriesIntro.text,
    memoriesFolder: _memoriesFolder.text,
    footerMessage: _footerMessage.text,
    families: [for (final r in _familyRows) r.value],
    details: [for (final r in _detailRows) r.value],
    itinerary: [for (final r in _stopRows) r.value],
    hashtag: _hashtag.text,
    musicUrl: _music.text,
    published: _published,
  );

  /// Aplica una plantilla-compuesta sin tocar los textos, las fotos ni las
  /// listas de la invitación. La plantilla solo cambia la base visual, la
  /// portada y los diseños de los componentes.
  void _applyTemplateRecipe(InvitationTemplateRecipe recipe) {
    setState(() {
      _template = recipe.baseTemplate;
      _preset = recipe.key;
      _coverStyle = recipe.coverStyle;
      _coverBackdrop = recipe.coverBackdrop.isEmpty
          ? 'marfil'
          : recipe.coverBackdrop;
      _accent = recipe.accent;
      _bgColor = recipe.bgColor;
      _effect = recipe.effect;
      _font = recipe.font;
      _componentDesigns = templateRecipeComponents(recipe);
    });
  }

  Future<void> _changeTemplate() async {
    await InvitationTemplateStore.load();
    if (!mounted) return;
    final key = await showHsModal<String>(
      context: context,
      builder: (_) => const _TemplateChooser(),
    );
    if (key == null || !mounted) return;
    final recipe = invitationTemplateRecipeForKey(key);
    if (recipe != null) _applyTemplateRecipe(recipe);
  }

  /// Una foto del diseño que hay ahora en el lienzo. Es lo que se guarda
  /// cuando el usuario crea o actualiza una plantilla.
  InvitationTemplateRecipe _templateSnapshot({
    required String key,
    required String name,
    required String occasion,
    required String hint,
  }) {
    String hex(String value) => value.trim().replaceAll('#', '').toUpperCase();
    return InvitationTemplateRecipe(
      key: key,
      name: name,
      occasion: occasion,
      hint: hint,
      baseTemplate: _template,
      coverStyle: _coverStyle,
      coverBackdrop: _coverBackdrop,
      accent: hex(_accent),
      bgColor: hex(_bgColor),
      effect: _effect.trim().toLowerCase(),
      font: _font.trim().toLowerCase(),
      components: {
        for (final component in kInvitationComponents)
          if (component.key != 'cover')
            component.key:
                _componentDesigns[component.key] ?? component.fallback,
      },
      custom: true,
    );
  }

  /// Guarda el diseño actual como plantilla nueva o actualiza la que está
  /// aplicada. La plantilla se conserva en este equipo; la invitación y su
  /// liga pública no cambian.
  Future<void> _saveCurrentAsTemplate({bool overwrite = false}) async {
    if (_saving) return;
    final current = templateRecipeForInvitation(
      preset: _preset,
      template: _template,
    );
    final existing = overwrite ? InvitationTemplateStore.find(_preset) : null;
    final snapshot = _templateSnapshot(
      key: existing?.key ?? '',
      name: existing?.name ?? '${current.name} personalizada',
      occasion: existing?.occasion ?? current.occasion,
      hint:
          existing?.hint ??
          'Diseño creado desde el editor y guardado en este equipo.',
    );
    final picked = await showHsModal<InvitationTemplateRecipe>(
      context: context,
      builder: (_) => InvitationTemplateRecipeDialog(
        title: existing == null ? 'Guardar plantilla' : 'Editar plantilla',
        source: snapshot,
        editing: existing != null,
      ),
    );
    if (picked == null || !mounted) return;
    await InvitationTemplateStore.save(picked);
    if (!mounted) return;
    setState(() => _preset = picked.key);
    HsToast.success(
      existing == null ? 'Plantilla creada' : 'Plantilla actualizada',
      details: 'Se guardó en este equipo y ya aparece en el catálogo.',
    );
  }

  /// Abre en el navegador el HTML que se va a guardar (el de la liga),
  /// para revisarlo tal cual. En la web la vista previa del panel ya es la
  /// invitación y no hay archivos temporales.
  Future<void> _openInBrowser() async {
    final ok = await hsOpenHtmlInBrowser(buildInvitationHtml(_current));
    if (!ok && mounted) {
      HsToast.info(
        'La vista previa de la izquierda ya es la invitación. Para verla en '
        'el navegador, publica y abre su liga.',
      );
    }
  }

  Future<void> _pickPhoto({int? replaceAt}) async {
    if (_photos.length >= 3 && replaceAt == null) {
      HsToast.info('La invitación usa tres fotos: quita una para cambiarla.');
      return;
    }
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final slot = replaceAt == null ? _photos.length + 1 : replaceAt + 1;
    final picked = await showDrivePhotoPicker(
      context,
      drive: drive,
      title: 'Polaroid $slot de la invitación',
      note:
          'Se enlaza desde el servidor del Drive. Al guardar se hace pública '
          'para que la liga pueda mostrarla.',
      maxSelection: 1,
      minSelection: 1,
    );
    if (picked == null || picked.isEmpty) return;
    final url = drivePublicUrl(picked.first);
    setState(() {
      if (replaceAt != null && replaceAt < _photos.length) {
        _photos[replaceAt] = url;
      } else {
        _photos = [..._photos, url].take(3).toList(growable: true);
      }
    });
  }

  /// Elige la carpeta del Drive donde se guardarán las fotos de Recuerdos.
  Future<void> _pickMemoriesFolder() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final current = _memoriesFolder.text.trim();
    final segments = await showHsModal<List<String>>(
      context: context,
      builder: (_) => DriveFolderPicker(
        base: '',
        initial: current.isEmpty
            ? const <String>[]
            : current.split('/').where((s) => s.isNotEmpty).toList(),
        load: drive.listChildFolders,
        conflict: (_) => null,
        title: 'Carpeta de Recuerdos',
        subtitle:
            'Las fotos que suban los invitados se guardarán aquí, en el Drive.',
        confirmLabel: 'Usar esta carpeta',
      ),
    );
    if (segments == null) return;
    setState(() => _memoriesFolder.text = segments.join('/'));
  }

  Future<void> _save() async {
    final inv = _current;
    if (inv.displayTitle.trim().isEmpty) {
      setState(() {
        _error =
            'Escribe los nombres del evento (o el título de la '
            'invitación) antes de guardar.';
        _designTab = 0;
        // Si el panel estaba recogido, se abre para enseñar el campo que
        // hay que completar.
        _panelOpen = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await HsApi.saveInvitation(inv);
      // Las fotos de una invitación pública tienen que abrirse SIN sesión.
      if (saved.photos.isNotEmpty) {
        unawaited(
          DriveApiService.publishPublicPhotos('invitaciones', saved.photos),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.details == null || e.details!.isEmpty
            ? e.message
            : '${e.message} · ${e.details}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar la invitación';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    // En una laptop angosta el lienzo manda: el panel se abre al tocar una
    // herramienta, pero no arranca robándole ancho a la vista previa.
    final panelOpen = _panelOpen ?? width >= 1100;

    // Ventana de trabajo completa: sin márgenes ni tarjeta flotante. El
    // lienzo de la invitación es el protagonista y las herramientas viven
    // en el borde izquierdo.
    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.antiAlias,
      backgroundColor: scheme.surface,
      child: SizedBox.expand(
        child: SafeArea(
          child: Column(
            children: [
              _header(scheme, panelOpen: panelOpen),
              if (_error != null) _errorBanner(scheme),
              Expanded(
                child: _workspace(scheme, wide: wide, panelOpen: panelOpen),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, {required bool panelOpen}) {
    final recipe = templateRecipeForInvitation(
      preset: _preset,
      template: _template,
    );
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Container(
      key: const ValueKey('invitation-editor-header'),
      height: compact ? 58 : 66,
      padding: EdgeInsets.fromLTRB(compact ? 4 : 14, 6, compact ? 8 : 14, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cerrar editor',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 21),
          ),
          if (!compact) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.mail_outline_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editing ? 'Editar invitación' : 'Nueva invitación',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13.5 : 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${recipe.name} · ${recipe.occasion}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 9.5 : 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            _StatusChip(published: _published),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: panelOpen
                ? 'Ocultar herramientas'
                : 'Mostrar herramientas',
            style: IconButton.styleFrom(
              backgroundColor: panelOpen
                  ? scheme.primary.withValues(alpha: .10)
                  : null,
            ),
            onPressed: _saving
                ? null
                : () => setState(() => _panelOpen = !panelOpen),
            icon: Icon(
              Icons.tune_rounded,
              size: 20,
              color: panelOpen ? scheme.primary : null,
            ),
          ),
          if (!compact)
            IconButton(
              tooltip: 'Ver la invitación real',
              onPressed: _saving ? null : _openInBrowser,
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
            ),
          if (compact)
            IconButton.filled(
              key: const ValueKey('invitation-save'),
              tooltip: _saving ? 'Guardando…' : 'Guardar invitación',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 19),
            )
          else ...[
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const ValueKey('invitation-save'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Guardando…' : 'Guardar invitación'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorBanner(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// El espacio de trabajo: riel de herramientas, panel de ajustes y un
  /// lienzo grande con la invitación. En pantallas angostas el panel se
  /// abre encima del lienzo para no robarle ancho a la vista previa.
  Widget _workspace(
    ColorScheme scheme, {
    required bool wide,
    required bool panelOpen,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = (constraints.maxWidth * .29)
            .clamp(380.0, 440.0)
            .toDouble();
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolRail(scheme, compact: false),
              if (panelOpen)
                SizedBox(width: panelWidth, child: _toolPanel(scheme)),
              VerticalDivider(
                width: 1,
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
              Expanded(child: _canvas(scheme)),
            ],
          );
        }

        // El ancho del panel flotante nunca tapa el riel.
        final overlayWidth = constraints.maxWidth < 466
            ? constraints.maxWidth - 66
            : 400.0;
        return Stack(
          children: [
            Positioned.fill(left: 66, child: _canvas(scheme, compact: true)),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _toolRail(scheme, compact: true),
            ),
            if (panelOpen) ...[
              Positioned.fill(
                left: 66,
                child: GestureDetector(
                  onTap: () => setState(() => _panelOpen = false),
                  child: Container(color: Colors.black.withValues(alpha: .28)),
                ),
              ),
              Positioned(
                left: 66,
                top: 0,
                bottom: 0,
                width: overlayWidth,
                child: Material(
                  elevation: 16,
                  color: scheme.surface,
                  child: _toolPanel(scheme),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Riel vertical de herramientas, con el borde izquierdo de la ventana.
  Widget _toolRail(ColorScheme scheme, {required bool compact}) {
    return Container(
      key: const ValueKey('invitation-tool-rail'),
      width: compact ? 66 : 82,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .16),
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
      ),
      child: Column(
        children: [
          if (!compact) ...[
            const SizedBox(height: 10),
            Icon(
              Icons.grid_view_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              'EDITOR',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
          ] else
            const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 5 : 7,
                vertical: 2,
              ),
              children: [
                for (var i = 0; i < _editorTools.length; i++)
                  _toolRailItem(scheme, index: i, compact: compact),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolRailItem(
    ColorScheme scheme, {
    required int index,
    required bool compact,
  }) {
    final tool = _editorTools[index];
    final selected = _designTab == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('invitation-tab-$index'),
          borderRadius: BorderRadius.circular(12),
          onTap: _saving
              ? null
              : () => setState(() {
                  _designTab = index;
                  _panelOpen = true;
                }),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: compact ? 7 : 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: .38)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  tool.icon,
                  size: compact ? 18 : 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Text(
                  tool.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 8.5 : 9.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El panel de la herramienta activa, con su cabecera y el formulario.
  Widget _toolPanel(ColorScheme scheme) {
    final tool = _editorTools[_designTab.clamp(0, _editorTools.length - 1)];
    return Container(
      key: const ValueKey('invitation-tool-panel'),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 6, 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(tool.icon, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tool.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        tool.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ocultar herramientas',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _panelOpen = false),
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
          Expanded(child: _form(scheme)),
        ],
      ),
    );
  }

  /// El lienzo central: la vista previa ocupa todo el espacio disponible.
  Widget _canvas(ColorScheme scheme, {bool compact = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canvasColor = dark
        ? const Color(0xFF0A0F18)
        : const Color(0xFFE9E5DE);
    return Container(
      key: const ValueKey('invitation-canvas'),
      color: canvasColor,
      child: Column(
        children: [
          Container(
            height: compact ? 38 : 44,
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .74),
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .45),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 15,
                  color: scheme.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  compact ? 'VISTA PREVIA' : 'VISTA PREVIA EN VIVO',
                  style: TextStyle(
                    fontSize: compact ? 8.5 : 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2F9E5B),
                    shape: BoxShape.circle,
                  ),
                ),
                const Spacer(),
                if (!compact) ...[
                  Flexible(
                    child: Text(
                      _current.templateRecipe.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                _previewDeviceSwitch(scheme),
              ],
            ),
          ),
          _canvasTabs(scheme, compact: compact),
          Expanded(child: _canvasPreviews(scheme, compact: compact)),
        ],
      ),
    );
  }

  /// Portada, Invitación y Todo son tres vistas del mismo documento. Así la
  /// portada puede ocupar el lienzo completo en vez de quedar en una columna
  /// pequeña al lado de la invitación.
  Widget _canvasTabs(ColorScheme scheme, {required bool compact}) {
    return Container(
      height: compact ? 38 : 43,
      padding: EdgeInsets.fromLTRB(compact ? 7 : 14, 4, compact ? 7 : 14, 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .62),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Row(
            children: [
              _canvasTabButton(
                scheme,
                index: 0,
                keyName: 'invitation-canvas-tab-cover',
                icon: Icons.mark_email_unread_outlined,
                label: 'Portada',
                compact: compact,
              ),
              const SizedBox(width: 5),
              _canvasTabButton(
                scheme,
                index: 1,
                keyName: 'invitation-canvas-tab-invitation',
                icon: Icons.article_outlined,
                label: 'Invitación',
                compact: compact,
              ),
              const SizedBox(width: 5),
              _canvasTabButton(
                scheme,
                index: 2,
                keyName: 'invitation-canvas-tab-all',
                icon: Icons.view_agenda_outlined,
                label: 'Todo',
                compact: compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasTabButton(
    ColorScheme scheme, {
    required int index,
    required String keyName,
    required IconData icon,
    required String label,
    required bool compact,
  }) {
    final selected = _canvasTab == index;
    return Expanded(
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: ValueKey(keyName),
          borderRadius: BorderRadius.circular(9),
          onTap: _saving ? null : () => setState(() => _canvasTab = index),
          child: Container(
            height: compact ? 27 : 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: .40)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: compact ? 13 : 15,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9 : 10.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El lienzo cambia de vista sin recargar el editor. «Todo» abre el mismo
  /// documento público desde el sobre, para revisar la experiencia completa.
  Widget _canvasPreviews(ColorScheme scheme, {required bool compact}) {
    final tab = _canvasTab.clamp(0, 2);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 14,
        compact ? 6 : 10,
        compact ? 6 : 14,
        compact ? 6 : 14,
      ),
      child: _previewFrame(
        scheme,
        compact: compact,
        child: switch (tab) {
          0 => _coverPreview(),
          2 => _preview(allowCover: true, startAtCover: true),
          _ => _preview(allowCover: false),
        },
      ),
    );
  }

  Widget _previewFrame(
    ColorScheme scheme, {
    required bool compact,
    required Widget child,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(compact ? 12 : 18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _coverPreview() {
    // La portada sigue el mismo conmutador que la invitación: en teléfono se
    // dibuja en un lienzo de 430 px y en computadora ocupa todo el marco. Es
    // solo una vista: no debe abrir la invitación ni cambiar de documento al
    // hacer clic. La edición se hace desde los diseños de Items.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scheme = Theme.of(context).colorScheme;
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final phoneWidth = width < 430 ? width : 430.0;
          final phoneHeight = height < 900 ? height : 900.0;
          final preview = InvitationPreview(
            key: const ValueKey('invitation-cover-preview'),
            invitation: _current,
            allowCover: true,
            coverOnly: true,
          );
          if (_previewDesktop) return preview;
          return Center(
            child: Container(
              width: phoneWidth,
              height: phoneHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .75),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: preview,
            ),
          );
        },
      ),
    );
  }

  /// El conmutador entre la vista de teléfono y la de computadora.
  Widget _previewDeviceSwitch(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _previewDeviceButton(
            scheme,
            key: 'invitation-device-phone',
            icon: Icons.smartphone_rounded,
            tooltip: 'Vista de teléfono',
            desktop: false,
          ),
          _previewDeviceButton(
            scheme,
            key: 'invitation-device-desktop',
            icon: Icons.desktop_windows_rounded,
            tooltip: 'Vista de computadora',
            desktop: true,
          ),
        ],
      ),
    );
  }

  Widget _previewDeviceButton(
    ColorScheme scheme, {
    required String key,
    required IconData icon,
    required String tooltip,
    required bool desktop,
  }) {
    final selected = _previewDesktop == desktop;
    return IconButton(
      key: ValueKey(key),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 26),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.surface : Colors.transparent,
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      onPressed: _saving
          ? null
          : () => setState(() => _previewDesktop = desktop),
      icon: Icon(icon, size: 16),
    );
  }

  Widget _preview({bool allowCover = true, bool startAtCover = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final phoneWidth = width < 430 ? width : 430.0;
        final phoneHeight = height < 900 ? height : 900.0;
        final preview = InvitationPreview(
          key: const ValueKey('invitation-preview'),
          invitation: _current,
          maxWidth: _previewDesktop ? width : phoneWidth,
          allowCover: allowCover,
          startAtCover: startAtCover,
          editable: true,
          selectedSection: _selectedLayer,
          onSelectSection: _selectCanvasSection,
          onEditSection: _editCanvasSection,
          onRemoveSection: _hideCanvasSection,
          onDropComponent: _dropCanvasComponent,
        );
        if (_previewDesktop) return preview;
        // En la vista de teléfono se dibuja un lienzo de 430 × 900 (o el
        // espacio disponible si la ventana es más chica) para que la
        // invitación se lea como en un móvil real.
        return Center(
          child: Container(
            width: phoneWidth,
            height: phoneHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .75),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: preview,
          ),
        );
      },
    );
  }

  /// El fondo (foto o vídeo) de la invitación, con su liga pública.
  Widget _backgroundBlock(ColorScheme scheme) {
    final has = _bgMedia.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('invitation-bg-photo'),
                  onPressed: _saving ? null : _pickBackground,
                  icon: const Icon(Icons.wallpaper_outlined, size: 18),
                  label: Text(
                    has ? 'Cambiar foto de fondo' : 'Elegir foto de fondo',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quitar fondo',
                onPressed: _saving || !has
                    ? null
                    : () => setState(() => _bgMedia.text = ''),
                icon: const Icon(Icons.layers_clear_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _field(
            label: _template == 'boda-marfil'
                ? 'Fondo de la portada: foto o vídeo (liga pública)'
                : 'Fondo: foto o vídeo (liga pública)',
            controller: _bgMedia,
            hint: 'https://…/video.mp4',
            keyboard: TextInputType.url,
          ),
          Text(
            'Un .mp4/.webm se reproduce en bucle; una foto se queda fija. Si '
            'se deja vacío, manda el color de fondo.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Elige una foto del Drive para el fondo (el vídeo se pega como liga).
  Future<void> _pickBackground() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final picked = await showDrivePhotoPicker(
      context,
      drive: drive,
      title: 'Fondo de la invitación',
      note:
          'Se enlaza desde el servidor del Drive y se hace pública al '
          'guardar. Para un VÍDEO de fondo, pega su liga en el campo.',
      maxSelection: 1,
      minSelection: 1,
    );
    if (picked == null || picked.isEmpty) return;
    setState(() => _bgMedia.text = drivePublicUrl(picked.first));
  }

  /// El fondo (foto o vídeo) de la sección de detalles de Marfil & Oro.
  Widget _detailsBackgroundBlock(ColorScheme scheme) {
    final has = _detailsMedia.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('invitation-details-bg-photo'),
                  onPressed: _saving ? null : _pickDetailsBackground,
                  icon: const Icon(Icons.movie_outlined, size: 18),
                  label: Text(
                    has
                        ? 'Cambiar fondo de los detalles'
                        : 'Elegir fondo de los detalles',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quitar fondo de los detalles',
                onPressed: _saving || !has
                    ? null
                    : () => setState(() => _detailsMedia.text = ''),
                icon: const Icon(Icons.layers_clear_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _field(
            label: 'Fondo de los detalles: foto o vídeo (liga pública)',
            controller: _detailsMedia,
            hint: 'https://…/detalles.mp4',
            keyboard: TextInputType.url,
          ),
          Text(
            'Se coloca detrás de las tarjetas de «Los detalles». Un .mp4/.webm '
            'se reproduce en bucle; si se deja vacío, los detalles usan el '
            'fondo de la invitación.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Elige una foto del Drive para el fondo de los detalles.
  Future<void> _pickDetailsBackground() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final picked = await showDrivePhotoPicker(
      context,
      drive: drive,
      title: 'Fondo de los detalles',
      note:
          'Se enlaza desde el servidor del Drive y se hace pública al '
          'guardar. Para un VÍDEO, pega su liga en el campo.',
      maxSelection: 1,
      minSelection: 1,
    );
    if (picked == null || picked.isEmpty) return;
    setState(() => _detailsMedia.text = drivePublicUrl(picked.first));
  }

  /// El efecto activo; una invitación sin efecto guardado usa pétalos.
  String get _effectKey {
    final key = _effect.trim().toLowerCase();
    return _effects.any((e) => e.key == key) ? key : 'petalos';
  }

  /// Las tarjetas para elegir la animación de la invitación.
  Widget _effectsBlock(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in _effects)
          _effectCard(
            scheme,
            key: e.key,
            label: e.label,
            hint: e.hint,
            icon: e.icon,
            selected: _effectKey == e.key,
          ),
      ],
    );
  }

  /// La etiqueta visible de una portada.
  String _coverLabel(String key) {
    for (final c in _covers) {
      if (c.key == key) return c.label;
    }
    return _covers.first.label;
  }

  /// Las tarjetas de portada. Son miniaturas de color, no imágenes: así el
  /// selector no depende de archivos externos y se puede abrir sin conexión.
  Widget _coverStylesBlock(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in _covers)
          _coverCard(
            scheme,
            key: c.key,
            label: c.label,
            hint: c.hint,
            icon: c.icon,
            selected: _coverStyle == c.key,
          ),
      ],
    );
  }

  String _backdropLabel(String key) {
    for (final b in kInvitationCoverBackdrops) {
      if (b.key == key) return b.label;
    }
    return kInvitationCoverBackdrops.first.label;
  }

  /// Los tres fondos de la Carta. La miniatura anticipa la escena:
  /// marfil clásico, jardín verde o seda champán.
  Widget _cartaBackdropBlock(ColorScheme scheme) {
    final t = invitationTemplate(_template);
    final accent = colorOfHex(_accent) ?? t.accent;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in kInvitationCoverBackdrops)
          SizedBox(
            width: 112,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('invitation-carta-backdrop-${b.key}'),
                borderRadius: BorderRadius.circular(12),
                onTap: _saving
                    ? null
                    : () => setState(() => _coverBackdrop = b.key),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _coverBackdrop == b.key
                          ? accent
                          : scheme.outlineVariant.withValues(alpha: .7),
                      width: _coverBackdrop == b.key ? 1.6 : 1,
                    ),
                    color: scheme.surface,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: switch (b.key) {
                              'jardin' => const [
                                Color(0xFFDCE6D8),
                                Color(0xFFF6F0E5),
                                Color(0xFF8EA183),
                              ],
                              'seda' => const [
                                Color(0xFFF7EAD8),
                                Color(0xFFD8B98E),
                                Color(0xFFB08C60),
                              ],
                              _ => const [
                                Color(0xFFFFFCF5),
                                Color(0xFFF1E4D1),
                                Color(0xFFD8C3A6),
                              ],
                            },
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 8,
                              bottom: 7,
                              child: Icon(
                                Icons.local_florist,
                                size: 18,
                                color: b.key == 'jardin'
                                    ? const Color(0xFF5C7154)
                                    : accent.withValues(alpha: .75),
                              ),
                            ),
                            Positioned(
                              right: 7,
                              top: 6,
                              child: Icon(
                                Icons.circle_outlined,
                                size: 13,
                                color: const Color(0xFFB99A63),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        b.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _coverBackdrop == b.key
                              ? accent
                              : scheme.onSurface,
                        ),
                      ),
                      Text(
                        b.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// La miniatura usa la paleta de la plantilla elegida, no colores fijos:
  /// así Rosa Pastel enseña sus rosas y Marfil & Oro sus dorados.
  List<Color> _coverPreviewColors(String key) {
    final t = invitationTemplate(_template);
    final accent = colorOfHex(_accent) ?? t.accent;
    final bg = t.bg;
    final pale = Color.lerp(t.panel, bg, .28)!;
    final deep = Color.lerp(Color.lerp(bg, accent, .42)!, Colors.black, .42)!;
    return switch (key) {
      'carta' => [t.panel, Color.lerp(t.panel, bg, .55)!],
      'xv' => [Color.lerp(pale, Colors.white, .25)!, bg],
      'noche' => [deep, Color.lerp(deep, Colors.black, .48)!],
      'cortina' => [Color.lerp(deep, accent, .18)!, deep],
      'clasica' => [t.panel, pale],
      _ => [Color.lerp(t.panel, Colors.white, .25)!, bg],
    };
  }

  /// Cada miniatura tiene una composición distinta. No es solo un color:
  /// se reconoce la carta, el 15, el arco floral, la luna, el telón o el
  /// monograma antes de elegirla.
  Widget _coverThumb(String key, List<Color> colors) {
    final base = colors.last;
    final dark = base.computeLuminance() < .4;
    final occasion = _occasionText.text.trim().isEmpty
        ? invitationTemplate(_template).occasion
        : _occasionText.text.trim();
    final isXV =
        occasion.toLowerCase().contains('xv') ||
        occasion.toLowerCase().contains('quince');
    final fg = dark ? const Color(0xFFF8ECD2) : const Color(0xFF5A403B);
    final accent = dark
        ? const Color(0xFFE7C98B)
        : (colorOfHex(_accent) ?? invitationTemplate(_template).accent);
    Widget stars({int count = 5}) => Stack(
      children: [
        for (var i = 0; i < count; i++)
          Positioned(
            left: 8.0 + (i * 23) % 90,
            top: 5.0 + (i * 13) % 34,
            child: Icon(
              i.isEven ? Icons.star_rounded : Icons.auto_awesome,
              size: i % 3 == 0 ? 5 : 3.5,
              color: const Color(0xFFF3DCA6),
            ),
          ),
      ],
    );
    Widget miniPaper() => Center(
      child: Container(
        width: 52,
        height: 38,
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF5),
          border: Border.all(color: accent.withValues(alpha: .45)),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(height: 1, width: 30, color: fg.withValues(alpha: .25)),
              const SizedBox(height: 4),
              Text(
                'Para ti',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 6.5,
                  fontStyle: FontStyle.italic,
                  color: fg.withValues(alpha: .8),
                ),
              ),
              const SizedBox(height: 4),
              Container(height: 1, width: 20, color: fg.withValues(alpha: .18)),
            ],
          ),
        ),
      ),
    );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? .18 : .55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (key) {
        'carta' => Stack(
          fit: StackFit.expand,
          children: [
            miniPaper(),
            Positioned(
              right: 25,
              bottom: 4,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: const [
                    BoxShadow(color: Color(0x55000000), blurRadius: 3),
                  ],
                ),
                child: Icon(Icons.favorite, size: 6, color: Colors.white),
              ),
            ),
          ],
        ),
        'xv' => Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 2,
              child: Icon(Icons.workspace_premium, size: 10, color: accent),
            ),
            Text(
              isXV ? '15' : '✦',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 27,
                height: .95,
                fontWeight: FontWeight.w700,
                color: accent,
                shadows: const [
                  Shadow(color: Color(0x22000000), blurRadius: 2),
                ],
              ),
            ),
            Positioned(
              bottom: 3,
              child: Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                color: accent.withValues(alpha: .8),
                child: Text(
                  isXV ? 'MIS XV' : 'CELEBRA',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 4.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        'noche' => Stack(
          fit: StackFit.expand,
          children: [
            stars(count: 7),
            Positioned(
              top: 7,
              right: 9,
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF3DFAF),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .35),
                      blurRadius: 10,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Text(
                'NOCHE',
                style: TextStyle(
                  fontSize: 5.5,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: .82),
                ),
              ),
            ),
          ],
        ),
        'cortina' => Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 29,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: .45),
                      accent.withValues(alpha: .28),
                      Colors.black.withValues(alpha: .25),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 29,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: .25),
                      accent.withValues(alpha: .28),
                      Colors.black.withValues(alpha: .45),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(Icons.theaters_outlined, size: 19, color: accent),
            ),
          ],
        ),
        'clasica' => Center(
          child: Container(
            width: 58,
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: accent.withValues(alpha: .7)),
            ),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(color: accent.withValues(alpha: .35)),
              ),
              child: Center(
                child: Text(
                  'AB',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 14,
                    letterSpacing: 1.5,
                    color: fg.withValues(alpha: .82),
                  ),
                ),
              ),
            ),
          ),
        ),
        _ => Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 23,
              right: 23,
              top: 5,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: accent.withValues(alpha: .38)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(50),
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.local_florist_outlined,
                size: 16,
                color: accent.withValues(alpha: .72),
              ),
            ),
            Positioned(
              bottom: 5,
              left: 7,
              child: Icon(Icons.auto_awesome, size: 5, color: accent),
            ),
            Positioned(
              top: 7,
              right: 8,
              child: Icon(Icons.auto_awesome, size: 6, color: accent),
            ),
          ],
        ),
      },
    );
  }

  Widget _coverCard(
    ColorScheme scheme, {
    required String key,
    required String label,
    required String hint,
    required IconData icon,
    required bool selected,
  }) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final colors = _coverPreviewColors(key);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('invitation-cover-$key'),
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : () => setState(() => _coverStyle = key),
        child: Container(
          width: narrow ? 144 : 164,
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .12)
                : scheme.surfaceContainerHighest.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .65)
                  : scheme.outlineVariant.withValues(alpha: .55),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _coverThumb(key, colors),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 14,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _effectCard(
    ColorScheme scheme, {
    required String key,
    required String label,
    required String hint,
    required IconData icon,
    required bool selected,
  }) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('invitation-effect-$key'),
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : () => setState(() => _effect = key),
        child: Container(
          width: narrow ? 132 : 150,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .12)
                : scheme.surfaceContainerHighest.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .65)
                  : scheme.outlineVariant.withValues(alpha: .55),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 15,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// La plantilla aplicada. Se elige al crear la invitación; aquí se muestra
  /// con su miniatura para confirmar el diseño con el que se guardará.
  Widget _templatePicker(ColorScheme scheme) {
    final recipe = templateRecipeForInvitation(
      preset: _preset,
      template: _template,
    );
    final sample = Invitation.samplePreset(recipe.key);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .11),
            scheme.primary.withValues(alpha: .025),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 96,
              height: 132,
              // La miniatura se dibuja a tamaño real y se encoge: así el
              // adorno de la invitación no se desborda en 96 px.
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 360,
                  height: 480,
                  child: InvitationPreview(invitation: sample, compact: true),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${kInvitationComponents.length} componentes',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  recipe.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recipe.occasion,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  recipe.hint,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Plantilla aplicada',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  key: const ValueKey('invitation-change-template'),
                  onPressed: _saving ? null : _changeTemplate,
                  icon: const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 16,
                  ),
                  label: const Text('Cambiar plantilla'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  key: const ValueKey('invitation-template-save-design'),
                  onPressed: _saving
                      ? null
                      : () => _saveCurrentAsTemplate(overwrite: recipe.custom),
                  icon: Icon(
                    recipe.custom
                        ? Icons.save_rounded
                        : Icons.bookmark_add_outlined,
                    size: 15,
                  ),
                  label: Text(
                    recipe.custom
                        ? 'Actualizar esta plantilla'
                        : 'Guardar como plantilla',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Fecha del evento con calendario. Actualiza la fecha visible, la hora
  /// y la fecha ISO de la cuenta regresiva.
  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final current = parseInvitationDate(_eventAt.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 12),
      helpText: 'Fecha del evento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (picked == null || !mounted) return;
    final clock =
        parseInvitationClock(_time.text) ??
        (
          hour: current.hour == 0 && current.minute == 0 ? 19 : current.hour,
          minute: current.minute,
        );
    final at = DateTime(
      picked.year,
      picked.month,
      picked.day,
      clock.hour,
      clock.minute,
    );
    setState(() {
      _eventAt.text = invitationIsoMinutes(at);
      _date.text = invitationDateLabel(at);
      _time.text = invitationTimeLabel(at);
    });
  }

  /// Hora del evento con reloj. Solo toca la cuenta regresiva si ya hay
  /// una fecha elegida.
  Future<void> _pickEventTime() async {
    final parsed = parseInvitationClock(_time.text);
    final event = parseInvitationDate(_eventAt.text);
    final initial =
        parsed ?? (hour: event?.hour ?? 19, minute: event?.minute ?? 30);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: 'Hora del evento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time.text = invitationTimeLabel(
        DateTime(2000, 1, 1, picked.hour, picked.minute),
      );
      final base = parseInvitationDate(_eventAt.text);
      if (base != null) {
        _eventAt.text = invitationIsoMinutes(
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute),
        );
      }
    });
  }

  /// Reloj para las horas sueltas (detalles e itinerario).
  Future<void> _pickClock(TextEditingController controller) async {
    final parsed = parseInvitationClock(controller.text);
    final initial = parsed ?? (hour: 19, minute: 30);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: 'Hora',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      controller.text = invitationTimeLabel(
        DateTime(2000, 1, 1, picked.hour, picked.minute),
        upper: true,
      );
    });
  }

  Widget _countdownTile(ColorScheme scheme) {
    final event = parseInvitationDate(_eventAt.text);
    return Container(
      key: const ValueKey('invitation-event-at'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .26),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Icon(
            event == null ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 18,
            color: event == null ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              event == null
                  ? 'Elige la fecha y la hora para activar la cuenta regresiva.'
                  : 'Cuenta regresiva: ${invitationDateLabel(event)} · '
                        '${invitationTimeLabel(event)}',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (event != null)
            IconButton(
              tooltip: 'Quitar fecha del evento',
              visualDensity: VisualDensity.compact,
              onPressed: _saving
                  ? null
                  : () => setState(() => _eventAt.text = ''),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
        ],
      ),
    );
  }

  /// Las secciones que se pueden prender o apagar.
  Widget _sectionsBlock(ColorScheme scheme) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in kInvitationSections)
          if (_template == 'boda-marfil' || s.key != 'memories')
            FilterChip(
              key: ValueKey('invitation-section-${s.key}'),
              label: Text(s.label),
              selected: _sectionVisible(s.key),
              onSelected: _saving
                  ? null
                  : (on) => setState(() => _toggleSection(s.key, on)),
              visualDensity: VisualDensity.compact,
              labelStyle: const TextStyle(fontSize: 11),
            ),
      ],
    );
  }

  bool _sectionVisible(String key) =>
      _sections.isEmpty || _sections.contains(key);

  /// Prende o apaga una sección conservando el atajo "vacío = todas".
  void _toggleSection(String key, bool on) {
    final all = [for (final s in kInvitationSections) s.key];
    final active = _sections.isEmpty ? [...all] : List<String>.of(_sections);
    if (on) {
      if (!active.contains(key)) active.add(key);
    } else {
      // Una invitación sin ninguna sección no tendría sentido; además el
      // modelo usa la lista vacía para decir «todas».
      if (active.length <= 1) return;
      active.remove(key);
    }
    _sections = active.length == all.length ? const <String>[] : active;
  }

  void _moveLayer(int index, int delta) {
    final next = index + delta;
    if (index < 0 || next < 0 || next >= _sectionOrder.length) return;
    setState(() {
      final moved = _sectionOrder.removeAt(index);
      _sectionOrder.insert(next, moved);
    });
  }

  void _openLayerSettings(String key) {
    final target = switch (key) {
      'cover' => 2,
      'countdown' || 'rsvp' => 0,
      'photos' => 3,
      _ => 4,
    };
    setState(() {
      _designTab = target;
      _panelOpen = true;
    });
  }

  /// Selecciona un bloque desde el lienzo sin sacar al usuario de él.
  void _selectCanvasSection(String key) {
    if (_saving) return;
    setState(() => _selectedLayer = key);
  }

  /// El lápiz del bloque: abre el formulario que corresponde a ese ítem.
  void _editCanvasSection(String key) {
    if (_saving) return;
    setState(() {
      _selectedLayer = key;
      _panelOpen = true;
    });
    _openLayerSettings(key);
  }

  /// El bote de basura no borra los textos: oculta el ítem y lo deja en la
  /// biblioteca de Items para volver a insertarlo.
  void _hideCanvasSection(String key) {
    if (_saving) return;
    setState(() {
      _toggleSection(key, false);
      if (_selectedLayer == key) _selectedLayer = null;
    });
  }

  /// Suelta un ítem del panel en una zona del lienzo. Acepta componentes
  /// nuevos (`new:`), bloques que ya estaban en el flujo (`move:`) y diseños
  /// del catálogo (`design:details:lista`).
  void _dropCanvasComponent(String payload, String? beforeKey) {
    if (_saving) return;
    final sep = payload.indexOf(':');
    if (sep <= 0) return;
    final kind = payload.substring(0, sep);
    final rest = payload.substring(sep + 1).trim();

    if (kind == 'design') {
      final designSep = rest.indexOf(':');
      if (designSep <= 0) return;
      final key = rest.substring(0, designSep).trim();
      final design = rest.substring(designSep + 1).trim();
      final component = invitationComponentForKey(key);
      if (component == null || component.design(design) == null) return;
      setState(() {
        _componentDesigns[key] = design;
        if (key == 'cover') _coverStyle = design;
        if (!_sectionVisible(key)) _toggleSection(key, true);
        if (component.flow) {
          if (!_sectionOrder.contains(key)) _sectionOrder.add(key);
          if (beforeKey != key) {
            final oldIndex = _sectionOrder.indexOf(key);
            if (oldIndex >= 0) _sectionOrder.removeAt(oldIndex);
            var target = beforeKey == null
                ? _sectionOrder.length
                : _sectionOrder.indexOf(beforeKey);
            if (target < 0) target = _sectionOrder.length;
            _sectionOrder.insert(target, key);
          }
        }
        _selectedLayer = key;
      });
      return;
    }

    final key = rest;
    if (!kFlowInvitationComponents.contains(key)) return;
    if (beforeKey == key) return;
    setState(() {
      if (!_sectionOrder.contains(key)) _sectionOrder.add(key);
      if (!_sectionVisible(key)) _toggleSection(key, true);
      final oldIndex = _sectionOrder.indexOf(key);
      if (oldIndex >= 0) _sectionOrder.removeAt(oldIndex);
      var target = beforeKey == null
          ? _sectionOrder.length
          : _sectionOrder.indexOf(beforeKey);
      if (target < 0) target = _sectionOrder.length;
      _sectionOrder.insert(target, key);
      _selectedLayer = key;
    });
  }

  String _sectionLabelFor(String key) {
    for (final s in kInvitationSections) {
      if (s.key == key) return s.label;
    }
    return key;
  }

  IconData _sectionIcon(String key) => switch (key) {
    'cover' => Icons.mark_email_unread_outlined,
    'countdown' => Icons.timer_outlined,
    'quote' => Icons.format_quote_rounded,
    'photos' => Icons.photo_camera_back_outlined,
    'families' => Icons.groups_2_outlined,
    'details' => Icons.event_note_outlined,
    'hashtag' => Icons.tag_rounded,
    'memories' => Icons.photo_library_outlined,
    'itinerary' => Icons.route_outlined,
    'rsvp' => Icons.mark_email_read_outlined,
    'footer' => Icons.favorite_border_rounded,
    'music' => Icons.music_note_outlined,
    _ => Icons.layers_outlined,
  };

  String _layerSubtitle(String key) => switch (key) {
    'cover' => 'Portada ${_coverLabel(_coverStyle)}',
    'countdown' =>
      _eventAt.text.trim().isEmpty
          ? 'Sin fecha: no se verá'
          : 'Cuenta regresiva',
    'quote' =>
      _quote.text.trim().isEmpty
          ? 'Usa el mensaje de la tarjeta'
          : 'Frase de la tarjeta',
    'photos' =>
      '${_photos.where((p) => p.trim().isNotEmpty).length} de 3 polaroids',
    'families' => 'Padres, padrinos y familia',
    'details' => 'Lugar, fecha y vestimenta',
    'hashtag' => 'Etiqueta para compartir',
    'memories' => 'Álbum de los invitados',
    'itinerary' => 'Momentos del día',
    'rsvp' =>
      _phone.text.trim().isEmpty
          ? 'Sin número de WhatsApp'
          : 'Confirmación por WhatsApp',
    'footer' => 'Cierre de la invitación',
    'music' =>
      _music.text.trim().isEmpty ? 'Sin liga de música' : 'Audio de fondo',
    _ => 'Sección',
  };

  String _layerDescription(String key) => switch (key) {
    'cover' =>
      'La portada que recibe al invitado. Puedes cambiar entre '
          'Rosa Pastel, Carta, Noche estrellada y Cortina.',
    'countdown' =>
      'El reloj con días, horas, minutos y segundos hasta el evento.',
    'quote' => 'La frase destacada dentro de la tarjeta principal.',
    'photos' =>
      'Las polaroids con los recuerdos de la pareja o la quinceañera.',
    'families' => 'Las tarjetas de padres, padrinos y personas que acompañan.',
    'details' =>
      'Las tarjetas de lugar, fecha, vestimenta y demás indicaciones.',
    'hashtag' => 'La etiqueta que invita a compartir las fotos del evento.',
    'memories' =>
      'La galería donde los invitados suben sus fotos del evento. '
          'Solo está disponible en Marfil & Oro.',
    'itinerary' => 'El programa del día, con sus horarios y momentos.',
    'rsvp' => 'La tarjeta para confirmar la asistencia por WhatsApp.',
    'footer' => 'El mensaje de cierre y el crédito de Hardstreet.',
    'music' => 'El audio de ambiente y su botón de reproducción.',
    _ => 'Un componente de la invitación.',
  };

  /// El panel de componentes: biblioteca, visibilidad, orden e inspección.
  List<Widget> _layersChildren(ColorScheme scheme) {
    final hidden = [
      for (final s in kInvitationSections)
        if ((_template == 'boda-marfil' || s.key != 'memories') &&
            !_sectionVisible(s.key))
          s,
    ];
    return [
      _introCard(
        scheme,
        icon: Icons.widgets_outlined,
        title: 'Componentes de la invitación',
        text:
            'Cada objeto (portada, familias, detalles, itinerario…) reúne '
            'todos sus diseños en un mismo grupo. Toca uno para aplicarlo o '
            'arrástralo a la invitación para insertarlo con ese diseño. No se '
            'pierden los textos ni las fotos.',
      ),
      const SizedBox(height: 12),
      _layersTemplateCard(scheme),
      const SizedBox(height: 14),
      _sectionLabel('TODOS LOS DISEÑOS, POR COMPONENTE', scheme),
      const SizedBox(height: 4),
      Text(
        'El catálogo completo de la invitación. Cada tarjeta se puede '
        'seleccionar y arrastrar al lienzo.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      _componentDesignCatalog(scheme),
      const SizedBox(height: 18),
      _sectionLabel('BIBLIOTECA DE COMPONENTES', scheme),
      const SizedBox(height: 4),
      Text(
        'Los componentes ocultos quedan aquí, listos para volver a la '
        'invitación con un toque.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      if (hidden.isEmpty)
        Text(
          'Todos los componentes están activos en esta invitación.',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        )
      else
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final s in hidden)
              Draggable<String>(
                data: 'new:${s.key}',
                feedback: _dragFeedback(scheme, s.label),
                child: ActionChip(
                  key: ValueKey('invitation-add-component-${s.key}'),
                  avatar: Icon(
                    _sectionIcon(s.key),
                    size: 15,
                    color: scheme.primary,
                  ),
                  label: Text(s.label),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _toggleSection(s.key, true);
                          _selectedLayer = s.key;
                        }),
                ),
              ),
          ],
        ),
      const SizedBox(height: 18),
      _sectionLabel('ITEMS ARRASTRABLES', scheme),
      const SizedBox(height: 4),
      Text(
        'Arrastra un ítem de esta lista y suéltalo en la invitación para '
        'insertarlo o moverlo. También puedes usar las flechas del inspector. '
        'El orden se guarda y se aplica a la liga.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      for (final key in _sectionOrder) ...[
        _layerTile(scheme, key),
        const SizedBox(height: 7),
      ],
      const SizedBox(height: 16),
      _sectionLabel('COMPONENTES FIJOS', scheme),
      const SizedBox(height: 4),
      Text(
        'La portada, la cuenta regresiva, la frase, las fotos, la '
        'confirmación y la música tienen un lugar propio en el diseño.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      for (final key in const [
        'cover',
        'countdown',
        'quote',
        'photos',
        'rsvp',
        'music',
      ]) ...[_fixedLayerTile(scheme, key), const SizedBox(height: 7)],
      if (_selectedLayer != null) ...[
        const SizedBox(height: 5),
        _layerInspector(scheme),
      ],
      const SizedBox(height: 12),
      Text(
        'Los componentes fijos no se reordenan para no romper el ritmo de '
        'la invitación; puedes ocultarlos y restaurarlos desde la biblioteca.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// Una tarjeta de diseño. Se puede tocar para aplicarla o arrastrar para
  /// insertar el componente (con ese diseño) en el lienzo.
  Widget _componentDesignTile(
    ColorScheme scheme,
    InvitationComponent component,
    InvitationComponentDesign design,
    String current,
  ) {
    final selected = current == design.key;
    final color = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: .70);
    final itemKey = component.key == 'cover'
        ? 'invitation-item-cover-${design.key}'
        : 'invitation-item-design-${component.key}-${design.key}';
    return SizedBox(
      width: 106,
      child: Draggable<String>(
        data: 'design:${component.key}:${design.key}',
        feedback: _dragFeedback(scheme, '${component.label} · ${design.label}'),
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: .08)
              : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey(itemKey),
            borderRadius: BorderRadius.circular(10),
            onTap: _saving
                ? null
                : () => _chooseComponentDesign(component.key, design.key),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.fromLTRB(7, 6, 6, 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color, width: selected ? 1.5 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (component.key == 'cover')
                        Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: _coverPreviewColors(design.key),
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 13,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          design.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    design.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      height: 1.25,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dragFeedback(ColorScheme scheme, String label) {
    return Material(
      elevation: 8,
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.drag_indicator_rounded,
              size: 15,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La plantilla-compuesta activa, con acceso al catálogo completo y a
  /// guardar el diseño actual como plantilla propia.
  Widget _layersTemplateCard(ColorScheme scheme) {
    final recipe = templateRecipeForInvitation(
      preset: _preset,
      template: _template,
    );
    final custom = recipe.custom;
    return Container(
      key: const ValueKey('invitation-applied-template'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${kInvitationComponents.length} componentes · '
                      '${recipe.occasion}${custom ? ' · TUYA' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('invitation-template-change'),
                onPressed: _saving ? null : _changeTemplate,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          OutlinedButton.icon(
            key: const ValueKey('invitation-template-save'),
            onPressed: _saving
                ? null
                : () => _saveCurrentAsTemplate(overwrite: custom),
            icon: Icon(
              custom ? Icons.save_rounded : Icons.bookmark_add_outlined,
              size: 15,
            ),
            label: Text(
              custom ? 'Actualizar plantilla' : 'Guardar como plantilla',
              style: const TextStyle(fontSize: 10.5),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          ),
        ],
      ),
    );
  }

  /// Catálogo completo: un grupo por componente, con todos sus diseños a la
  /// vista. No hay acordeones: el usuario ve todo lo disponible de una vez.
  Widget _componentDesignCatalog(ColorScheme scheme) {
    return Column(
      key: const ValueKey('invitation-design-catalog'),
      children: [
        for (var i = 0; i < kInvitationComponents.length; i++) ...[
          _componentDesignCard(scheme, kInvitationComponents[i]),
          if (i < kInvitationComponents.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _componentDesignCard(
    ColorScheme scheme,
    InvitationComponent component,
  ) {
    final current = component.key == 'cover'
        ? _coverStyle
        : (_componentDesigns[component.key] ?? component.fallback);
    final active = _sectionVisible(component.key);
    return Container(
      key: ValueKey('invitation-design-group-${component.key}'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(component.icon, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  component.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary.withValues(alpha: .09)
                      : scheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? scheme.primary.withValues(alpha: .28)
                        : scheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: Text(
                  active ? 'EN LA INVITACIÓN' : 'OCULTO',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            component.hint,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final design in component.designs)
                _componentDesignTile(scheme, component, design, current),
            ],
          ),
        ],
      ),
    );
  }

  /// Aplica un diseño desde el catálogo y se asegura de que el componente
  /// esté presente en la invitación. En los componentes de flujo conserva
  /// su posición actual (o lo agrega al final si estaba oculto).
  void _chooseComponentDesign(String key, String design) {
    if (_saving) return;
    final component = invitationComponentForKey(key);
    if (component == null || component.design(design) == null) return;
    setState(() {
      _componentDesigns[key] = design;
      if (key == 'cover') _coverStyle = design;
      if (!_sectionVisible(key)) _toggleSection(key, true);
      if (component.flow && !_sectionOrder.contains(key)) {
        _sectionOrder.add(key);
      }
      _selectedLayer = key;
    });
  }

  Widget _layerTile(ColorScheme scheme, String key) {
    final visible = _sectionVisible(key);
    final selected = _selectedLayer == key;
    return Container(
      key: ValueKey('invitation-layer-$key'),
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: .08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: .70)
              : scheme.outlineVariant.withValues(alpha: .70),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _saving ? null : () => setState(() => _selectedLayer = key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(
              children: [
                Draggable<String>(
                  data: 'move:$key',
                  feedback: _dragFeedback(scheme, _sectionLabelFor(key)),
                  child: Tooltip(
                    message: 'Arrastrar a la invitación',
                    child: Padding(
                      key: ValueKey('invitation-drag-$key'),
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('invitation-toggle-$key'),
                  tooltip: visible ? 'Ocultar capa' : 'Mostrar capa',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _toggleSection(key, !visible)),
                  icon: Icon(
                    visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: visible ? scheme.primary : scheme.outline,
                  ),
                ),
                Icon(
                  _sectionIcon(key),
                  size: 17,
                  color: visible ? scheme.onSurface : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sectionLabelFor(key),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: visible
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        visible ? _layerSubtitle(key) : 'Oculta',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                IconButton(
                  key: ValueKey('invitation-edit-$key'),
                  tooltip: 'Abrir ajustes del componente',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() => _selectedLayer = key);
                          _openLayerSettings(key);
                        },
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fixedLayerTile(ColorScheme scheme, String key) {
    final visible = _sectionVisible(key);
    final selected = _selectedLayer == key;
    return Container(
      key: ValueKey('invitation-fixed-layer-$key'),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: .06)
            : scheme.surfaceContainerHighest.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: .60)
              : scheme.outlineVariant.withValues(alpha: .60),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _saving ? null : () => setState(() => _selectedLayer = key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: ValueKey('invitation-toggle-$key'),
                  tooltip: visible ? 'Ocultar capa' : 'Mostrar capa',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _toggleSection(key, !visible)),
                  icon: Icon(
                    visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: visible ? scheme.primary : scheme.outline,
                  ),
                ),
                Icon(
                  _sectionIcon(key),
                  size: 17,
                  color: visible ? scheme.onSurface : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sectionLabelFor(key),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: visible
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        visible ? _layerSubtitle(key) : 'Oculta',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'FIJO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  key: ValueKey('invitation-edit-$key'),
                  tooltip: 'Abrir ajustes del componente',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() => _selectedLayer = key);
                          _openLayerSettings(key);
                        },
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _layerInspector(ColorScheme scheme) {
    final key = _selectedLayer!;
    final index = _sectionOrder.indexOf(key);
    final movable = index >= 0;
    return Container(
      key: const ValueKey('invitation-layer-inspector'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: .30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPONENTE SELECCIONADO',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _sectionLabelFor(key),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            _layerDescription(key),
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : () => _openLayerSettings(key),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Abrir ajustes'),
              ),
              if (movable) ...[
                const Spacer(),
                IconButton(
                  tooltip: 'Subir capa',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || index == 0
                      ? null
                      : () => _moveLayer(index, -1),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 19),
                ),
                IconButton(
                  tooltip: 'Bajar capa',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || index == _sectionOrder.length - 1
                      ? null
                      : () => _moveLayer(index, 1),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _form(ColorScheme scheme) {
    // `SingleChildScrollView` mantiene montados todos los ítems del panel:
    // son pocos y así el arrastre, las claves y los atajos no dependen de si
    // el usuario ya hizo scroll.
    return SingleChildScrollView(
      key: PageStorageKey<String>('invitation-form-$_designTab'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (_designTab) {
          1 => _layersChildren(scheme),
          2 => _designChildren(scheme),
          3 => _photosChildren(scheme),
          4 => _contentChildren(scheme),
          5 => _publishChildren(scheme),
          _ => _basicsChildren(scheme),
        },
      ),
    );
  }

  /// Una tarjeta de ayuda al principio de cada pestaña.
  Widget _introCard(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .10),
            scheme.primary.withValues(alpha: .02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Datos ----------------

  List<Widget> _basicsChildren(ColorScheme scheme) => [
    _introCard(
      scheme,
      icon: Icons.edit_note_rounded,
      title: 'Datos de la invitación',
      text:
          'Lo que leen tus invitados: nombres, fecha, lugar y cómo confirmar. '
          'Lo que dejes vacío usa el texto de la plantilla.',
    ),
    const SizedBox(height: 14),
    _field(
      label: 'Nombre del evento (para el panel)',
      controller: _title,
      hint: 'Boda de Ana & Luis',
    ),
    _field(
      key: const ValueKey('invitation-headline'),
      label: 'Nombres en la invitación',
      controller: _headline,
      hint: 'Ana & Luis',
    ),
    _field(
      label: 'Frase de arriba',
      controller: _subheadline,
      hint: '¡Nos casamos!',
    ),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            label: 'Fecha',
            controller: _date,
            hint: 'Sábado 14 de febrero de 2026',
            suffix: IconButton(
              key: const ValueKey('invitation-date-pick'),
              tooltip: 'Elegir fecha',
              onPressed: _saving ? null : _pickEventDate,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _field(
            label: 'Hora',
            controller: _time,
            hint: '6:00 pm',
            suffix: IconButton(
              key: const ValueKey('invitation-time-pick'),
              tooltip: 'Elegir hora',
              onPressed: _saving ? null : _pickEventTime,
              icon: const Icon(Icons.schedule_outlined, size: 18),
            ),
          ),
        ),
      ],
    ),
    Text(
      'La fecha y la hora también activan la cuenta regresiva.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
    const SizedBox(height: 12),
    _field(label: 'Lugar', controller: _place, hint: 'Hacienda San José'),
    _field(
      label: 'Dirección',
      controller: _address,
      hint: 'Camino Real 120, Guadalajara',
    ),
    _field(
      label: 'Mensaje',
      controller: _message,
      hint: 'Un texto corto para tus invitados…',
      maxLines: 3,
    ),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            label: 'Código de vestimenta',
            controller: _dress,
            hint: 'Formal',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _field(
            label: 'WhatsApp para confirmar',
            controller: _phone,
            hint: '5213312345678',
            keyboard: TextInputType.phone,
          ),
        ),
      ],
    ),
    const SizedBox(height: 4),
    _countdownTile(scheme),
  ];

  // ---------------- Diseño ----------------

  List<Widget> _designChildren(ColorScheme scheme) => [
    _introCard(
      scheme,
      icon: Icons.palette_outlined,
      title: 'Diseña a tu gusto',
      text:
          'Elige la plantilla, los colores y el fondo. La vista previa de la '
          'derecha se actualiza al instante.',
    ),
    const SizedBox(height: 14),
    _sectionLabel('PLANTILLA COMPUESTA', scheme),
    const SizedBox(height: 8),
    _templatePicker(scheme),
    const SizedBox(height: 6),
    Text(
      'La plantilla define la base. La portada, los colores, la animación y '
      'los componentes se combinan libremente.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
    const SizedBox(height: 16),
    _sectionLabel('PORTADA', scheme),
    const SizedBox(height: 4),
    Text(
      'Elige cómo recibe el invitado la invitación. La portada funciona con '
      'las dos plantillas y conserva el texto y el fondo que elijas.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
    const SizedBox(height: 8),
    _coverStylesBlock(scheme),
    if (_coverStyle == 'carta') ...[
      const SizedBox(height: 12),
      _sectionLabel('FONDO DE LA CARTA', scheme),
      const SizedBox(height: 4),
      Text(
        'Tres escenas de boda con flores, aros y papelería. Se mueven '
        'suavemente en la invitación publicada.',
        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      _cartaBackdropBlock(scheme),
    ],
    const SizedBox(height: 16),
    _sectionLabel('COLORES', scheme),
    const SizedBox(height: 8),
    _accentColorCard(scheme),
    _bgColorCard(scheme),
    const SizedBox(height: 4),
    _sectionLabel('FONDO', scheme),
    const SizedBox(height: 8),
    _backgroundBlock(scheme),
    if (_template == 'boda-marfil') ...[
      const SizedBox(height: 14),
      _sectionLabel('FONDO DE LOS DETALLES', scheme),
      const SizedBox(height: 8),
      _detailsBackgroundBlock(scheme),
    ],
    const SizedBox(height: 16),
    _sectionLabel('ANIMACIÓN', scheme),
    const SizedBox(height: 8),
    _effectsBlock(scheme),
    const SizedBox(height: 6),
    Text(
      'El movimiento se ve en la invitación publicada. Elige el que combine '
      'con la ocasión; «Sin efectos» deja solo el diseño.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
    const SizedBox(height: 16),
    _sectionLabel('SECCIONES', scheme),
    const SizedBox(height: 6),
    _sectionsBlock(scheme),
  ];

  /// El color de acento con la paleta de siempre MÁS cualquier color propio.
  Widget _accentColorCard(ColorScheme scheme) {
    final templateAccent = invitationTemplate(_template).accent;
    final usingTemplate = _accent.trim().isEmpty;
    final current = usingTemplate
        ? templateAccent
        : colorOfHex(_accent) ?? templateAccent;
    return _colorCard(
      scheme,
      key: const ValueKey('invitation-accent-block'),
      addKey: const ValueKey('invitation-accent-add'),
      icon: Icons.brush_outlined,
      title: 'Color de acento',
      hint: _template == 'boda-marfil'
          ? 'Dorados, líneas, fechas y botones de Marfil & Oro.'
          : 'Cintas, adornos, fechas y botones. Los dorados se mantienen.',
      current: current,
      usingTemplate: usingTemplate,
      templateLabel: 'Usar el color de la plantilla',
      onPick: () => _pickCustomColor(
        title: 'Color de acento',
        initial: current,
        onPicked: (c) => setState(() => _accent = colorHex(c)),
      ),
      onTemplate: () => setState(() => _accent = ''),
      swatches: [
        _Swatch(
          key: const ValueKey('invitation-accent-template'),
          color: templateAccent,
          selected: usingTemplate,
          tooltip: 'Color de la plantilla',
          onTap: _saving ? null : () => setState(() => _accent = ''),
        ),
        for (final hex in kInvitationAccents)
          _Swatch(
            key: ValueKey('invitation-accent-$hex'),
            color: _colorFromHex(hex),
            selected: _accent.toUpperCase() == '#$hex',
            tooltip: '#$hex',
            onTap: _saving ? null : () => setState(() => _accent = '#$hex'),
          ),
      ],
    );
  }

  /// El color de fondo de la página ('' = el de la plantilla).
  Widget _bgColorCard(ColorScheme scheme) {
    final templateBg = invitationTemplate(_template).bg;
    final usingTemplate = _bgColor.trim().isEmpty;
    final current = usingTemplate
        ? templateBg
        : colorOfHex(_bgColor) ?? templateBg;
    return _colorCard(
      scheme,
      key: const ValueKey('invitation-bg-block'),
      addKey: const ValueKey('invitation-bg-add'),
      icon: Icons.format_color_fill_rounded,
      title: 'Color de fondo',
      hint:
          'Página y secciones. La portada usa el diseño que elijas y la '
          'paleta de la plantilla; las tarjetas se quedan claras.',
      current: current,
      usingTemplate: usingTemplate,
      templateLabel: 'Usar el fondo de la plantilla',
      onPick: () => _pickCustomColor(
        title: 'Color de fondo',
        initial: current,
        onPicked: (c) => setState(() => _bgColor = colorHex(c)),
      ),
      onTemplate: () => setState(() => _bgColor = ''),
      swatches: [
        _Swatch(
          key: const ValueKey('invitation-bg-template'),
          color: templateBg,
          selected: usingTemplate,
          tooltip: 'Fondo de la plantilla',
          onTap: _saving ? null : () => setState(() => _bgColor = ''),
        ),
        for (final hex in _bgPalette)
          _Swatch(
            key: ValueKey('invitation-bg-$hex'),
            color: _colorFromHex(hex),
            selected: _bgColor.toUpperCase() == '#$hex',
            tooltip: 'Fondo #$hex',
            onTap: _saving ? null : () => setState(() => _bgColor = '#$hex'),
          ),
      ],
    );
  }

  Widget _colorCard(
    ColorScheme scheme, {
    required Key key,
    required Key addKey,
    required IconData icon,
    required String title,
    required String hint,
    required Color current,
    required bool usingTemplate,
    required String templateLabel,
    required VoidCallback onPick,
    required VoidCallback onTemplate,
    required List<Widget> swatches,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Elegir cualquier color',
                child: InkWell(
                  onTap: _saving ? null : onPick,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: current,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          colorHex(current),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in swatches) s,
              Tooltip(
                message: 'Añadir un color',
                child: Material(
                  color: scheme.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: addKey,
                    customBorder: const CircleBorder(),
                    onTap: _saving ? null : onPick,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving || usingTemplate ? null : onTemplate,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(templateLabel),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre el selector de color con el tono, la saturación y el brillo.
  Future<void> _pickCustomColor({
    required String title,
    required Color initial,
    required ValueChanged<Color> onPicked,
  }) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(title: title, initial: initial),
    );
    if (picked == null || !mounted) return;
    onPicked(picked);
  }

  // ---------------- Fotos ----------------

  List<Widget> _photosChildren(ColorScheme scheme) => [
    _introCard(
      scheme,
      icon: Icons.photo_camera_back_outlined,
      title: 'Polaroids de la invitación',
      text:
          'Tres fotos con marco de polaroid. La primera también es la imagen '
          'que se ve al compartir la liga. Se enlazan desde el Drive y se '
          'hacen públicas al guardar.',
    ),
    const SizedBox(height: 14),
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (var i = 0; i < 3; i++) _photoSlot(i, scheme)],
    ),
    const SizedBox(height: 12),
    if (_photos.length < 3)
      OutlinedButton.icon(
        onPressed: _saving ? null : _pickPhoto,
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: const Text('Agregar polaroid'),
      ),
    const SizedBox(height: 8),
    Text(
      'Toca una polaroid para cambiarla y la X para quitarla. Si una foto se '
      've en blanco, vuelve a elegirla: la vista previa necesita la sesión '
      'del panel y la liga pública, que la foto esté publicada.',
      style: TextStyle(
        fontSize: 10.5,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
    ),
  ];

  // ---------------- Contenido ----------------

  List<Widget> _contentChildren(ColorScheme scheme) => [
    _introCard(
      scheme,
      icon: Icons.article_outlined,
      title: 'Textos y secciones',
      text:
          'Familias, detalles, itinerario, hashtag y los textos propios del '
          'diseño. Lo vacío usa el texto original de la plantilla.',
    ),
    const SizedBox(height: 14),
    _sectionLabel('FAMILIAS', scheme),
    const SizedBox(height: 8),
    for (var i = 0; i < _familyRows.length; i++) _familyEditor(i),
    OutlinedButton.icon(
      onPressed: _saving
          ? null
          : () => setState(
              () => _familyRows.add(_FamilyRow(const InvitationFamily())),
            ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Agregar familia'),
    ),
    const SizedBox(height: 18),
    _sectionLabel('DETALLES', scheme),
    const SizedBox(height: 8),
    for (var i = 0; i < _detailRows.length; i++) _detailEditor(i, scheme),
    OutlinedButton.icon(
      onPressed: _saving
          ? null
          : () => setState(
              () => _detailRows.add(_DetailRow(const InvitationDetail())),
            ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Agregar detalle'),
    ),
    const SizedBox(height: 18),
    _sectionLabel('ITINERARIO', scheme),
    const SizedBox(height: 8),
    for (var i = 0; i < _stopRows.length; i++) _stopEditor(i, scheme),
    OutlinedButton.icon(
      onPressed: _saving
          ? null
          : () =>
                setState(() => _stopRows.add(_StopRow(const InvitationStop()))),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Agregar momento'),
    ),
    const SizedBox(height: 18),
    _sectionLabel('HASHTAG Y MÚSICA', scheme),
    const SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            key: const ValueKey('invitation-hashtag'),
            label: 'Hashtag',
            controller: _hashtag,
            hint: '#ReynaXV2026',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _field(
            label: 'Música de fondo (liga .mp3)',
            controller: _music,
            hint: 'https://…/Audio.mp3',
            keyboard: TextInputType.url,
          ),
        ),
      ],
    ),
    _field(
      key: const ValueKey('invitation-quote'),
      label: 'Frase de la tarjeta (si se deja vacía se usa el mensaje)',
      controller: _quote,
      hint: 'Hoy dejo atrás mi niñez para comenzar un nuevo capítulo…',
      maxLines: 3,
    ),
    const SizedBox(height: 18),
    _sectionLabel('TEXTOS DEL DISEÑO', scheme),
    const SizedBox(height: 4),
    Text(
      'Si un campo se deja vacío, se usa el texto original de la plantilla.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
    const SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            label: 'Ocasión',
            controller: _occasionText,
            hint: 'XV',
          ),
        ),
        if (_template != 'boda-marfil') ...[
          const SizedBox(width: 10),
          Expanded(
            child: _field(
              label: 'Título vertical',
              controller: _verticalTitle,
              hint: 'Mis Quinceaños',
            ),
          ),
        ],
      ],
    ),
    if (_template == 'boda-marfil')
      Text(
        'En Marfil & Oro, el «Texto sobre los nombres» es la línea que va '
        'sobre los nombres; la «Frase de arriba» es el subtítulo.',
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
    _field(
      label: _template == 'boda-marfil'
          ? 'Texto sobre los nombres'
          : 'Texto del arco',
      controller: _arcTitle,
      hint: 'MIS QUINCEAÑOS',
    ),
    _field(
      label: 'Texto del sobre',
      controller: _envelopeText,
      hint: 'Tienes una invitación',
    ),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            label: 'Título de familias',
            controller: _familiesTitle,
            hint: 'Con mi familia',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _field(
            label: 'Título de detalles',
            controller: _detailsTitle,
            hint: 'Detalles',
          ),
        ),
      ],
    ),
    _field(
      label: 'Subtítulo de detalles',
      controller: _detailsIntro,
      hint: 'Todo lo que necesitas saber para acompañarme',
    ),
    _field(
      label: 'Título del itinerario',
      controller: _itineraryTitle,
      hint: 'Itinerario de Actividades',
    ),
    _field(
      label: 'Introducción del hashtag',
      controller: _hashtagIntro,
      hint: 'Captura momentos únicos con',
    ),
    if (_template == 'boda-marfil') ...[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              label: 'Título de Recuerdos',
              controller: _memoriesTitle,
              hint: 'Recuerdos',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(
              label: 'Introducción de Recuerdos',
              controller: _memoriesIntro,
              hint: 'El álbum de la celebración, hecho entre todos',
            ),
          ),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              label: 'Carpeta del Drive para las fotos',
              controller: _memoriesFolder,
              hint: 'Recuerdos/AnaYLuis (vacío = Recuerdos/<liga>)',
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: IconButton.filledTonal(
              tooltip: 'Elegir carpeta del Drive',
              onPressed: HsAccess.instance.canUseDrive
                  ? _pickMemoriesFolder
                  : null,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
            ),
          ),
        ],
      ),
    ],
    _field(
      label: 'Mensaje del pie',
      controller: _footerMessage,
      hint: 'Tu presencia es el mejor regalo…',
      maxLines: 2,
    ),
  ];

  // ---------------- Publicar ----------------

  List<Widget> _publishChildren(ColorScheme scheme) => [
    _introCard(
      scheme,
      icon: Icons.ios_share_rounded,
      title: 'Publica y comparte',
      text:
          'Al publicar se crea una liga que cualquiera puede abrir sin cuenta. '
          'Puedes despublicarla cuando quieras: la invitación y sus datos se '
          'quedan guardados.',
    ),
    const SizedBox(height: 14),
    Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .35),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: _published,
        onChanged: _saving ? null : (v) => setState(() => _published = v),
        title: const Text(
          'Publicar con liga para compartir',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          _published
              ? 'Al guardar se crea (o se conserva) la liga pública.'
              : 'Se guarda como borrador; la liga se crea al publicar.',
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
      ),
    ),
    const SizedBox(height: 14),
    _summaryCard(scheme),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: _saving ? null : _openInBrowser,
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: const Text('Ver la invitación real'),
    ),
    const SizedBox(height: 4),
    Text(
      'Abre el HTML que se guarda, tal como lo verá el cliente.',
      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
    ),
  ];

  Widget _summaryCard(ColorScheme scheme) {
    final photos = _photos.where((p) => p.trim().isNotEmpty).length;
    final sections = _sections.isEmpty
        ? kInvitationSections.length
        : _sections.length;
    final rows = <(String, String)>[
      (
        'Plantilla',
        templateRecipeForInvitation(preset: _preset, template: _template).name,
      ),
      ('Portada', _coverLabel(_coverStyle)),
      if (_coverStyle == 'carta')
        ('Fondo de carta', _backdropLabel(_coverBackdrop)),
      (
        'Acento',
        _accent.trim().isEmpty ? 'De la plantilla' : _accent.toUpperCase(),
      ),
      (
        'Fondo',
        _bgColor.trim().isEmpty ? 'De la plantilla' : _bgColor.toUpperCase(),
      ),
      ('Animación', _effects.firstWhere((e) => e.key == _effectKey).label),
      ('Polaroids', '$photos de 3'),
      ('Secciones', '$sections de ${kInvitationSections.length}'),
      ('Estado', _published ? 'Publicada' : 'Borrador'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 14,
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  rows[i].$2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- Listas con campos (familias, detalles, itinerario) ----------------

  /// Tarjeta de una fila de lista: encabezado, botón de quitar y campos.
  Widget _listCard({
    required Widget title,
    required VoidCallback onRemove,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
        color: scheme.surfaceContainerHighest.withValues(alpha: .22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _rowTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
    ),
  );

  Widget _detailEditor(int index, ColorScheme scheme) {
    final row = _detailRows[index];
    return _listCard(
      title: _rowTitle('Detalle ${index + 1}'),
      onRemove: () => setState(() => _detailRows.removeAt(index).dispose()),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _field(
                  label: 'Título',
                  controller: row.title,
                  hint: 'Ceremonia',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _field(label: 'Icono', controller: row.icon, hint: '⛪'),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  label: 'Hora',
                  controller: row.time,
                  hint: '7:30 PM',
                  suffix: IconButton(
                    tooltip: 'Elegir hora',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving ? null : () => _pickClock(row.time),
                    icon: const Icon(Icons.schedule_outlined, size: 17),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _field(
                  label: 'Lugar',
                  controller: row.place,
                  hint: 'Iglesia Santa Úrsula',
                ),
              ),
            ],
          ),
          _field(
            label: 'Liga del mapa (opcional)',
            controller: row.map,
            hint: 'https://maps.google.com/…',
            keyboard: TextInputType.url,
          ),
          _field(
            label: 'Nota (opcional)',
            controller: row.note,
            hint: 'Vestimenta, indicaciones…',
          ),
        ],
      ),
    );
  }

  Widget _stopEditor(int index, ColorScheme scheme) {
    final row = _stopRows[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _field(
            label: 'Hora',
            controller: row.time,
            hint: '7:30 PM',
            suffix: IconButton(
              tooltip: 'Elegir hora',
              visualDensity: VisualDensity.compact,
              onPressed: _saving ? null : () => _pickClock(row.time),
              icon: const Icon(Icons.schedule_outlined, size: 17),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _field(
            label: 'Actividad',
            controller: row.title,
            hint: 'Ceremonia',
          ),
        ),
        IconButton(
          tooltip: 'Quitar momento',
          onPressed: () => setState(() => _stopRows.removeAt(index).dispose()),
          icon: Icon(
            Icons.close_rounded,
            size: 17,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _familyEditor(int index) {
    final row = _familyRows[index];
    return _listCard(
      title: _rowTitle('Familia ${index + 1}'),
      onRemove: () => setState(() => _familyRows.removeAt(index).dispose()),
      child: Column(
        children: [
          _field(label: 'Título', controller: row.title, hint: 'Papás'),
          _field(
            label: 'Nombres (separados por coma)',
            controller: row.names,
            hint: 'Jose Coot, Wendy Ruiz',
          ),
        ],
      ),
    );
  }

  Widget _photoSlot(int index, ColorScheme scheme) {
    final url = index < _photos.length ? _photos[index] : '';
    final filled = url.trim().isNotEmpty;
    final next = index == _photos.length;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: .25),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: filled ? scheme.outlineVariant : scheme.outline,
              ),
            ),
            child: InkWell(
              key: ValueKey('invitation-photo-$index'),
              onTap: _saving || (!filled && !next)
                  ? null
                  : () => filled ? _pickPhoto(replaceAt: index) : _pickPhoto(),
              child: SizedBox(
                width: 96,
                height: 112,
                child: filled
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            driveImagePreview(
                              url,
                              token: HsSession.token,
                              width: 320,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.image_outlined,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Material(
                              color: scheme.surface,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _saving
                                    ? null
                                    : () => setState(
                                        () =>
                                            _photos = [..._photos]
                                              ..removeAt(index),
                                      ),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(Icons.close_rounded, size: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 22,
                            color: next ? scheme.primary : scheme.outline,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            next ? 'Elegir' : 'Libre',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Polaroid ${index + 1}',
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 2),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
        ),
      ],
    ),
  );

  Widget _field({
    Key? key,
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Más aire entre campos y una etiqueta fija (antes era la del
      // TextField y se movía al enfocar).
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: key,
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboard,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .22),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .55),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una familia en el editor (título + nombres en un solo campo).
class _FamilyRow {
  _FamilyRow(InvitationFamily f)
    : title = TextEditingController(text: f.title),
      names = TextEditingController(text: f.names.join(', '));

  final TextEditingController title;
  final TextEditingController names;

  InvitationFamily get value => InvitationFamily(
    title: title.text.trim(),
    names: [
      for (final n in names.text.split(','))
        if (n.trim().isNotEmpty) n.trim(),
    ],
  );

  void dispose() {
    title.dispose();
    names.dispose();
  }
}

/// Un detalle de la invitación (misa, recepción, vestimenta…), campo por campo.
class _DetailRow {
  _DetailRow(InvitationDetail d)
    : title = TextEditingController(text: d.title),
      time = TextEditingController(text: d.time),
      place = TextEditingController(text: d.place),
      map = TextEditingController(text: d.mapUrl),
      note = TextEditingController(text: d.note),
      icon = TextEditingController(text: d.icon == '✦' ? '' : d.icon);

  final TextEditingController title;
  final TextEditingController time;
  final TextEditingController place;
  final TextEditingController map;
  final TextEditingController note;
  final TextEditingController icon;

  InvitationDetail get value => InvitationDetail(
    title: title.text.trim(),
    time: time.text.trim(),
    place: place.text.trim(),
    mapUrl: map.text.trim(),
    note: note.text.trim(),
    icon: icon.text.trim().isEmpty ? '✦' : icon.text.trim(),
  );

  void dispose() {
    for (final c in [title, time, place, map, note, icon]) {
      c.dispose();
    }
  }
}

/// Un momento del itinerario (hora + actividad).
class _StopRow {
  _StopRow(InvitationStop s)
    : time = TextEditingController(text: s.time),
      title = TextEditingController(text: s.title);

  final TextEditingController time;
  final TextEditingController title;

  InvitationStop get value =>
      InvitationStop(time: time.text.trim(), title: title.text.trim());

  void dispose() {
    time.dispose();
    title.dispose();
  }
}

/// Un color de la paleta del diseñador.
class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: color.computeLuminance() > .55
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

/// Selector de color del diseñador: tono, saturación y brillo, con el valor
/// exacto en hexadecimal. No usa dependencias nuevas y permite CUALQUIER
/// color, no solo los de la paleta.
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: colorHex(widget.initial).substring(1));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _apply(HSVColor value) {
    setState(() {
      _hsv = value;
      _hex.text = colorHex(value.toColor()).substring(1);
    });
  }

  void _typed(String raw) {
    final clean = raw.trim().replaceAll('#', '').toUpperCase();
    final color = colorOfHex(clean);
    if (color == null) return;
    setState(() => _hsv = HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    final hex = colorHex(color);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    ],
                    onChanged: _typed,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Hexadecimal',
                      prefixText: '#',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            label('Tono'),
            Slider(
              value: _hsv.hue,
              max: 360,
              activeColor: color,
              onChanged: (v) => _apply(_hsv.withHue(v)),
            ),
            label('Saturación'),
            Slider(
              value: _hsv.saturation,
              activeColor: color,
              onChanged: (v) => _apply(_hsv.withSaturation(v)),
            ),
            label('Brillo'),
            Slider(
              value: _hsv.value,
              activeColor: color,
              onChanged: (v) => _apply(_hsv.withValue(v)),
            ),
            Text(
              'Se usará $hex',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Usar este color'),
        ),
      ],
    );
  }
}

// ==================================================================
// COMPARTIR
// ==================================================================

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.invitation});

  final Invitation invitation;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  bool _busy = false;
  bool _changed = false;

  Future<void> _copy() async {
    final url = widget.invitation.shareUrl;
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    HsToast.success('Liga copiada', details: url);
  }

  Future<void> _open() async {
    final url = widget.invitation.shareUrl;
    if (url.isEmpty) return;
    final opened = await hsOpenUrl(url);
    if (!mounted) return;
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      HsToast.info(
        'Liga copiada',
        details:
            'En este dispositivo no se pudo abrir el navegador: '
            'pégala donde la necesites.',
      );
    }
  }

  Future<void> _whatsapp() async {
    final url = widget.invitation.shareUrl;
    if (url.isEmpty) return;
    final text = Uri.encodeComponent(
      'Te comparto la invitación de ${widget.invitation.displayTitle}: $url',
    );
    final opened = await hsOpenUrl('https://wa.me/?text=$text');
    if (!mounted) return;
    if (!opened) await _copy();
  }

  Future<void> _unpublish() async {
    setState(() => _busy = true);
    try {
      await HsApi.publishInvitation(widget.invitation.id, false);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
      });
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      HsToast.error(e.message, details: e.details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inv = widget.invitation;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Compartir invitación',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          inv.panelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: InvitationPreview(
                          invitation: inv,
                          compact: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .4,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .6),
                        ),
                      ),
                      child: SelectableText(
                        inv.shareUrl,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _copy,
                            icon: const Icon(Icons.copy_rounded, size: 17),
                            label: const Text('Copiar liga'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _open,
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                            ),
                            label: const Text('Abrir'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _busy ? null : _whatsapp,
                      icon: const Icon(Icons.chat_bubble_outline, size: 17),
                      label: const Text('Mandar por WhatsApp'),
                    ),
                    Text(
                      'Cualquiera con esta liga puede abrir la invitación. '
                      'No hace falta que tenga cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _unpublish,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.link_off_rounded, size: 17),
                    label: const Text('Despublicar'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(_changed),
                    child: const Text('Listo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El catálogo que se abre al crear una invitación o al cambiarla: cada
/// tarjeta es una combinación de componentes ya armada.
class _TemplateChooser extends StatefulWidget {
  const _TemplateChooser();

  @override
  State<_TemplateChooser> createState() => _TemplateChooserState();
}

class _TemplateChooserState extends State<_TemplateChooser> {
  bool _busy = false;

  List<InvitationTemplateRecipe> get _recipes => allInvitationTemplateRecipes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await InvitationTemplateStore.load();
    if (mounted) setState(() {});
  }

  Future<void> _createTemplate() async {
    if (_busy) return;
    final basis = _recipes.first;
    final picked = await showHsModal<InvitationTemplateRecipe>(
      context: context,
      builder: (_) => InvitationTemplateRecipeDialog(
        title: 'Nueva plantilla',
        source: basis.copyWith(key: '', name: 'Mi plantilla', custom: true),
        editing: false,
        choices: _recipes,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    await InvitationTemplateStore.save(picked);
    if (!mounted) return;
    setState(() => _busy = false);
    HsToast.success('Plantilla creada', details: picked.name);
  }

  Future<void> _deleteTemplate(InvitationTemplateRecipe recipe) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('¿Eliminar la plantilla?'),
        content: Text(
          'Se quitará «${recipe.name}» del catálogo de este equipo. Las '
          'invitaciones que ya la usan conservan su diseño y sus datos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await InvitationTemplateStore.delete(recipe.key);
    if (!mounted) return;
    setState(() {});
    HsToast.info('Plantilla eliminada', details: recipe.name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final cards = [for (final t in _recipes) _card(context, t)];
    final customCount = _recipes.where((r) => r.custom).length;
    return Dialog(
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < kHsPhoneWidth ? 0 : 22,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.dashboard_customize_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Elige una plantilla',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_recipes.length} combinaciones de componentes. '
                          'Se personalizan igual: textos, fecha, fotos, '
                          'colores y animación.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('template-create'),
                    onPressed: _busy ? null : _createTemplate,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nueva plantilla'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Text(
                    customCount == 0
                        ? 'Crea tu propia combinación y guárdala en este equipo.'
                        : customCount == 1
                        ? '1 plantilla tuya · guardada en este equipo'
                        : '$customCount plantillas tuyas · guardadas en este equipo',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards)
                    SizedBox(width: wide ? 196 : double.infinity, child: card),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, InvitationTemplateRecipe t) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('template-${t.key}'),
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).pop(t.key),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .65),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              alignment: Alignment.center,
              color: scheme.surfaceContainerHighest.withValues(alpha: .25),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96,
                  height: 132,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 360,
                      height: 480,
                      child: InvitationPreview(
                        invitation: Invitation.samplePreset(t.key),
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t.custom ? 'TUYA' : t.occasion,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      if (t.custom)
                        PopupMenuButton<String>(
                          key: ValueKey('template-menu-${t.key}'),
                          tooltip: 'Opciones de ${t.name}',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          iconSize: 17,
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (action) {
                            if (action == 'delete') {
                              _deleteTemplate(t);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(t.key),
                      child: Text('Usar ${t.name}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
