import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import 'drive_service.dart';

/// Descarga la selección: 1 archivo → individual; varios o carpetas → ZIP.
/// Devuelve true si se guardó algo en disco.
Future<bool> downloadDriveSelection(
  BuildContext context, {
  required DriveService drive,
  required List<DriveItem> items,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (items.isEmpty) return false;

    // ---------- 1 archivo → descarga individual ----------
    if (items.length == 1 && !items.first.isFolder) {
      final item = items.first;
      final src = File(drive.absolutePathOf(item));
      if (!await src.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('El archivo ya no existe')),
        );
        return false;
      }
      final location = await getSaveLocation(suggestedName: item.name);
      if (location == null) return false; // cancelado por el usuario
      final bytes = await src.readAsBytes();
      await File(location.path).writeAsBytes(bytes);
      messenger.showSnackBar(SnackBar(content: Text('Descargado: ${item.name}')));
      return true;
    }

    // ---------- Varios / carpetas → ZIP en memoria ----------
    final args = _ZipJob(
      root: drive.root.path,
      rel: List<String>.of(drive.path),
      names: items
          .map((i) => _ZipEntry(name: i.name, isFolder: i.isFolder))
          .toList(),
    );
    final zipBytes = await compute(_buildZip, args);
    if (zipBytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay nada que descargar')),
      );
      return false;
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
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo descargar: $e')),
    );
    return false;
  }
}

// ===================== ZIP en isolate =====================

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
  final clean = locationLabel == 'Hardstreet' ? 'hardstreet' : locationLabel;
  return 'hardstreet-${clean.replaceAll(RegExp(r'[^\w-]'), '-')}.zip';
}
