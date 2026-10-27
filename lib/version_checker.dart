import 'dart:convert';
import 'dart:io' if (dart.library.io) 'dart:io';

import 'app_platform.dart';

/// Información de versión que publica el servidor.
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.minVersion,
    required this.notes,
    required this.downloads,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
    version: j['version']?.toString() ?? '1.0.3',
    minVersion: j['minVersion']?.toString() ?? '1.0.3',
    notes: j['notes']?.toString() ?? '',
    downloads: ((j['downloads'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    )),
  );

  final String version;
  final String minVersion; // versión MÍNIMA aceptada
  final String notes;
  final Map<String, String> downloads; // windows / android

  /// Enlace de descarga de la plataforma [platform] (`android` / `windows`),
  /// servido SIEMPRE por el servidor con el que habla la app (el HUB).
  ///
  /// El backend publica la dirección del servidor que tiene el APK/EXE. Pero
  /// la app solo habla con el HUB, así que se cambia el ORIGEN y se conserva
  /// la ruta `/downloads/<archivo>`: el hub la reenvía al servidor donde está
  /// el archivo (aunque ese no sea el primero de la lista) y sigue sirviendo
  /// cuando un nodo está apagado. Un enlace externo (otro dominio, una nube)
  /// se respeta tal cual: no se reescribe.
  String downloadUrlFor(String platform, {String? viaBase}) {
    final own = downloads[platform] ?? '';
    final chosen = own.isNotEmpty
        ? own
        : downloads.values.firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final base = (viaBase ?? '').replaceAll(RegExp(r'/+$'), '');
    if (chosen.isEmpty || base.isEmpty) return chosen;
    final link = Uri.tryParse(chosen);
    final hub = Uri.tryParse(base);
    if (link == null || hub == null || hub.host.isEmpty) return chosen;
    final at = link.path.indexOf('/downloads/');
    if (at < 0) return chosen;
    final tail = link.path.substring(at);
    final pathOfHub = hub.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: hub.scheme,
      host: hub.host,
      port: hub.hasPort ? hub.port : null,
      path: '$pathOfHub$tail',
      query: link.hasQuery ? link.query : null,
    ).toString();
  }

  /// ¿La versión [current] es más vieja que [minVersion]?
  bool isOutdated(String current) => compareVersions(current, minVersion) < 0;

  /// ¿La versión [current] es más vieja que la ÚLTIMA publicada
  /// (hay una actualización disponible, aunque no obligatoria)?
  bool hasUpdate(String current) => compareVersions(current, version) < 0;
}

/// Comparación semántica: 1.2.10 > 1.2.9 > 1.1.0
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('.')
      .map((s) => int.tryParse(s.trim().split('+').first) ?? 0)
      .toList(growable: false);
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class VersionChecker {
  VersionChecker(this.base);

  final String base;
  Future<AppVersionInfo?> check() async {
    // En web NO existe dart:io (HttpClient lanza): usa null y no molesta.
    if (kWeb) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse('$base/api/version'));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return null;
      return AppVersionInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null; // sin conexión no se bloquea la app
    }
  }
}
