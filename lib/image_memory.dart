import 'dart:io';

import 'package:flutter/painting.dart';

/// Gestión de memoria para imágenes: liberación de caché y poda de disco.
class ImageMemory {
  ImageMemory._();

  /// Evicta una imagen de la caché de pintura (p. ej. al cerrar el visor).
  static void evict(String url) {
    PaintingBinding.instance.imageCache.evict(
      NetworkImage(url),
    );
  }

  /// Limpia TODA la caché de imágenes en RAM (llamar al cambiar de carpeta).
  static void clearRam() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Configura límites de la caché de imágenes en RAM (moderados por defecto).
  static void configure({
    int maxImages = 200,
    int maxBytes = 150 << 20, // 150 MB
  }) {
    final c = PaintingBinding.instance.imageCache;
    c.maximumSize = maxImages;
    c.maximumSizeBytes = maxBytes;
  }

  /// Borra el caché de chunks del visor en disco (archivos .part incluidos),
  /// dejando solo los más recientes. Llamar al iniciar la app.
  static Future<void> pruneDiskCache({int keep = 40}) async {
    try {
      final dir = Directory(
        [Directory.systemTemp.path, 'hardstreet_cache']
            .join(Platform.pathSeparator),
      );
      if (!await dir.exists()) return;
      final files = (await dir.list().toList())
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part') && !f.path.endsWith('.lm'))
          .toList();
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      for (final f in files.skip(keep)) {
        try {
          await f.delete();
          final lm = File('${f.path}.lm');
          if (await lm.exists()) await lm.delete();
        } catch (_) {}
      }
    } catch (_) {
      // El caché es prescindible.
    }
  }
}
