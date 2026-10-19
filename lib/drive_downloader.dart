import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_platform.dart';
import 'drive_api_service.dart';
import 'drive_service.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart';

/// Canal nativo (Android) que deja el archivo en la carpeta de DESCARGAS del
/// dispositivo. En Android no hay diálogo "Guardar como": file_selector no lo
/// implementa (lanzaba `UnimplementedError: getSavePath()`), así que la app
/// guarda en Descargas y avisa dónde quedó.
const MethodChannel _downloadsChannel = MethodChannel('hardstreet/downloads');

/// ¿Hay que preguntar el destino con el diálogo del sistema?
/// En Android NO: se guarda directo en Descargas (y así lo espera el usuario).
bool get needsSaveDialog => !kIsWeb && !isAndroidPlatform;

/// Descarga la selección EN SEGUNDO PLANO.
///
/// * 1 archivo → se guarda tal cual; varios (o carpetas) → un ZIP.
/// * En nativo se pregunta ANTES el destino (diálogo Guardar) y luego la
///   descarga sigue en segundo plano: el panel de transferencias muestra el
///   progreso al lado de las subidas, sin bloquear la pantalla.
/// * En web no hay diálogo: el navegador guarda al terminar.
Future<void> downloadDriveSelection(
  BuildContext context, {
  required DriveBase drive,
  required List<DriveItem> items,
  List<String>? from,
}) async {
  if (items.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final single = items.length == 1 && !items.first.isFolder;
  final suggested =
      single ? items.first.name : zipSuggestedName(drive.locationLabel);

  // 1. Destino (solo escritorio; en web decide el navegador y en Android la
  //    carpeta de Descargas del sistema).
  String? targetPath;
  if (needsSaveDialog) {
    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null) return; // el usuario canceló
    targetPath = location.path;
  }

  // 2. El trabajo vive en el panel: la espera ya no bloquea la interfaz.
  final job = drive.startDownload(
    suggested,
    items: List<DriveItem>.of(items),
    targetPath: targetPath,
    from: from,
  );
  unawaited(_runDownloadJob(drive, job, messenger));
}

/// Reintenta una descarga fallida desde el panel (mismo destino).
Future<void> retryDriveDownload(
  BuildContext context,
  DriveBase drive,
  DriveDownloadJob job,
) {
  final messenger = ScaffoldMessenger.of(context);
  drive.restartDownloadJob(job);
  return _runDownloadJob(drive, job, messenger);
}

/// Hace el trabajo real de un [DriveDownloadJob] y lo cierra en el panel.
Future<void> _runDownloadJob(
  DriveBase drive,
  DriveDownloadJob job,
  ScaffoldMessengerState messenger,
) async {
  try {
    final bytes = await fetchDriveBytes(
      drive,
      job.items,
      from: job.from,
      onProgress: (received, total) {
        if (job.cancelled) throw 'Cancelado';
        job.received = received;
        job.total = total;
        drive.notifyDownloadProgress();
      },
    );
    if (job.cancelled) throw 'Cancelado';
    if (bytes.isEmpty) throw 'No hay nada que descargar';

    // Dónde quedó, para poder decirlo (en Android es una carpeta del sistema).
    String? savedTo;
    if (kIsWeb) {
      triggerBrowserDownload(bytes, job.name);
    } else if (job.targetPath != null) {
      await File(job.targetPath!).writeAsBytes(bytes);
    } else if (isAndroidPlatform) {
      savedTo = await saveToAndroidDownloads(bytes, job.name);
      if (savedTo == null) throw 'No se pudo guardar en Descargas';
    } else {
      throw 'No se pudo determinar el destino de la descarga';
    }
    drive.finishDownloadJob(job);
    if (!kIsWeb) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            savedTo == null
                ? 'Descargado: ${job.name} '
                    '(${(bytes.length / 1024).toStringAsFixed(0)} KB)'
                : 'Descargado en $savedTo',
          ),
        ),
      );
    }
  } catch (e) {
    drive.finishDownloadJob(job, error: '$e');
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo descargar "${job.name}": $e')),
    );
  }
}

/// Deja la descarga en la carpeta pública de DESCARGAS del dispositivo
/// (Android) y devuelve una etiqueta legible del destino ("Descargas/x.zip"),
/// o null si no se pudo.
///
/// Los bytes se pasan por un archivo TEMPORAL: el canal nativo copia ese
/// archivo (no se copian megabytes de memoria a memoria por el canal) y el
/// temporal se borra siempre, salga bien o mal.
/// Público para poder verificarlo en test/. [tempDir] permite fijar el
/// directorio temporal (en pruebas, sin depender del plugin de plataforma).
Future<String?> saveToAndroidDownloads(
  List<int> bytes,
  String name, {
  String? tempDir,
}) async {
  final dir = tempDir ?? (await getTemporaryDirectory()).path;
  final tmp = File('$dir${Platform.pathSeparator}$name');
  await tmp.writeAsBytes(bytes, flush: true);
  try {
    return await _downloadsChannel.invokeMethod<String>('save', {
      'path': tmp.path,
      'name': name,
    });
  } finally {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
      // El temporal se queda: no es motivo para reportar una descarga fallida.
    }
  }
}

/// Obtiene los bytes de la selección desde el backend o del disco local.
/// PÚBLICO para poder verificar en test/ que una descarga individual NO se
/// guarda como ZIP (que es lo que la corrompía).
Future<List<int>> fetchDriveBytes(
  DriveBase drive,
  List<DriveItem> items, {
  required void Function(int received, int total) onProgress,
  List<String>? from,
}) async {
  final single = items.length == 1 && !items.first.isFolder;
  final folder = from == null
      ? drive.path
      : from.where((s) => s.isNotEmpty).toList(growable: false);
  if (single) {
    final item = items.first;
    if (drive is DriveApiService) {
      final raw = await drive.downloadZip([item.name],
          from: folder, onProgress: onProgress);
      // El backend responde con un ZIP incluso para UN archivo: si se guardara
      // tal cual con la extensión de la foto, el archivo queda corrupto.
      return extractSingleFile(raw, item.name) ?? raw;
    }
    final src = File(drive.absolutePathIn(folder, item));
    if (!await src.exists()) throw 'El archivo ya no existe';
    return src.readAsBytes();
  }
  if (drive is DriveApiService) {
    return drive.downloadZip(
      items.map((i) => i.name).toList(),
      from: folder,
      onProgress: onProgress,
    );
  }
  return buildLocalZipBytes(drive as DriveService, items, rel: folder);
}

/// Si [bytes] es un ZIP con UNA sola entrada de archivo, devuelve su
/// contenido decompuesto (y `null` si no aplica).
///
/// Evita que una descarga individual termine guardada como ZIP con extensión
/// de imagen ("parece que este formato de archivo no está disponible").
/// Público para poder verificarlo desde test/.
List<int>? extractSingleFile(List<int> bytes, String name) {
  if (bytes.length < 4) return null;
  // Firma de ZIP: 'P','K'.
  if (bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.length != 1) return null;
    final content = files.first.content;
    return content.isNotEmpty ? content : null;
  } catch (_) {
    return null;
  }
}

/// ZIP con la selección de un drive LOCAL, generado en un isolate aparte
/// (la UI no se congela). Público para poder verificar su contenido en test/.
Future<List<int>> buildLocalZipBytes(
  DriveService drive,
  List<DriveItem> items, {
  List<String>? rel,
}) {
  final job = _ZipJob(
    root: drive.root.path,
    rel: List<String>.of(rel ?? drive.path),
    names: items
        .map((i) => _ZipEntry(name: i.name, isFolder: i.isFolder))
        .toList(),
  );
  return compute(_buildZip, job);
}

// ===================== ZIP local en isolate =====================

class _ZipEntry {
  _ZipEntry({required this.name, required this.isFolder});
  final String name;
  final bool isFolder;
}

class _ZipJob {
  _ZipJob({required this.root, required this.rel, required this.names});
  final String root;
  final List<String> rel;
  final List<_ZipEntry> names;
}

List<int> _buildZip(_ZipJob job) {
  final archive = Archive();
  final encoder = ZipEncoder();

  void addFile(String absPath, String arcName) {
    final f = File(absPath);
    if (!f.existsSync()) return;
    final bytes = f.readAsBytesSync();
    archive.add(
      ArchiveFile.bytes(arcName.replaceAll('\\', '/'), bytes),
    );
  }

  void addDir(Directory dir, String arcPrefix) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      final arcName = '$arcPrefix/$name';
      // Cualquier archivo entra en el ZIP: una carpeta del Drive ya no tiene
      // solo fotos (antes los vídeos y documentos se quedaban fuera).
      if (e is File) {
        addFile(e.path, arcName);
      } else if (e is Directory) {
        archive.add(ArchiveFile.string('$arcName/', ''));
        addDir(e, arcName); // recursivo
      }
    }
  }

  final folderPath = [job.root, ...job.rel].join(Platform.pathSeparator);
  for (final it in job.names) {
    final p = [folderPath, it.name].join(Platform.pathSeparator);
    if (it.isFolder) {
      final d = Directory(p);
      if (d.existsSync()) {
        archive.add(ArchiveFile.string('${it.name}/', ''));
        addDir(d, it.name);
      }
    } else {
      addFile(p, it.name);
    }
  }

  return encoder.encode(archive);
}

// ===================== Nombre sugerido =====================

String zipSuggestedName(String locationLabel) {
  final clean = locationLabel == 'Mi Drive' ? 'mi-drive' : locationLabel;
  return 'hardstreet-${clean.replaceAll(RegExp(r'[^\w-]'), '-')}.zip';
}

/// Formatea bytes para el panel ("1.2 MB").
String transferSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
