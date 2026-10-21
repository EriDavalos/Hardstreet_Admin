import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'app_constants.dart';
import 'app_platform.dart';
import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
import 'drive_base.dart' show driveImageToken;
import 'drive_downloader.dart' show saveToAndroidDownloads;
import 'print_models.dart';

// ==================================================================
// IMPRESIONES: DE LA FOTO ORIGINAL AL ARCHIVO IMPRIMIBLE
// ==================================================================
// 1. La vista previa usa la miniatura grande del drive (`/thumb?w=1600`):
//    pesa poco y se ve al instante.
// 2. Al descargar se pide la ORIGINAL (`/files/...`) y se recorta a la
//    proporción del formato SIN reescalar: el PNG sale a la resolución del
//    recorte original.
// 3. Si la selección tiene una foto se guarda el PNG; si tiene varias, un ZIP.
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

/// Recorta/compone la foto al formato elegido y devuelve el PNG.
///
/// El marco final mide lo mismo que el recorte (resolución original); el
/// borde blanco se pinta DENTRO y la foto se encoge, que es lo que se ve en
/// la vista previa.
Future<Uint8List> renderPrintPhoto({
  required ui.Image image,
  required PrintFormat format,
  required PrintCrop crop,
  double borderPercent = 0,
}) async {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  // La foto horizontal se recorta horizontal aunque el formato sea vertical
  // (5x7), salvo que el usuario haya girado el recorte a propósito.
  final src = crop.sourceRect(size, crop.ratioFor(format, size));
  if (src.width < 1 || src.height < 1) {
    throw 'La foto es demasiado pequeña para ese formato';
  }
  final outW = math.max(1, src.width.round());
  final outH = math.max(1, src.height.round());
  final border = borderGeometry(src, borderPercent).pixels;

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
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  picture.dispose();
  if (bytes == null) throw 'No se pudo generar la imagen de impresión';
  return bytes.buffer.asUint8List();
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
