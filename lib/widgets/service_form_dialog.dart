import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../hs_api.dart';
import '../service_icons.dart';
import '../theme.dart';
import 'form_dialog.dart';

/// Diálogo de alta/edición de un servicio del catálogo: icono seleccionable,
/// nombre y descripción.
///
/// Es COMPARTIDO por el módulo Servicios y por la personalización de paquetes
/// (donde se puede agregar un servicio sin salir del diálogo).
class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({super.key, this.service});

  final Map<String, dynamic>? service;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;

  /// PARÁMETROS ESPECIALES (migración 2026-10-18): fotos y carpeta.
  late final TextEditingController _photosMax;
  late bool _photosOn;
  late bool _allowFolder;

  /// Valor guardado del icono (`material:xxx` o la ruta heredada).
  late String _icon;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.service != null;

  String get _iconKey {
    final v = _icon.trim();
    return v.startsWith('material:') ? v.substring(9) : '';
  }

  @override
  void initState() {
    super.initState();
    final s = widget.service ?? const {};
    _name = TextEditingController(text: (s['name'] ?? '').toString());
    _description = TextEditingController(text: (s['description'] ?? '').toString());
    _icon = (s['icon'] ?? '').toString();
    final max = (s['photosMax'] as num?)?.toInt() ?? 0;
    _photosOn = max > 0;
    _photosMax = TextEditingController(text: max > 0 ? '$max' : '');
    _allowFolder = s['allowFolder'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _photosMax.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del servicio');
      return;
    }
    final photosMax = int.tryParse(_photosMax.text.trim()) ?? 0;
    if (_photosOn && photosMax <= 0) {
      setState(() => _error = 'Escribe cuántas fotos podrá elegir el cliente');
      return;
    }
    if (_photosOn && !_allowFolder) {
      setState(() => _error =
          '«Elegir fotos» necesita que el servicio use carpeta del Drive');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'description': _description.text.trim(),
      'icon': _icon.trim(),
      'photosMax': _photosOn ? photosMax : 0,
      'allowFolder': _allowFolder,
    };
    try {
      if (_editing) {
        await HsApi.updateService(
            {'id': (widget.service!['id'] as num).toInt(), ...body});
      } else {
        await HsApi.createService(body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo guardar el servicio';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      icon: _editing
          ? Icons.tune_rounded
          : Icons.miscellaneous_services_outlined,
      title: _editing ? 'Personalizar servicio' : 'Nuevo servicio',
      subtitle: 'Se usa en el catálogo y en todos los paquetes que lo '
          'incluyen.',
      maxWidth: 520,
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear servicio',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Icono',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kServiceIcons.entries)
                _IconPickTile(
                  icon: e.value,
                  selected: _iconKey == e.key,
                  onTap: () => setState(() => _icon = serviceIconValue(e.key)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Nombre',
          child: TextField(
            controller: _name,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del servicio',
              prefixIcon: Icon(Icons.miscellaneous_services_outlined,
                  size: 20),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Descripción',
          child: TextField(
            controller: _description,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Cobertura completa del evento…',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Parámetros especiales',
          child: Column(
            children: [
              _switch(
                icon: Icons.photo_library_outlined,
                title: 'Elegir fotos',
                subtitle: 'El cliente podrá marcar fotos de la carpeta '
                    'compartida en «Mi paquete».',
                value: _photosOn,
                onChanged: (v) => setState(() {
                  _photosOn = v;
                  if (v && _photosMax.text.trim().isEmpty) {
                    _photosMax.text = '10';
                  }
                  if (v) _allowFolder = true;
                }),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: !_photosOn
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: TextField(
                          key: const ValueKey('service-photos-max'),
                          controller: _photosMax,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '¿Cuántas fotos puede elegir?',
                            hintText: 'Ej. 25',
                            helperText: 'Máximo de fotos por cliente para este '
                                'servicio.',
                            prefixIcon: Icon(Icons.tag, size: 20),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              _switch(
                icon: Icons.folder_open_outlined,
                title: 'Abrir carpeta',
                subtitle: _allowFolder
                    ? 'El estudio podrá compartirle una carpeta del Drive y '
                        'el cliente verá «Abrir carpeta».'
                    : 'Este servicio no usa carpeta del Drive. Sus servicios '
                        'en los paquetes no podrán compartir una.',
                value: _allowFolder,
                onChanged: (v) => setState(() {
                  _allowFolder = v;
                  if (!v) _photosOn = false;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Interruptor de un parámetro especial (con su explicación).
  Widget _switch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      value: value,
      onChanged: onChanged,
      secondary: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (value ? AppColors.brand : scheme.onSurfaceVariant)
              .withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: value ? AppColors.brand : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Casilla visual para elegir un icono del catálogo.
class _IconPickTile extends StatelessWidget {
  const _IconPickTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: .14)
              : scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.brand.withValues(alpha: .75)
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Icon(
          icon,
          size: 21,
          color: selected ? AppColors.brand : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
