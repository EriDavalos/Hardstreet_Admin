/// Dirección del servidor del DRIVE, editable en la app.
///
/// El panel llega al servidor por su nombre público
/// ([compiled] = `https://oriongo.ddns.net`, o el que se pase con
/// `--dart-define=DRIVE_API=…`). Ese nombre funciona desde internet, pero
/// DENTRO de la red de la oficina no siempre: el router no devuelve las
/// conexiones a su propia IP pública (NAT loopback) y contesta él con su
/// certificado autofirmado, así que el celular falla con
/// `CERTIFICATE_VERIFY_FAILED`.
///
/// Por eso la dirección es AJUSTABLE en [AppSettings] y vive aquí: en la red de
/// la casa/oficina se escribe la del servidor (`http://192.168.1.72:4000`) y
/// el panel entra directo, sin pasar por el router. Sin valor guardado se usa
/// la de siempre, así las instalaciones que ya funcionan no cambian.
class DriveHost {
  DriveHost._();

  /// La dirección de fábrica (la que trae la build).
  static const String compiled = String.fromEnvironment(
    'DRIVE_API',
    defaultValue: 'https://oriongo.ddns.net',
  );

  static String? _custom;

  /// La dirección guardada por el usuario, o `null` si no hay ninguna.
  static String? get custom => _custom;

  /// ¿Se está usando una dirección distinta a la de fábrica?
  static bool get isCustom => _custom != null;

  /// Dirección LOCAL de respaldo: la misma que documenta el módulo Conexión.
  ///
  /// Cuando el teléfono está en la red de la oficina, el nombre público
  /// responde con el certificado del router (o el NAT no devuelve la
  /// conexión) y el drive no conecta. En ese caso la app PRUEBA esta
  /// dirección y, si responde, la usa durante la sesión sin que el usuario
  /// tenga que escribirla. Al reabrir la app vuelve a intentar la pública.
  static const String lanFallback = 'http://192.168.1.72:4000';

  /// El MISMO nombre público pero por HTTP directo al puerto del drive.
  ///
  /// El servidor del Drive escucha HTTP en 4000 y no siempre hay un proxy
  /// con un certificado válido delante. Cuando el HTTPS falla en el teléfono
  /// (certificado del router, cadena incompleta…), esta dirección evita TLS
  /// y sigue funcionando desde internet, sin depender de la red local.
  static String get publicHttp {
    final uri = Uri.tryParse(compiled);
    if (uri == null || uri.host.isEmpty) return compiled;
    // Si la build ya apunta a HTTP, no hay nada que cambiar.
    if (uri.scheme == 'http') return compiled;
    return Uri(scheme: 'http', host: uri.host, port: 4000).toString();
  }

  /// Direcciones que se prueban, EN ORDEN, cuando la configurada no responde.
  ///
  /// 1. el nombre público por HTTP (sirve dentro y fuera de la oficina),
  /// 2. la IP local (sirve si el router no devuelve la conexión a su propia
  ///    IP pública).
  /// Se quitan duplicados y la que ya se está usando.
  static List<String> get fallbackCandidates {
    final out = <String>[];
    for (final candidate in [publicHttp, lanFallback]) {
      if (candidate == base || out.contains(candidate)) continue;
      out.add(candidate);
    }
    return out;
  }

  /// Dirección que se activó automáticamente en esta sesión.
  static String? _sessionFallback;

  /// true = se está usando una dirección de respaldo.
  static bool get usingFallback => _custom == null && _sessionFallback != null;

  /// Activa una dirección de respaldo para el resto de la sesión.
  static void useFallback([String? url]) {
    if (_custom != null) return;
    final clean = normalize(url ?? lanFallback);
    if (clean != null) _sessionFallback = clean;
  }

  /// Vuelve a la dirección pública de fábrica.
  static void clearFallback() => _sessionFallback = null;

  /// Dirección EFECTIVA del servidor del drive (lo que usan los servicios).
  static String get base => _custom ?? _sessionFallback ?? compiled;

  /// Guarda (o borra, con `null`/vacío) la dirección del servidor.
  /// Devuelve `true` si quedó aplicada; `false` si lo escrito no es válido.
  static bool set(String? raw) {
    final text = (raw ?? '').trim();
    // Elegir una dirección a mano desactiva el respaldo automático.
    _sessionFallback = null;
    if (text.isEmpty) {
      _custom = null;
      return true;
    }
    final value = normalize(text);
    if (value == null) return false;
    _custom = value;
    return true;
  }

  /// Deja la dirección como una URL usable: agrega `http://` si falta, quita
  /// las barras del final y descarta lo que no sea http/https.
  /// Devuelve `null` si no hay host.
  static String? normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return null;
    if (!v.contains('://')) v = 'http://$v';
    v = v.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return v;
  }

  /// ¿Lo escrito sirve como dirección? (Vacío = usar la de fábrica.)
  static bool isValid(String? raw) {
    final text = (raw ?? '').trim();
    return text.isEmpty || normalize(text) != null;
  }
}
