// ==================================================================
// VISTA PREVIA JPEG DENTRO DE UN RAW
// ==================================================================
// Un DNG/CR2/CR3 no se puede dibujar directamente, pero casi todos llevan
// dentro una foto JPEG que la cámara usa para su pantalla. El SERVIDOR del
// drive ya la extrae; este archivo hace lo mismo en Dart para cuando el
// archivo vive en la COMPUTADORA del dueño y la miniatura la tiene que armar
// su app (agente de carpetas compartidas).
//
// Es el mismo algoritmo que `hardstreet-drive/raw-preview.js`: se recorren los
// segmentos JPEG de verdad (no basta buscar el primer FF D9, porque el EXIF
// lleva un thumbnail con su propio SOI/EOI) y se queda el JPEG más grande.
// ==================================================================
import 'dart:typed_data';

bool isRawFileName(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0) return false;
  return _rawExtensions.contains(name.substring(i).toLowerCase());
}

const Set<String> _rawExtensions = {
  '.dng',
  '.cr2',
  '.cr3',
  '.crw',
  '.nef',
  '.nrw',
  '.arw',
  '.srf',
  '.sr2',
  '.raf',
  '.rw2',
  '.orf',
  '.pef',
  '.srw',
  '.raw',
  '.rwl',
  '.dcr',
  '.kdc',
  '.3fr',
  '.erf',
  '.mef',
  '.mos',
  '.mrw',
  '.x3f',
  '.iiq',
};

/// Fin del JPEG que empieza en [start] (índice DESPUÉS del EOI), o -1.
int _jpegEnd(Uint8List b, int start) {
  var i = start + 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xD9) return i + 2;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) return -1;
    final next = i + 2 + len;
    if (next > b.length) return -1;
    if (marker == 0xDA) {
      // Datos comprimidos: hasta el próximo marcador real (ignora relleno,
      // stuffing FF 00 y reinicios D0–D7).
      var j = next;
      while (j + 1 < b.length) {
        if (b[j] == 0xFF) {
          final n = b[j + 1];
          if (n == 0x00 || n == 0xFF || (n >= 0xD0 && n <= 0xD7)) {
            j += 2;
            continue;
          }
          if (n == 0xD9) return j + 2;
          break;
        }
        j++;
      }
      i = j;
      continue;
    }
    i = next;
  }
  return -1;
}

/// El JPEG de vista previa más grande dentro de [bytes], o null.
///
/// Los candidatos de menos de 1 KB se ignoran (son iconos/miniaturas que no
/// permiten identificar la foto). Tope de 40 MB para no copiar un archivo
/// entero si un RAW guardara un JPEG gigante.
Uint8List? embeddedJpeg(Uint8List bytes) {
  if (bytes.length < 4) return null;
  int? bestStart;
  var bestSize = 0;
  var pos = 0;
  for (var found = 0; found < 200; found++) {
    // Buscar el próximo SOI (FF D8 FF).
    while (pos + 2 < bytes.length) {
      if (bytes[pos] == 0xFF &&
          bytes[pos + 1] == 0xD8 &&
          bytes[pos + 2] == 0xFF) {
        break;
      }
      pos++;
    }
    if (pos + 2 >= bytes.length) break;
    final end = _jpegEnd(bytes, pos);
    if (end > pos + 3) {
      final size = end - pos;
      if (size >= 1024 && size <= 40 * 1024 * 1024 && size > bestSize) {
        bestStart = pos;
        bestSize = size;
      }
      // Saltar el JPEG completo: sus metadatos pueden contener otro SOI/EOI.
      pos = end;
    } else {
      pos += 2;
    }
  }
  if (bestStart == null) return null;
  return Uint8List.sublistView(bytes, bestStart, bestStart + bestSize);
}
