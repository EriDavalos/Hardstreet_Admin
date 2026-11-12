import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'package:hardstreet_admin/app/app_constants.dart';
import 'package:hardstreet_admin/app/app_platform.dart';
import 'package:hardstreet_admin/core/platform/download_stub.dart'
    if (dart.library.js_interop) 'package:hardstreet_admin/core/platform/download_web.dart';
import 'package:hardstreet_admin/modules/drive/services/drive_base.dart'
    show driveImageToken;
import 'package:hardstreet_admin/modules/drive/services/drive_downloader.dart'
    show saveToAndroidDownloads;
import 'package:hardstreet_admin/modules/print/models/print_models.dart';

// ==================================================================
// IMPRESIONES: DE LA FOTO ORIGINAL AL ARCHIVO IMPRIMIBLE
// ==================================================================
// 1. La vista previa usa la miniatura grande del drive (`/thumb?w=1600`):
//    pesa poco y se ve al instante.
// 2. Al descargar se pide la ORIGINAL (`/files/...`) y se recorta a la
//    proporción del formato SIN reescalar: el PNG sale a la resolución del
//    recorte original.
// 3. Si se elige TIFF CMYK, la foto se convierte a cuatro tintas y se guarda
//    como TIFF con un perfil ICC incrustado, el formato de entrega habitual
//    para imprenta. La vista previa NO simula el color impreso: enseña la foto
//    original, porque una simulación sin el perfil de la imprenta engaña más
//    de lo que ayuda.
// 4. Si la selección tiene una foto se guarda ese archivo; si tiene varias,
//    un ZIP.
// ==================================================================

/// URL de la miniatura grande de una foto (para la vista previa).
///
/// LLEVA el token de la sesión en la query (`&apikey=`), igual que las demás
/// miniaturas del panel: `/thumb` no pide permisos, pero SÍ usa la sesión para
/// saber en qué CARPETA DE EMPRESA vive la foto. Sin el token, la ruta de un
/// usuario de empresa se buscaba en la raíz del disco y el servidor respondía
/// 404 — por eso las fotos del módulo Impresiones no se veían (ni la
/// cuadrícula de envíos ni la vista previa del editor de formatos).
String printPreviewUrl(String path, {int width = 1600}) {
  final clean = path
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  if (clean.isEmpty) return '';
  final w = width.clamp(32, 2048);
  final base = '${AppConstants.apiBase}/thumb/$clean?w=$w';
  final token = driveImageToken.trim();
  return token.isEmpty
      ? base
      : '$base&apikey=${Uri.encodeQueryComponent(token)}';
}

/// URL de la ORIGINAL de una foto del drive (con el token de la sesión).
String printPhotoUrl(String path) {
  final clean = path
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  if (clean.isEmpty) return '';
  final token = driveImageToken.trim();
  return '${AppConstants.apiBase}/files/$clean'
      '${token.isEmpty ? '' : '?apikey=${Uri.encodeQueryComponent(token)}'}';
}

/// Descarga los bytes de una foto (miniatura u original).
Future<Uint8List> fetchPrintPhoto(String url) async {
  final res = await http
      .get(Uri.parse(url))
      .timeout(const Duration(minutes: 2));
  if (res.statusCode != 200) {
    throw 'La foto no se pudo descargar (HTTP ${res.statusCode})';
  }
  return res.bodyBytes;
}

/// Decodifica los bytes a una imagen de `dart:ui` (para pintar y recortar).
Future<ui.Image> decodePrintImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Carga la MINIATURA grande de una foto (vista previa del editor).
Future<ui.Image> loadPrintPreview(String path, {int width = 1600}) async {
  final url = printPreviewUrl(path, width: width);
  if (url.isEmpty) throw 'La foto no tiene ruta';
  return decodePrintImage(await fetchPrintPhoto(url));
}

/// Carga la imagen ORIGINAL de una foto (para el archivo final).
Future<ui.Image> loadPrintOriginal(String path) async {
  final url = printPhotoUrl(path);
  if (url.isEmpty) throw 'La foto no tiene ruta';
  return decodePrintImage(await fetchPrintPhoto(url));
}

/// Recorta/compone la foto al formato elegido y devuelve la imagen.
///
/// El marco final mide lo mismo que el recorte (resolución original), salvo
/// que [outputSize] pida otra medida (por ejemplo, 300 ppp para el TIFF CMYK).
/// El borde blanco se pinta DENTRO y la foto se encoge, igual que se ve en la
/// vista previa.
Future<ui.Image> renderPrintFrame({
  required ui.Image image,
  required PrintFormat format,
  required PrintCrop crop,
  double borderPercent = 0,
  Size? outputSize,
}) async {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  // La foto horizontal se recorta horizontal aunque el formato sea vertical
  // (5x7), salvo que el usuario haya girado el recorte a propósito.
  final src = crop.sourceRect(size, crop.ratioFor(format, size));
  if (src.width < 1 || src.height < 1) {
    throw 'La foto es demasiado pequeña para ese formato';
  }
  final outW = math.max(1, (outputSize?.width ?? src.width).round());
  final outH = math.max(1, (outputSize?.height ?? src.height).round());
  final scale = outW / src.width;
  final border = borderGeometry(src, borderPercent).pixels * scale;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final inner = Rect.fromLTWH(
    border,
    border,
    math.max(1, outW - border * 2),
    math.max(1, outH - border * 2),
  );
  // La foto se recorta otra vez a la proporción del HUECO interior para no
  // deformarse cuando el borde es grueso.
  final sub = _fitRect(src, inner.width / inner.height);
  canvas.drawImageRect(
    image,
    sub,
    inner,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(outW, outH);
  picture.dispose();
  return out;
}

/// Recorta/compone la foto al formato elegido y devuelve el PNG.
Future<Uint8List> renderPrintPhoto({
  required ui.Image image,
  required PrintFormat format,
  required PrintCrop crop,
  double borderPercent = 0,
}) async {
  final out = await renderPrintFrame(
    image: image,
    format: format,
    crop: crop,
    borderPercent: borderPercent,
  );
  try {
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw 'No se pudo generar la imagen de impresión';
    return bytes.buffer.asUint8List();
  } finally {
    out.dispose();
  }
}

/// Salida del módulo de impresión. PNG conserva el comportamiento de antes;
/// TIFF guarda una foto CMYK con perfil ICC, lista para imprenta.
enum PrintOutputMode { png, cmykTiff }

/// Perfil internacional que se incrusta en el TIFF.
///
/// Es un perfil SWOP 2006 Coated con límite de tinta 300 %, liberado bajo CC0
/// por el proyecto Amethyst CMYK ICC Profiles. Si una imprenta pide otro
/// perfil (FOGRA39, GRACoL…), basta con reemplazar este archivo por el suyo.
const String printCmykProfileAsset =
    'assets/profiles/SWOP2006coated_300_mth.icc';

Future<Uint8List>? _printCmykProfile;

/// Carga una sola vez el perfil ICC que se incrusta en cada TIFF.
Future<Uint8List> loadPrintCmykProfile() {
  return _printCmykProfile ??= rootBundle
      .load(printCmykProfileAsset)
      .then(
        (data) => Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
}

/// Convierte RGBA a CMYK Device (un byte por canal).
///
/// [maxInk] es el límite de tinta total (TAC): 3.0 = 300 %, habitual en
/// imprenta. El alfa se compone sobre blanco porque el TIFF no lleva
/// transparencias.
Uint8List rgbaToCmyk(Uint8List rgba, {double maxInk = 3.0}) {
  final pixels = rgba.length ~/ 4;
  final out = Uint8List(pixels * 4);
  var j = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3] / 255;
    final r = (rgba[i] * a + 255 * (1 - a)) / 255;
    final g = (rgba[i + 1] * a + 255 * (1 - a)) / 255;
    final b = (rgba[i + 2] * a + 255 * (1 - a)) / 255;
    final k = 1.0 - math.max(r, math.max(g, b));
    var c = 0.0;
    var m = 0.0;
    var y = 0.0;
    if (k < 1) {
      final inv = 1 - k;
      c = (1 - r - k) / inv;
      m = (1 - g - k) / inv;
      y = (1 - b - k) / inv;
    }
    if (maxInk > 0 && maxInk < 4) {
      final total = c + m + y + k;
      final cmY = c + m + y;
      if (total > maxInk && cmY > 0) {
        final room = math.max(0.0, maxInk - k);
        final scale = room / cmY;
        c *= scale;
        m *= scale;
        y *= scale;
      }
    }
    int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
    out[j++] = byte(c);
    out[j++] = byte(m);
    out[j++] = byte(y);
    out[j++] = byte(k);
  }
  return out;
}

/// Construye un TIFF de una tira con separación CMYK y perfil ICC.
///
/// El archivo queda con `PhotometricInterpretation = Separated` (5),
/// `InkSet = CMYK` (1), 4 canales de 8 bits, resolución física [xDpi] × [yDpi]
/// y el perfil en el tag ICC (34675). Los píxeles se comprimen con Deflate
/// cuando eso reduce el tamaño; si no, se guardan sin comprimir.
Uint8List buildCmykTiff({
  required int pixelWidth,
  required int pixelHeight,
  required Uint8List cmyk,
  required Uint8List iccProfile,
  double xDpi = 300,
  double yDpi = 300,
}) {
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    throw 'El TIFF CMYK necesita un tamaño de imagen válido';
  }
  if (cmyk.length != pixelWidth * pixelHeight * 4) {
    throw 'Los datos CMYK no coinciden con el tamaño de la imagen';
  }
  if (iccProfile.isEmpty) {
    throw 'El TIFF CMYK necesita un perfil ICC';
  }

  final compressed = Uint8List.fromList(ZLibEncoder().encode(cmyk));
  final useDeflate = compressed.length < cmyk.length;
  final pixels = useDeflate ? compressed : cmyk;
  final compression = useDeflate ? 8 : 1;
  final resX = xDpi.isFinite && xDpi > 0 ? xDpi.round() : 300;
  final resY = yDpi.isFinite && yDpi > 0 ? yDpi.round() : 300;

  const entryCount = 18;
  var cursor = 8 + 2 + entryCount * 12 + 4;
  int alloc(int length) {
    if (cursor.isOdd) cursor++;
    final at = cursor;
    cursor += length;
    return at;
  }

  final bitsOffset = alloc(8);
  final sampleFormatOffset = alloc(8);
  final xResOffset = alloc(8);
  final yResOffset = alloc(8);
  final iccOffset = alloc(iccProfile.length);
  final pixelsOffset = alloc(pixels.length);

  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out);
  data.setUint16(0, 0x4949, Endian.little); // "II"
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, 8, Endian.little); // primer IFD
  data.setUint16(8, entryCount, Endian.little);

  var entry = 8 + 2;
  void addTag(int tag, int type, int count, int value) {
    data.setUint16(entry, tag, Endian.little);
    data.setUint16(entry + 2, type, Endian.little);
    data.setUint32(entry + 4, count, Endian.little);
    data.setUint32(entry + 8, value, Endian.little);
    entry += 12;
  }

  // Los tags van en orden ascendente, como exige el formato.
  addTag(256, 4, 1, pixelWidth); // ImageWidth
  addTag(257, 4, 1, pixelHeight); // ImageLength
  addTag(258, 3, 4, bitsOffset); // BitsPerSample
  addTag(259, 3, 1, compression); // Compression
  addTag(262, 3, 1, 5); // PhotometricInterpretation = Separated
  addTag(273, 4, 1, pixelsOffset); // StripOffsets
  addTag(277, 3, 1, 4); // SamplesPerPixel
  addTag(278, 4, 1, pixelHeight); // RowsPerStrip
  addTag(279, 4, 1, pixels.length); // StripByteCounts
  addTag(282, 5, 1, xResOffset); // XResolution
  addTag(283, 5, 1, yResOffset); // YResolution
  addTag(284, 3, 1, 1); // PlanarConfiguration = chunky
  addTag(296, 3, 1, 2); // ResolutionUnit = inch
  addTag(317, 3, 1, 1); // Predictor = none
  addTag(332, 3, 1, 1); // InkSet = CMYK
  addTag(334, 3, 1, 4); // NumberOfInks
  addTag(339, 3, 4, sampleFormatOffset); // SampleFormat = unsigned
  addTag(34675, 7, iccProfile.length, iccOffset); // ICC Profile
  data.setUint32(entry, 0, Endian.little); // siguiente IFD

  for (var i = 0; i < 4; i++) {
    data.setUint16(bitsOffset + i * 2, 8, Endian.little);
    data.setUint16(sampleFormatOffset + i * 2, 1, Endian.little);
  }
  data.setUint32(xResOffset, resX, Endian.little);
  data.setUint32(xResOffset + 4, 1, Endian.little);
  data.setUint32(yResOffset, resY, Endian.little);
  data.setUint32(yResOffset + 4, 1, Endian.little);
  out.setRange(iccOffset, iccOffset + iccProfile.length, iccProfile);
  out.setRange(pixelsOffset, pixelsOffset + pixels.length, pixels);

  return out;
}

/// Tamaño en píxeles y resolución física para el TIFF CMYK.
///
/// Intenta 300 ppp y baja la resolución solo si el archivo pasaría de ~18 Mpx
/// (para no agotar la memoria en un lote grande). La resolución del TIFF se
/// ajusta a los píxeles reales para que el tamaño físico siga siendo el del
/// formato elegido.
({int pixelsWide, int pixelsHigh, double xDpi, double yDpi})
printCmykImageSetup(PrintFormat format, double cropRatio) {
  final a = math.max(0.1, _printInches(format.width, format.unit));
  final b = math.max(0.1, _printInches(format.height, format.unit));
  final longSide = math.max(a, b);
  final shortSide = math.min(a, b);
  final landscape = cropRatio >= 1;
  final pageW = landscape ? longSide : shortSide;
  final pageH = landscape ? shortSide : longSide;
  const targetDpi = 300.0;
  const maxPixels = 18e6;
  final scale = math.min(
    1.0,
    math.sqrt(maxPixels / (pageW * pageH * targetDpi * targetDpi)),
  );
  final pixelsWide = math.max(1, (pageW * targetDpi * scale).round());
  final pixelsHigh = math.max(1, (pageH * targetDpi * scale).round());
  return (
    pixelsWide: pixelsWide,
    pixelsHigh: pixelsHigh,
    xDpi: pageW > 0 ? pixelsWide / pageW : targetDpi,
    yDpi: pageH > 0 ? pixelsHigh / pageH : targetDpi,
  );
}

double _printInches(double value, String unit) =>
    unit.trim().toLowerCase() == 'cm' ? value / 2.54 : value;

/// Recorta/compone la foto y devuelve el TIFF CMYK con perfil incrustado.
Future<Uint8List> renderPrintCmykImage({
  required ui.Image image,
  required PrintFormat format,
  required PrintCrop crop,
  double borderPercent = 0,
  Uint8List? iccProfile,
}) async {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final ratio = crop.ratioFor(format, size);
  final setup = printCmykImageSetup(format, ratio);
  final frame = await renderPrintFrame(
    image: image,
    format: format,
    crop: crop,
    borderPercent: borderPercent,
    outputSize: Size(setup.pixelsWide.toDouble(), setup.pixelsHigh.toDouble()),
  );
  try {
    final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw 'No se pudo leer la imagen para CMYK';
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final cmyk = rgbaToCmyk(rgba);
    final profile = iccProfile ?? await loadPrintCmykProfile();
    return buildCmykTiff(
      pixelWidth: frame.width,
      pixelHeight: frame.height,
      cmyk: cmyk,
      iccProfile: profile,
      xDpi: setup.xDpi,
      yDpi: setup.yDpi,
    );
  } finally {
    frame.dispose();
  }
}

/// Recorta [src] a la proporción [ratio] manteniendo el centro.
Rect _fitRect(Rect src, double ratio) {
  if (ratio <= 0 || src.width <= 0 || src.height <= 0) return src;
  var w = src.width;
  var h = src.height;
  if (w / h > ratio) {
    w = h * ratio;
  } else {
    h = w / ratio;
  }
  return Rect.fromCenter(center: src.center, width: w, height: h);
}

/// Guarda el archivo (foto suelta o ZIP) en cada plataforma.
///
/// En el navegador el archivo lo baja el navegador; en Android va a Descargas;
/// en escritorio se pregunta el destino. Si [targetPath] ya viene elegido (un
/// solo diálogo para todo el lote) se usa ese.
Future<void> savePrintBytes(
  List<int> bytes,
  String name, {
  String? targetPath,
}) async {
  if (kIsWeb) {
    triggerBrowserDownload(bytes, name);
    return;
  }
  if (targetPath != null) {
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return;
  }
  if (isAndroidPlatform) {
    final saved = await saveToAndroidDownloads(bytes, name);
    if (saved == null) throw 'No se pudo guardar en Descargas';
    return;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return; // el usuario canceló
  await File(location.path).writeAsBytes(bytes, flush: true);
}

/// ¿Hay que preguntar el destino ANTES de generar las fotos?
bool get printNeedsSaveDialog => !kIsWeb && !isAndroidPlatform;
