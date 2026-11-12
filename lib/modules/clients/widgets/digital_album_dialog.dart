import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hardstreet_admin/modules/clients/models/digital_album_model.dart';
import 'package:hardstreet_admin/modules/drive/services/drive_scope.dart';
import 'package:hardstreet_admin/core/api/hs_api.dart';

import 'package:hardstreet_admin/widgets/confirm_dialog.dart';
import 'package:hardstreet_admin/modules/drive/widgets/drive_folder_picker.dart';
import 'package:hardstreet_admin/widgets/hs_modal.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';

/// Álbum digital de un cliente: se elige una carpeta del Drive y una temática,
/// y el cliente la abre con una liga (`/album/<slug>`). No se copian fotos:
/// la página lee la carpeta, así que lo que se suba al Drive aparece solo.
class DigitalAlbumDialog extends StatefulWidget {
  const DigitalAlbumDialog({
    super.key,
    required this.userId,
    required this.clientName,
  });

  final int userId;
  final String clientName;

  @override
  State<DigitalAlbumDialog> createState() => _DigitalAlbumDialogState();
}

class _DigitalAlbumDialogState extends State<DigitalAlbumDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _date = TextEditingController();

  List<DigitalAlbum> _albums = const [];
  bool _loading = true;
  String? _error;

  /// null = lista de álbumes; una instancia = formulario abierto.
  DigitalAlbum? _editing;
  bool _saving = false;
  String _theme = 'boda';
  String _folder = '';
  bool _published = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await HsApi.albums(widget.userId);
      if (!mounted) return;
      setState(() {
        _albums = list;
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
        _error = 'No se pudieron cargar los álbumes de este cliente';
        _loading = false;
      });
    }
  }

  void _startNew() {
    setState(() {
      _editing = DigitalAlbum(userId: widget.userId);
      _title.clear();
      _date.clear();
      _theme = 'boda';
      _folder = '';
      _published = false;
    });
  }

  void _startEdit(DigitalAlbum album) {
    setState(() {
      _editing = album;
      _title.text = album.title;
      _date.text = album.eventDate;
      _theme = album.theme;
      _folder = album.folder;
      _published = album.published;
    });
  }

  void _cancelEdit() {
    if (_saving) return;
    setState(() => _editing = null);
  }

  Future<void> _pickFolder() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final current = _folder
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final segments = await showHsModal<List<String>>(
      context: context,
      builder: (_) => DriveFolderPicker(
        base: '',
        initial: current,
        load: drive.listChildFolders,
        conflict: (_) => null,
        title: 'Carpeta del álbum',
        subtitle:
            'Elige la carpeta con las fotos y vídeos del evento. Puedes crear '
            'una nueva carpeta dentro del Drive.',
        confirmLabel: 'Usar esta carpeta',
        emptyHint:
            'Esta carpeta no tiene subcarpetas.\nPuedes elegirla tal cual con '
            'el botón de abajo.',
      ),
    );
    if (!mounted || segments == null) return;
    if (segments.isEmpty) {
      HsToast.info('Elige una carpeta concreta, no la raíz del Drive');
      return;
    }
    setState(() => _folder = segments.join('/'));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      HsToast.info('Escribe el título del álbum');
      return;
    }
    if (_folder.trim().isEmpty) {
      HsToast.info('Elige la carpeta del Drive con las fotos');
      return;
    }
    setState(() => _saving = true);
    try {
      final base = _editing ?? DigitalAlbum(userId: widget.userId);
      await HsApi.saveAlbum(
        base.copyWith(
          title: title,
          theme: _theme,
          folder: _folder.trim(),
          eventDate: _date.text.trim(),
          published: _published,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = null;
      });
      HsToast.success(
        _published
            ? 'Álbum guardado y publicado. Ya puedes compartir la liga.'
            : 'Álbum guardado como borrador.',
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      HsToast.error(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      HsToast.error('No se pudo guardar el álbum');
    }
  }

  Future<void> _delete(DigitalAlbum album) async {
    final sure = await confirmDelete(
      context,
      title: '¿Eliminar este álbum?',
      message:
          '«${album.title}» dejará de estar disponible. Las fotos y vídeos '
          'siguen guardados en el Drive.',
    );
    if (!sure || !mounted) return;
    try {
      await HsApi.deleteAlbum(album.id);
      if (!mounted) return;
      HsToast.success('Álbum eliminado');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      HsToast.error(e.message);
    }
  }

  Future<void> _copyLink(DigitalAlbum album) async {
    if (album.url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: album.url));
    if (!mounted) return;
    HsToast.success('Liga copiada', details: album.url);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = hsIsPhone(context);
    final editing = _editing;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: phone ? 10 : 40,
        vertical: phone ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 10, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing == null ? 'Álbum digital' : 'Editar álbum',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                Text(
                  widget.clientName.isEmpty
                      ? 'Fotos y vídeos del evento'
                      : widget.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
      content: SizedBox(
        width: phone ? double.maxFinite : 540,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: editing == null ? _albumList(scheme) : _albumForm(scheme),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      actions: editing == null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
              FilledButton.icon(
                onPressed: _startNew,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nuevo álbum'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : _cancelEdit,
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_saving ? 'Guardando…' : 'Guardar'),
              ),
            ],
    );
  }

  // ======================= Lista de álbumes =======================

  Widget _albumList(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 46),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 34, color: scheme.error),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_albums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_album_outlined,
                size: 30,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Todavía no hay álbumes',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Elige una carpeta del Drive con las fotos y vídeos del evento '
              'y comparte una liga elegante con el cliente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _albums.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, i) => _albumTile(_albums[i], scheme),
    );
  }

  Widget _albumTile(DigitalAlbum album, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
        color: scheme.surfaceContainerHighest.withValues(alpha: .18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              album.published
                  ? Icons.photo_library_outlined
                  : Icons.photo_album_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _pill(
                      album.published ? 'Publicado' : 'Borrador',
                      album.published
                          ? const Color(0xFF2E9E6B)
                          : const Color(0xFFB8862F),
                    ),
                    const SizedBox(width: 4),
                    _pill(albumThemeLabel(album.theme), scheme.primary),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        album.folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (album.published && album.url.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    album.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones del álbum',
            icon: const Icon(Icons.more_vert_rounded, size: 19),
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  _copyLink(album);
                  break;
                case 'edit':
                  _startEdit(album);
                  break;
                case 'delete':
                  _delete(album);
                  break;
              }
            },
            itemBuilder: (_) => [
              if (album.published && album.url.isNotEmpty)
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link_rounded, size: 19),
                    title: Text('Copiar liga'),
                  ),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 19),
                  title: Text('Editar'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, size: 19),
                  title: Text(
                    'Eliminar',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
          color: color,
        ),
      ),
    );
  }

  // ======================= Formulario =======================

  Widget _albumForm(ColorScheme scheme) {
    final hint = kAlbumThemes
        .firstWhere((t) => t.key == _theme, orElse: () => kAlbumThemes.first)
        .hint;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Título del álbum',
              hintText: 'Ana & Luis',
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _date,
            decoration: const InputDecoration(
              labelText: 'Fecha del evento (opcional)',
              hintText: '14 de noviembre de 2026',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'TEMÁTICA',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in kAlbumThemes)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _theme == t.key,
                  onSelected: (_) => setState(() => _theme = t.key),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            hint,
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'CARPETA DEL DRIVE',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _saving ? null : _pickFolder,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _folder.isEmpty
                      ? scheme.outlineVariant
                      : scheme.primary.withValues(alpha: .45),
                  width: 1.2,
                ),
                color: _folder.isEmpty
                    ? scheme.surfaceContainerHighest.withValues(alpha: .22)
                    : scheme.primary.withValues(alpha: .055),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 21,
                    color: _folder.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _folder.isEmpty ? 'Elegir carpeta…' : _folder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _folder.isEmpty
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Fotos y vídeos del evento, en tu Drive',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _published,
            onChanged: _saving ? null : (v) => setState(() => _published = v),
            title: const Text(
              'Publicar el álbum',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            subtitle: Text(
              _published
                  ? 'Quien tenga la liga podrá verlo.'
                  : 'Borrador: la liga todavía no funcionará.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: scheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'El álbum es automático: lee la carpeta del Drive cada vez '
                    'que se abre. Las fotos y vídeos que subas aparecen solos.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
