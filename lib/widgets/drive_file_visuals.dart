import 'package:flutter/material.dart';

import '../drive_base.dart';

// ==================================================================
// CÓMO SE PINTA CADA TIPO DE ARCHIVO
// ==================================================================
// Vive aparte de la página del Drive porque lo usan sitios distintos (la
// cuadrícula, la lista y el visor) y porque el Drive ya no guarda solo fotos:
// un `.mp4`, un `.pdf` o un `.zip` tienen su propio icono, su color y su
// nombre de tipo en la ficha.
// ==================================================================

/// Icono del tipo de archivo.
IconData driveKindIcon(DriveItemKind kind) => switch (kind) {
  DriveItemKind.folder => Icons.folder_rounded,
  DriveItemKind.image => Icons.image_outlined,
  DriveItemKind.video => Icons.movie_creation_outlined,
  DriveItemKind.audio => Icons.music_note_rounded,
  DriveItemKind.pdf => Icons.picture_as_pdf_outlined,
  DriveItemKind.text => Icons.description_outlined,
  DriveItemKind.other => Icons.insert_drive_file_outlined,
};

/// Color con el que se pinta ese tipo (tinte suave: el panel es claro/oscuro
/// según el tema y estos colores se usan con transparencia).
Color driveKindColor(DriveItemKind kind, ColorScheme scheme) => switch (kind) {
  DriveItemKind.folder => scheme.primary,
  DriveItemKind.image => scheme.tertiary,
  DriveItemKind.video => const Color(0xFF7C4DFF),
  DriveItemKind.audio => const Color(0xFF00897B),
  DriveItemKind.pdf => const Color(0xFFE53935),
  DriveItemKind.text => const Color(0xFF546E7A),
  DriveItemKind.other => scheme.onSurfaceVariant,
};

/// Ficha compacta con el tipo y, si el archivo no tiene vista previa, su
/// extensión: «Vídeo · MP4».
String driveKindChip(DriveItem item) {
  final label = driveKindLabel(item.kind);
  final ext = driveExtensionLabel(item.name);
  if (item.isFolder || ext.isEmpty) return label;
  return '$label · $ext';
}
