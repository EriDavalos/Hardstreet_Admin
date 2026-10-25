/// Dirección del servidor del DRIVE, editable en la app.
///
/// El panel llega al HUB por su nombre público
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
  ///
  /// Es el nombre público por **HTTPS** (sin puerto: 443). Desde ahí se sirve
  /// el hub y también las fotos públicas. El respaldo [publicHttp] existe solo
  /// para cuando el TLS falla (certificado del router, NAT loopback): apunta al
  /// MISMO nombre por HTTP en [hubPort].
  static const String compiled = String.fromEnvironment(
    'DRIVE_API',
    defaultValue: 'https://oriongo.ddns.net',
  );

  /// Base de las URLs PÚBLICAS de las fotos (`<publicBase>/files/<ruta>`).
  ///
  /// NO es la dirección con la que el panel habla con el hub: el hub escucha
  /// HTTP en [hubPort] y la web es HTTPS, así que una foto guardada como
  /// `http://…:4100/files/…` la bloquearía el navegador (contenido mixto). Los
  /// `/files` los sirve el servidor de archivos, que sí tiene TLS en el 443 del
  /// mismo nombre. Override: `--dart-define=DRIVE_PUBLIC=https://…`.
  static String get publicBase {
    const override = String.fromEnvironment('DRIVE_PUBLIC');
    if (override.isNotEmpty) return normalize(override) ?? compiled;
    final uri = Uri.tryParse(compiled);
    if (uri == null || uri.host.isEmpty) return compiled;
    final clean = compiled.replaceAll(RegExp(r'/+$'), '');
    // Ya va por HTTPS: se usa tal cual (quitar el 443 explícito es inocuo).
    if (uri.scheme == 'https') return clean;
    // Una IP/nombre de la red local no tiene HTTPS público: se deja igual.
    if (_isPrivateHost(uri.host)) return clean;
    return 'https://${uri.host}';
  }

  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan')) {
      return true;
    }
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    return a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  static String? _custom;

  /// La dirección guardada por el usuario, o `null` si no hay ninguna.
  static String? get custom => _custom;

  /// ¿Se está usando una dirección distinta a la de fábrica?
  static bool get isCustom => _custom != null;

  /// Puerto del HUB del Drive (el servicio que une los servidores).
  ///
  /// La app habla SIEMPRE con el hub: cada servidor de archivos (4000, 5050…)
  /// solo tiene que ser alcanzable DESDE el hub, no desde el teléfono. Por eso
  /// los respaldos automáticos usan este puerto: apuntar al puerto del nodo
  /// conectaba con UN servidor y las carpetas de los demás desaparecían.
  static const int hubPort = 4100;

  /// Dirección LOCAL de respaldo: la misma que documenta el módulo Conexión.
  ///
  /// Cuando el teléfono está en la red de la oficina, el nombre público
  /// responde con el certificado del router (o el NAT no devuelve la
  /// conexión) y el drive no conecta. En ese caso la app PRUEBA esta
  /// dirección y, si responde, la usa durante la sesión sin que el usuario
  /// tenga que escribirla. Al reabrir la app vuelve a intentar la pública.
  /// Es el HUB ([hubPort]), no el servidor de archivos.
  static const String lanFallback = 'http://192.168.1.72:4100';

  /// El MISMO nombre público pero por HTTP directo al puerto del HUB.
  ///
  /// El hub escucha HTTP en [hubPort] y no siempre hay un proxy con un
  /// certificado válido delante. Cuando el HTTPS falla en el teléfono
  /// (certificado del router, cadena incompleta…), esta dirección evita TLS
  /// y sigue funcionando desde internet, sin depender de la red local.
  static String get publicHttp {
    final uri = Uri.tryParse(compiled);
    if (uri == null || uri.host.isEmpty) return compiled;
    // Si la build ya apunta a HTTP, no hay nada que cambiar.
    if (uri.scheme == 'http') return compiled;
    return Uri(scheme: 'http', host: uri.host, port: hubPort).toString();
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
  static bool get usingFallback =>
      _sessionFallback != null && _sessionFallback != _custom;

  /// Activa una dirección de respaldo para el resto de la sesión.
  ///
  /// También cuando hay una dirección guardada: si la guardada no responde
  /// (por ejemplo el `https://…:4100` de antes, que el hub no entiende), la
  /// app entra igual en lugar de quedarse con la pantalla de error.
  static void useFallback([String? url]) {
    final clean = normalize(url ?? lanFallback);
    if (clean != null) _sessionFallback = clean;
  }

  /// Vuelve a la dirección pública de fábrica.
  static void clearFallback() => _sessionFallback = null;

  /// Dirección EFECTIVA del servidor del drive (lo que usan los servicios).
  ///
  /// El respaldo automático manda sobre la guardada: si la escrita no responde
  /// por red/TLS, la sesión sigue con una que sí (y Conexión lo avisa).
  static String get base => _sessionFallback ?? _custom ?? compiled;

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
    // Guardar justo el nombre y puerto de fábrica (aunque sea con `https`,
    // como quedó en instalaciones anteriores) NO la convierte en
    // «personalizada»: eso desactiva los respaldos automáticos y era una vía
    // sin salida cuando ese `https:4100` no existe.
    _custom = _isFactoryAddress(value) ? null : value;
    return true;
  }

  /// ¿[url] apunta al mismo host y puerto que la dirección de fábrica?
  static bool _isFactoryAddress(String url) {
    final value = Uri.tryParse(url);
    final factory = Uri.tryParse(compiled);
    if (value == null || factory == null) return false;
    return value.host.toLowerCase() == factory.host.toLowerCase() &&
        value.port == factory.port &&
        value.path.isEmpty;
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
