import 'package:flutter/material.dart';

// ==================================================================
// Iconos del catálogo de SERVICIOS.
//
// El campo `icon` de un servicio guarda una CADENA. Acepta dos formatos:
//   * `material:xxx`  → elegido con el selector del módulo Servicios.
//   * `icon/xxx.svg`  → valor heredado de la web (no renderizable aquí):
//                       se muestra un icono genérico de servicios.
// ==================================================================

/// Catálogo de iconos elegibles (nombre → IconData Material).
const Map<String, IconData> kServiceIcons = {
  'videocam': Icons.videocam_outlined,
  'movie': Icons.movie_outlined,
  'photo_camera': Icons.photo_camera_outlined,
  'photo_library': Icons.photo_library_outlined,
  'album': Icons.album_outlined,
  'music_note': Icons.music_note_outlined,
  'mic': Icons.mic_outlined,
  'location_on': Icons.location_on_outlined,
  'directions_car': Icons.directions_car_outlined,
  'flight': Icons.flight_outlined,
  'checkroom': Icons.checkroom_outlined,
  'restaurant': Icons.restaurant_outlined,
  'cake': Icons.cake_outlined,
  'menu_book': Icons.menu_book_outlined,
  'auto_awesome': Icons.auto_awesome_outlined,
  'celebration': Icons.celebration_outlined,
  'favorite': Icons.favorite_outline,
  'star': Icons.star_outline,
  'palette': Icons.palette_outlined,
  'edit_note': Icons.edit_note_outlined,
  'wallpaper': Icons.wallpaper_outlined,
  'view_carousel': Icons.view_carousel_outlined,
};

const IconData _kFallbackIcon = Icons.miscellaneous_services_outlined;

/// Icono Material para el valor guardado del servicio (o el genérico).
IconData serviceIconOf(String raw) {
  final v = raw.trim();
  if (v.startsWith('material:')) {
    return kServiceIcons[v.substring(9).trim()] ?? _kFallbackIcon;
  }
  return kServiceIcons[v] ?? _kFallbackIcon;
}

/// Valor a guardar para el icono elegido en el selector.
String serviceIconValue(String key) => 'material:$key';
