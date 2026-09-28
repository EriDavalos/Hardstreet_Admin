import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';

import 'drive_api_service.dart';
import 'drive_base.dart';
import 'drive_service.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart';

/// Descarga la selección: 1 archivo → individual; varios o carpetas → ZIP.
/// Usa el backend si el drive es remoto; si es local, genera el ZIP en un
/// isolate. Muestra una ventana "Descargando…" mientras trabaja y guarda el
/// archivo (diálogo Guardar en nativo; descarga del navegador en web).
Future<bool> downloadDriveSelection(
  BuildContext context, {
  required DriveBase drive,
  required List<DriveItem> items,
}) async {
  final messenger = ScaffoldMessenger.of(context);  // "Descargando…" NO bloqueante: se cierra al terminar.
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DownloadingDialog(),
    ).ignore();
  }
  // Captura el messenger ANTES de los awaits (BuildContext no cruza gaps).
  final navigator = Navigator.of(context, rootNavigator: true);
  var ok = false;
  try {
    ok = await _download(context, drive: drive, items: items);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo descargar: $e')),
    );
  } finally {
    if (navigator.canPop()) navigator.pop();
  }
  if (ok) {
    messenger.showSnackBar(
      SnackBar(content: Text('Descarga completada')),
    );
  }
  return ok;
}

Future<bool> _download(
  BuildContext context, {
  required DriveBase drive,
  required List<DriveItem> items,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (items.isEmpty) return false;

  // ---------- 1 archivo → descarga individual ----------
  if (items.length == 1 && !items.first.isFolder) {
    final item = items.first;
    late List<int> bytes;
    if (drive is DriveApiService) {
      bytes = await drive.downloadZip([item.name]);
    } else {
      final src = File(drive.absolutePathOf(item));
      if (!await src.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('El archivo ya no existe')),
        );
        return false;
      }
      bytes = await src.readAsBytes();
    }
    if (kIsWeb) {
      // En web NO existe el diálogo Guardar: dispara la descarga del navegador.
      _triggerBrowserDownload(bytes, item.name);
      return true;
    }
    final location = await getSaveLocation(suggestedName: item.name);
    if (location == null) return false;
    await File(location.path).writeAsBytes(bytes);
    messenger.showSnackBar(
        SnackBar(content: Text('Descargado: ${item.name}')));
    return true;
  }

    // ---------- Varios / carpetas → ZIP ----------
    late List<int> zipBytes;
    if (drive is DriveApiService) {
      // Remoto: el backend lo empaqueta (streaming, sin cargar memoria).
      zipBytes = await drive
          .downloadZip(items.map((i) => i.name).toList());
    } else {
      // Local: ZIP en isolate.
      final d = drive as DriveService;
      final job = _ZipJob(
        root: d.root.path,
        rel: List<String>.of(d.path),
        names: items
            .map((i) => _ZipEntry(name: i.name, isFolder: i.isFolder))
            .toList(),
      );
      zipBytes = await compute(_buildZip, job);
    }
    if (zipBytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay nada que descargar')),
      );
      return false;
    }

    if (kIsWeb) {
      _triggerBrowserDownload(zipBytes,
          zipSuggestedName(drive.locationLabel));
      return true;
    }
    final location = await getSaveLocation(
      suggestedName: zipSuggestedName(drive.locationLabel),
    );
    if (location == null) return false;
    await File(location.path).writeAsBytes(zipBytes);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'ZIP descargado (${(zipBytes.length / 1024).toStringAsFixed(0)} KB)'),
      ),
    );
    return true;
}

/// En web dispara la descarga del navegador (blob + <a download>).
void _triggerBrowserDownload(List<int> bytes, String filename) {
  triggerBrowserDownload(bytes, filename);
}

/// Ventana pequeña "Descargando…" (spinner, no bloquea el resto de la UI
/// más allá del modal mismo).
class _DownloadingDialog extends StatelessWidget {
  const _DownloadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Text(
              'Descargando…',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
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
      if (e is File && kImageExtensions.contains(_extOf(name))) {
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

String _extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i).toLowerCase();
}

// ===================== Nombre sugerido =====================

String zipSuggestedName(String locationLabel) {
  final clean = locationLabel == 'Mi Drive' ? 'mi-drive' : locationLabel;
  return 'hardstreet-${clean.replaceAll(RegExp(r'[^\w-]'), '-')}.zip';
}
