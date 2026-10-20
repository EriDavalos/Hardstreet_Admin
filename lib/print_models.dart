import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';

// ==================================================================
// IMPRESIONES: MODELOS Y RECORTE
// ==================================================================
// El formato de impresión manda la PROPORCIÓN: 5x7, 1x1, 12x18… El recorte
// se calcula sobre la foto ORIGINAL (misma resolución), como en Lightroom:
//
//   * `focus` (0..1) es el centro del recorte dentro de la foto;
//   * `zoom` (1..4) encoge el recorte (acerca la foto);
//   * `border` (%) es el grosor del borde blanco: el marco NO cambia de
//     tamaño, así que al subir el borde la foto se hace más pequeña.
//
// Este archivo es puro (sin red ni widgets) para poder probarlo.
// ==================================================================

/// Un formato de impresión: nombre visible + medidas.
class PrintFormat {
  const PrintFormat({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.unit = 'in',
  });

  final int id;
  final String name;
  final double width;
  final double height;
  final String unit;

  /// Proporción ancho / alto (nunca 0).
  double get ratio => (height <= 0 || width <= 0) ? 1 : width / height;

  /// "5 × 7 in" (solo informativo; el recorte usa la proporción).
  String get sizeLabel {
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${n(width)} × ${n(height)} ${unit == 'cm' ? 'cm' : 'in'}';
  }

  static PrintFormat? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final name = (json['name'] ?? '').toString().trim();
    final width = (json['width'] as num?)?.toDouble() ?? 0;
    final height = (json['height'] as num?)?.toDouble() ?? 0;
    if (id <= 0 || name.isEmpty || width <= 0 || height <= 0) return null;
    return PrintFormat(
      id: id,
      name: name,
      width: width,
      height: height,
      unit: (json['unit'] ?? 'in').toString().trim().isEmpty
          ? 'in'
          : (json['unit'] ?? 'in').toString().trim(),
    );
  }

  @override
  String toString() => 'PrintFormat($id, $name, $ratio)';
}

/// Ajuste de recorte de UNA foto.
class PrintCrop {
  const PrintCrop({
    this.focusX = .5,
    this.focusY = .5,
    this.zoom = 1,
    this.landscape,
  });

  /// Centro del recorte, en proporción de la foto (0..1).
  final double focusX;
  final double focusY;

  /// 1 = recorte más grande posible; 4 = cuatro veces más cerca.
  final double zoom;

  /// Orientación del recorte. `null` = automática: horizontal si la foto es
  /// horizontal (así una foto apaisada no se recorta en vertical sin querer).
  /// Se guarda al ajustar, y el usuario puede cambiarla cuando quiera.
  final bool? landscape;

  /// Proporción ancho/alto que se usa para ESTA foto.
  ///
  /// El formato manda (5x7 = vertical), salvo que se haya pedido el giro o
  /// que la orientación sea automática y la foto venga apaisada.
  double ratioFor(PrintFormat format, Size image) {
    final base = format.ratio;
    if (base <= 0) return 1;
    final wide = landscape ?? (image.width >= image.height);
    return wide ? 1 / base : base;
  }

  PrintCrop copyWith({
    double? focusX,
    double? focusY,
    double? zoom,
    bool? landscape,
  }) => PrintCrop(
    focusX: (focusX ?? this.focusX).clamp(0.0, 1.0),
    focusY: (focusY ?? this.focusY).clamp(0.0, 1.0),
    zoom: (zoom ?? this.zoom).clamp(1.0, 8.0),
    landscape: landscape ?? this.landscape,
  );

  /// Para guardar la posición en el servidor (mismas claves que el backend).
  Map<String, dynamic> toJson() => {
    'x': focusX,
    'y': focusY,
    'zoom': zoom,
    if (landscape != null) 'landscape': landscape,
  };

  /// Lee una posición guardada. Devuelve null si el JSON no es válido.
  static PrintCrop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double? num_(String key) {
      final v = raw[key];
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    final x = num_('x');
    final y = num_('y');
    final zoom = num_('zoom');
    if (x == null || y == null || zoom == null) return null;
    return PrintCrop(
      focusX: x.clamp(0.0, 1.0),
      focusY: y.clamp(0.0, 1.0),
      zoom: zoom.clamp(1.0, 8.0),
      landscape: raw['landscape'] is bool ? raw['landscape'] as bool : null,
    );
  }

  /// Rectángulo que se recorta de la imagen ORIGINAL (en sus píxeles).
  ///
  /// La proporción sale del formato; el centro y el zoom, de este ajuste. El
  /// rectángulo SIEMPRE queda dentro de la imagen (no se sale del original).
  Rect sourceRect(Size image, double ratio) {
    if (image.width <= 0 || image.height <= 0 || ratio <= 0) {
      return Rect.zero;
    }
    final z = zoom.clamp(1.0, 8.0);
    double w;
    double h;
    // Recorte máximo con esa proporción.
    if (image.width / image.height > ratio) {
      h = image.height;
      w = h * ratio;
    } else {
      w = image.width;
      h = w / ratio;
    }
    w = w / z;
    h = h / z;
    final maxLeft = math.max(0.0, image.width - w);
    final maxTop = math.max(0.0, image.height - h);
    final left = (focusX * image.width - w / 2).clamp(0.0, maxLeft);
    final top = (focusY * image.height - h / 2).clamp(0.0, maxTop);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Tamaño del marco final: el del recorte (misma resolución).
  Size outputSize(Size image, double ratio) {
    final r = sourceRect(image, ratio);
    return Size(r.width.roundToDouble(), r.height.roundToDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is PrintCrop &&
      other.focusX == focusX &&
      other.focusY == focusY &&
      other.zoom == zoom &&
      other.landscape == landscape;

  @override
  int get hashCode => Object.hash(focusX, focusY, zoom, landscape);
}

/// Borde blanco del marco: píxeles y rectángulo interior de la foto.
///
/// [percent] 0..30. El borde se mide sobre el lado MÁS CORTO del recorte para
/// que en un 5x7 y en un 1x1 se vea igual de grueso.
({double pixels, Rect inner}) borderGeometry(Rect crop, double percent) {
  final minSide = math.min(crop.width, crop.height);
  final pct = percent.clamp(0.0, 30.0);
  final px = minSide * pct / 100;
  final inner = Rect.fromLTWH(
    crop.left + px,
    crop.top + px,
    math.max(1.0, crop.width - px * 2),
    math.max(1.0, crop.height - px * 2),
  );
  return (pixels: px, inner: inner);
}

/// Nombre del archivo final: "foto.jpg" + "5x7" -> "foto_5x7.png".
String printFileName(
  String path,
  PrintFormat format, {
  String fallback = 'foto',
}) {
  final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
  var base = parts.isEmpty ? fallback : parts.last;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.trim().isEmpty ? fallback : base.trim();
  final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final name = format.name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '');
  return '${safe}_${name.isEmpty ? 'impresion' : name}.png';
}

/// Nombres únicos cuando dos fotos de carpetas distintas se llaman igual.
List<String> uniquePrintNames(Iterable<String> names) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in names) {
    var name = raw;
    var i = 1;
    while (seen.contains(name)) {
      final dot = raw.lastIndexOf('.');
      final base = dot > 0 ? raw.substring(0, dot) : raw;
      final ext = dot > 0 ? raw.substring(dot) : '';
      name = '${base}_$i$ext';
      i++;
    }
    seen.add(name);
    out.add(name);
  }
  return out;
}

/// ZIP con las fotos ya recortadas.
Uint8List zipPrintPhotos(List<({String name, Uint8List bytes})> files) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(ArchiveFile(f.name, f.bytes.length, f.bytes));
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}
