import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_platform.dart';
import 'drive_api_service.dart';
import 'drive_service.dart';
import 'download_stub.dart' if (dart.library.html) 'download_web.dart';

/// Canal nativo (Android) que deja el archivo en la carpeta de DESCARGAS del
/// dispositivo. En Android no hay diálogo "Guardar como": file_selector no lo
/// implementa (lanzaba `UnimplementedError: getSavePath()`), así que la app
/// guarda en Descargas y avisa dónde quedó.
const MethodChannel _downloadsChannel = MethodChannel('hardstreet/downloads');

/// ¿Se descarga UNO POR UNO (sin ZIP)?
///
/// En el CELULAR —la app de Android/iOS o la web en el navegador del teléfono—
/// el usuario quiere SUS fotos sueltas: al marcar 12 fotos se bajan 12
/// archivos. Un ZIP no le sirve: los navegadores móviles no lo abren bien y la
/// galería no lo muestra.
bool get downloadsOneByOne =>
    isAndroidPlatform || isIOSPlatform || (kIsWeb && isMobileBrowser());

/// Carpeta de DESCARGAS del sistema (computadora).
///
/// Antes cada descarga abría el diálogo "Guardar como" y el usuario siempre
/// elegía Descargas. Ahora se guarda ahí directo y solo se avisa dónde quedó.
Future<Directory> desktopDownloadsDirectory() async {
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) {
      await dir.create(recursive: true);
      return dir;
    }
  } catch (_) {
    // Sin carpeta del sistema: se intenta la ruta de siempre.
  }
  final home =
      platformEnvironment['USERPROFILE'] ?? platformEnvironment['HOME'];
  if (home != null && home.isNotEmpty) {
    final dir = Directory('$home${Platform.pathSeparator}Downloads');
    try {
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      // Sin permiso: se cae al temporal.
    }
  }
  return getTemporaryDirectory();
}

/// Ruta LIBRE dentro de [directory] para [name] ("foto.png", "foto (1).png"…).
/// Pública para poder verificarla en test/.
Future<String> availableDownloadPath(String directory, String name) async {
  final sep = Platform.pathSeparator;
  final safe = name.trim().isEmpty ? 'descarga' : name.trim();
  final dot = safe.lastIndexOf('.');
  final stem = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';
  var path = '$directory$sep$safe';
  var i = 1;
  while (await File(path).exists() && i <= 500) {
    path = '$directory$sep$stem ($i)$ext';
    i++;
  }
  return path;
}

/// Descarga la selección EN SEGUNDO PLANO.
///
/// * COMPUTADORA: 1 archivo → se guarda tal cual; varios (o carpetas) → un
///   ZIP. Siempre en la carpeta de Descargas, sin diálogo "Guardar como".
/// * CELULAR (app o web): cada archivo se baja POR SEPARADO, sin ZIP.
/// * La descarga sigue aunque el usuario salga de la pantalla: el panel de
///   transferencias muestra el progreso al lado de las subidas.
Future<void> downloadDriveSelection(
  BuildContext context, {
  required DriveBase drive,
  required List<DriveItem> items,
  List<String>? from,
}) async {
  if (items.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);

  // CELULAR: uno por uno (las carpetas se expanden a sus archivos).
  if (downloadsOneByOne) {
    unawaited(_downloadOneByOne(drive, items, from, messenger));
    return;
  }

  final single = items.length == 1 && !items.first.isFolder;
  final suggested = single
      ? items.first.name
      : zipSuggestedName(drive.locationLabel);

  // Destino: la carpeta de Descargas del sistema. En web decide el navegador.
  String? targetPath;
  if (!kIsWeb) {
    try {
      final dir = await desktopDownloadsDirectory();
      targetPath = await availableDownloadPath(dir.path, suggested);
    } catch (_) {
      targetPath = null; // sin destino conocido: el trabajo lo reporta
    }
  }

  // El trabajo vive en el panel: la espera no bloquea la interfaz.
  final job = drive.startDownload(
    suggested,
    items: List<DriveItem>.of(items),
    targetPath: targetPath,
    from: from,
  );
  unawaited(_runDownloadJob(drive, job, messenger));
}

/// Un archivo suelto de la selección, con la carpeta DE DONDE sale.
class IndividualDownload {
  const IndividualDownload(this.folder, this.item);

  final List<String> folder;
  final DriveItem item;
}

/// Expande la selección a ARCHIVOS sueltos (las carpetas, recursivamente).
/// Pública para poder verificarla en test/.
Future<List<IndividualDownload>> collectIndividualFiles(
  DriveBase drive,
  List<DriveItem> items,
  List<String> folder, {
  int depth = 0,
}) async {
  final out = <IndividualDownload>[];
  for (final item in items) {
    if (!item.isFolder) {
      out.add(IndividualDownload(folder, item));
      continue;
    }
    if (depth >= 6) continue; // carpetas absurdamente anidadas: no nos colgamos
    final sub = [...folder, item.name];
    final children = await drive.listFolderItems(sub);
    out.addAll(await collectIndividualFiles(drive, children, sub,
        depth: depth + 1));
  }
  return out;
}

/// Baja la selección ARCHIVO POR ARCHIVO (celular), en un trabajo por archivo
/// para que el panel muestre el avance de cada uno y se pueda reintentar.
Future<void> _downloadOneByOne(
  DriveBase drive,
  List<DriveItem> items,
  List<String>? from,
  ScaffoldMessengerState messenger,
) async {
  final folder = (from ?? drive.path)
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  List<IndividualDownload> files;
  try {
    files = await collectIndividualFiles(drive, items, folder);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo leer la carpeta: $e')),
    );
    return;
  }
  if (files.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No hay archivos que descargar')),
    );
    return;
  }

  var done = 0;
  var cancelled = false;
  String? firstError;
  for (final file in files) {
    final job = drive.startDownload(
      file.item.name,
      items: <DriveItem>[file.item],
      from: file.folder,
    );
    await _runDownloadJob(drive, job, messenger, quiet: true);
    if (job.status == 'done') {
      done++;
    } else {
      firstError ??= job.error;
      if (job.cancelled) {
        cancelled = true;
        break;
      }
    }
  }

  if (cancelled) return;
  final String text;
  if (done == files.length) {
    text = done == 1
        ? (isAndroidPlatform
              ? 'Descargado en Descargas: ${files.first.item.name}'
              : 'Descargado: ${files.first.item.name}')
        : '$done descargas en la carpeta de Descargas';
  } else if (done == 0) {
    text = 'No se pudo descargar: ${firstError ?? 'error desconocido'}';
  } else {
    text = '$done de ${files.length} descargas completadas'
        '${firstError == null ? '' : ' · $firstError'}';
  }
  messenger.showSnackBar(SnackBar(content: Text(text)));
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
///
/// [quiet] = no avisar archivo por archivo: lo usa la descarga del celular, que
/// baja varias fotos seguidas y resume al final.
Future<void> _runDownloadJob(
  DriveBase drive,
  DriveDownloadJob job,
  ScaffoldMessengerState messenger, {
  bool quiet = false,
}) async {
  try {
    void progress(int received, int total) {
      if (job.cancelled) throw 'Cancelado';
      job.received = received;
      job.total = total;
      drive.notifyDownloadProgress();
    }

    // UN archivo de una carpeta COMPARTIDA (o de cualquier drive remoto que no
    // sea el del módulo Archivos): se baja DIRECTO al destino, por trozos.
    // Antes se pedía a `fetchDriveBytes`, que lo trataba como si estuviera en
    // ESTE disco (`File(ruta)`): toda descarga de una carpeta compartida
    // fallaba —"El archivo ya no existe"—, vídeos incluidos. Y hacerlo por
    // trozos evita cargar un vídeo de cientos de MB en memoria.
    final single = job.items.length == 1 && !job.items.first.isFolder;
    if (single &&
        drive.isRemote &&
        drive is! DriveApiService &&
        !kIsWeb &&
        (job.targetPath != null || isAndroidPlatform)) {
      final item = job.items.first;
      final folder = job.from == null
          ? drive.path
          : job.from!.where((s) => s.isNotEmpty).toList(growable: false);
      final uri = Uri.parse(drive.absolutePathIn(folder, item));
      final temp =
          job.targetPath ??
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
              'hs-${DateTime.now().microsecondsSinceEpoch}-${job.name}';
      await downloadRemoteToFile(uri, temp, onProgress: progress);
      String? savedTo;
      if (job.targetPath == null) {
        savedTo = await saveFileToAndroidDownloads(temp, job.name);
        try {
          await File(temp).delete();
        } catch (_) {
          // El temporal se queda: no es motivo para reportar un fallo.
        }
        if (savedTo == null) throw 'No se pudo guardar en Descargas';
      }
      drive.finishDownloadJob(job);
      if (!quiet) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              savedTo == null
                  ? 'Descargado en Descargas: ${job.name} '
                        '(${(job.received / 1024).toStringAsFixed(0)} KB)'
                  : 'Descargado en $savedTo',
            ),
          ),
        );
      }
      return;
    }

    final bytes = await fetchDriveBytes(
      drive,
      job.items,
      from: job.from,
      onProgress: progress,
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
    if (!kIsWeb && !quiet) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            savedTo != null
                ? 'Descargado en $savedTo'
                : job.targetPath != null
                ? 'Descargado en Descargas: ${job.name} '
                      '(${(bytes.length / 1024).toStringAsFixed(0)} KB)'
                : 'Descargado: ${job.name} '
                      '(${(bytes.length / 1024).toStringAsFixed(0)} KB)',
          ),
        ),
      );
    }
  } catch (e) {
    drive.finishDownloadJob(job, error: '$e');
    if (!quiet) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo descargar "${job.name}": $e')),
      );
    }
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

/// Deja en la carpeta pública de DESCARGAS (Android) el archivo que YA está
/// escrito en [path] (una descarga grande se baja por trozos a un temporal en
/// vez de tenerla entera en memoria).
Future<String?> saveFileToAndroidDownloads(String path, String name) {
  return _downloadsChannel.invokeMethod<String>('save', {
    'path': path,
    'name': name,
  });
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
      final raw = await drive.downloadZip(
        [item.name],
        from: folder,
        onProgress: onProgress,
      );
      // El backend responde con un ZIP incluso para UN archivo: si se guardara
      // tal cual con la extensión de la foto, el archivo queda corrupto.
      return extractSingleFile(raw, item.name) ?? raw;
    }
    // Carpeta COMPARTIDA (u otro drive que no es el del módulo Archivos): el
    // archivo vive en el servidor del drive, no en este disco. Se pide por su
    // URL; tratarlo como un `File` local era lo que hacía fallar la descarga
    // de CUALQUIER archivo compartido (y de un vídeo, en cuanto se tocaba).
    if (drive.isRemote) {
      return remoteBytes(
        Uri.parse(drive.absolutePathIn(folder, item)),
        onProgress: onProgress,
      );
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
  if (drive.isRemote) {
    return remoteZipBytes(drive, items, folder, onProgress: onProgress);
  }
  return buildLocalZipBytes(drive as DriveService, items, rel: folder);
}

/// Bytes de un archivo REMOTO (carpeta compartida), con progreso.
Future<List<int>> remoteBytes(
  Uri uri, {
  required void Function(int received, int total) onProgress,
}) async {
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', uri));
    if (res.statusCode != 200) {
      throw 'El servidor contestó ${res.statusCode}';
    }
    final total = res.contentLength ?? 0;
    final out = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in res.stream) {
      out.add(chunk);
      received += chunk.length;
      onProgress(received, total);
    }
    return out.takeBytes();
  } finally {
    client.close();
  }
}

/// Baja un archivo REMOTO directo a [path], sin pasar por memoria.
Future<void> downloadRemoteToFile(
  Uri uri,
  String path, {
  required void Function(int received, int total) onProgress,
}) async {
  final client = http.Client();
  IOSink? sink;
  try {
    final res = await client.send(http.Request('GET', uri));
    if (res.statusCode != 200) {
      throw 'El servidor contestó ${res.statusCode}';
    }
    final total = res.contentLength ?? 0;
    sink = File(path).openWrite();
    var received = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(received, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;
  } catch (e) {
    // A medias no se deja un archivo cortado con el nombre del original (el
    // usuario creería que se descargó bien).
    await sink?.close();
    sink = null;
    try {
      final out = File(path);
      if (await out.exists()) await out.delete();
    } catch (_) {
      // Si no se puede borrar, el error que importa es el de la descarga.
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// Una entrada del ZIP de una carpeta COMPARTIDA (`bytes` null = carpeta).
class RemoteZipEntry {
  const RemoteZipEntry(this.name, this.bytes);

  final String name;
  final List<int>? bytes;
}

/// Arma el ZIP de una selección de una carpeta compartida: el servidor sirve
/// los archivos uno a uno, así que el ZIP se arma aquí (en un isolate).
Future<List<int>> remoteZipBytes(
  DriveBase drive,
  List<DriveItem> items,
  List<String> folder, {
  required void Function(int received, int total) onProgress,
}) async {
  final entries = <RemoteZipEntry>[];
  var received = 0;

  Future<void> addFile(List<String> rel, DriveItem item, String arc) async {
    final bytes = await remoteBytes(
      Uri.parse(drive.absolutePathIn(rel, item)),
      onProgress: (partial, _) => onProgress(received + partial, 0),
    );
    received += bytes.length;
    entries.add(RemoteZipEntry(arc, bytes));
  }

  Future<void> walk(List<String> rel, String prefix) async {
    final children = await drive.listFolderItems(rel);
    for (final child in children) {
      final arc = prefix.isEmpty ? child.name : '$prefix/${child.name}';
      if (child.isFolder) {
        entries.add(RemoteZipEntry('$arc/', null));
        await walk([...rel, child.name], arc);
      } else {
        await addFile(rel, child, arc);
      }
    }
  }

  for (final item in items) {
    if (item.isFolder) {
      entries.add(RemoteZipEntry('${item.name}/', null));
      await walk([...folder, item.name], item.name);
    } else {
      await addFile(folder, item, item.name);
    }
  }
  if (entries.isEmpty) throw 'La carpeta no tiene archivos para descargar';
  return compute(zipRemoteEntries, entries);
}

/// Comprime las entradas de [remoteZipBytes] (corre en un isolate).
List<int> zipRemoteEntries(List<RemoteZipEntry> entries) {
  final archive = Archive();
  for (final e in entries) {
    final name = e.name.replaceAll('\\', '/');
    final bytes = e.bytes;
    if (bytes == null) {
      archive.add(ArchiveFile.string(name, ''));
    } else {
      archive.add(ArchiveFile.bytes(name, bytes));
    }
  }
  return ZipEncoder().encode(archive);
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
    archive.add(ArchiveFile.bytes(arcName.replaceAll('\\', '/'), bytes));
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
