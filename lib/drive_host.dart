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

  /// Dirección EFECTIVA del servidor del drive (lo que usan los servicios).
  static String get base => _custom ?? compiled;

  /// Guarda (o borra, con `null`/vacío) la dirección del servidor.
  /// Devuelve `true` si quedó aplicada; `false` si lo escrito no es válido.
  static bool set(String? raw) {
    final text = (raw ?? '').trim();
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
