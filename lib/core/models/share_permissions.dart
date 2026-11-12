import 'package:flutter/foundation.dart';

/// Lo que puede hacer un DESTINATARIO en una carpeta compartida.
///
/// Lo decide quien COMPARTE (no su rol): la misma persona puede editar una
/// carpeta y solo ver otra. El DUEÑO siempre puede todo.
///
/// Se usa en tres sitios y por eso vive aparte:
///   * el diálogo de permisos del módulo Archivos compartidos,
///   * la ficha del listado (los iconos de lo que puede cada uno),
///   * la vista de la carpeta, que decide qué acciones ofrecer.
@immutable
class SharePermissions {
  const SharePermissions({
    this.view = true,
    this.edit = false,
    this.create = false,
    this.download = true,
  });

  /// Ver el contenido.
  final bool view;

  /// Editar: renombrar, mover y eliminar.
  final bool edit;

  /// Crear: subir archivos y carpetas.
  final bool create;

  /// Descargar archivos y carpetas (ZIP).
  final bool download;

  /// El dueño de la carpeta: todo permitido.
  static const SharePermissions owner = SharePermissions(
    view: true,
    edit: true,
    create: true,
    download: true,
  );

  /// Un compartido NUEVO: ver y descargar (lo que el módulo hacía antes).
  static const SharePermissions readOnly = SharePermissions();

  bool get any => view || edit || create || download;

  static bool _yes(Object? v, bool fallback) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '$v'.trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'si' || s == 'sí') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return fallback;
  }

  factory SharePermissions.fromJson(Object? raw, {SharePermissions? fallback}) {
    final base = fallback ?? readOnly;
    final m = (raw is Map) ? raw : const {};
    return SharePermissions(
      view: _yes(m['view'] ?? m['ver'], base.view),
      edit: _yes(m['edit'] ?? m['editar'], base.edit),
      create: _yes(m['create'] ?? m['crear'], base.create),
      download: _yes(m['download'] ?? m['descargar'], base.download),
    );
  }

  Map<String, bool> toJson() => {
    'view': view,
    'edit': edit,
    'create': create,
    'download': download,
  };

  SharePermissions copyWith({
    bool? view,
    bool? edit,
    bool? create,
    bool? download,
  }) => SharePermissions(
    view: view ?? this.view,
    edit: edit ?? this.edit,
    create: create ?? this.create,
    download: download ?? this.download,
  );

  /// Suma de permisos (para varios dueños de la MISMA carpeta: si uno dio
  /// editar, se puede editar).
  SharePermissions merge(SharePermissions other) => SharePermissions(
    view: view || other.view,
    edit: edit || other.edit,
    create: create || other.create,
    download: download || other.download,
  );

  /// Lo que se enseña en la ficha, p. ej. «Ver · Descargar · Editar».
  String get label {
    final out = <String>[
      if (view) 'Ver',
      if (download) 'Descargar',
      if (edit) 'Editar',
      if (create) 'Crear',
    ];
    return out.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is SharePermissions &&
      other.view == view &&
      other.edit == edit &&
      other.create == create &&
      other.download == download;

  @override
  int get hashCode => Object.hash(view, edit, create, download);

  @override
  String toString() => 'SharePermissions($label)';
}
