import 'package:flutter/material.dart';

import '../invitation_components/templates/custom_invitation_templates.dart';
import '../invitation_components/templates/invitation_templates.dart';

/// Formulario pequeño para ponerle nombre a una plantilla y decidir de qué
/// diseño parte. Los colores, la portada y los componentes se editan en el
/// lienzo; después se guardan con «Actualizar plantilla».
class InvitationTemplateRecipeDialog extends StatefulWidget {
  const InvitationTemplateRecipeDialog({
    super.key,
    required this.title,
    required this.source,
    required this.editing,
    this.choices = const <InvitationTemplateRecipe>[],
  });

  final String title;
  final InvitationTemplateRecipe source;
  final bool editing;

  /// Plantillas entre las que se puede elegir el diseño de partida. Vacío =
  /// se usa directamente [source] (por ejemplo, la foto del editor).
  final List<InvitationTemplateRecipe> choices;

  @override
  State<InvitationTemplateRecipeDialog> createState() =>
      _InvitationTemplateRecipeDialogState();
}

class _InvitationTemplateRecipeDialogState
    extends State<InvitationTemplateRecipeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _occasion;
  late final TextEditingController _hint;
  late String _basisKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.source.name);
    _occasion = TextEditingController(text: widget.source.occasion);
    _hint = TextEditingController(text: widget.source.hint);
    _basisKey = widget.source.key;
    if (widget.choices.isNotEmpty &&
        !widget.choices.any((r) => r.key == _basisKey)) {
      _basisKey = widget.choices.first.key;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _occasion.dispose();
    _hint.dispose();
    super.dispose();
  }

  InvitationTemplateRecipe get _selectedSource {
    if (widget.editing || widget.choices.isEmpty) return widget.source;
    for (final recipe in widget.choices) {
      if (recipe.key == _basisKey) return recipe;
    }
    return widget.source;
  }

  void _chooseBasis(String? key) {
    if (key == null || key == _basisKey) return;
    InvitationTemplateRecipe? basis;
    for (final recipe in widget.choices) {
      if (recipe.key == key) {
        basis = recipe;
        break;
      }
    }
    if (basis == null) return;
    final picked = basis;
    setState(() {
      _basisKey = key;
      if (_name.text.trim().isEmpty || _name.text.trim() == 'Mi plantilla') {
        _name.text = '${picked.name} personalizada';
      }
      _occasion.text = picked.occasion;
      _hint.text = picked.hint;
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe un nombre para la plantilla.');
      return;
    }
    final source = _selectedSource;
    final key = widget.editing && source.key.isNotEmpty
        ? source.key
        : InvitationTemplateStore.newKey(name);
    final occasion = _occasion.text.trim().isEmpty
        ? source.occasion
        : _occasion.text.trim();
    Navigator.of(context).pop(
      source.copyWith(
        key: key,
        name: name,
        occasion: occasion,
        hint: _hint.text.trim().isEmpty
            ? 'Plantilla personalizada guardada en este equipo.'
            : _hint.text.trim(),
        custom: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.editing && widget.choices.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('template-dialog-basis'),
                  initialValue: _basisKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Partir de',
                    prefixIcon: Icon(Icons.dashboard_customize_outlined),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final recipe in widget.choices)
                      DropdownMenuItem(
                        value: recipe.key,
                        child: Text(
                          '${recipe.name} · ${recipe.occasion}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _chooseBasis,
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                key: const ValueKey('template-dialog-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la plantilla',
                  hintText: 'Mi estilo de XV',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('template-dialog-occasion'),
                controller: _occasion,
                textCapitalization: TextCapitalization.words,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Ocasión',
                  hintText: 'XV, Boda, Cumpleaños…',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('template-dialog-hint'),
                controller: _hint,
                minLines: 2,
                maxLines: 3,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Para qué evento queda mejor…',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                widget.editing
                    ? 'Se conservan los colores, la portada y los componentes '
                          'actuales. Para cambiar el diseño, edita la invitación '
                          'y usa «Actualizar plantilla».'
                    : 'La plantilla parte de este diseño. Después puedes '
                          'personalizarla en el editor y guardar los cambios '
                          'con «Actualizar plantilla».',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Se guarda en este equipo.',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('template-dialog-save'),
          onPressed: _submit,
          child: Text(widget.editing ? 'Guardar cambios' : 'Crear plantilla'),
        ),
      ],
    );
  }
}
