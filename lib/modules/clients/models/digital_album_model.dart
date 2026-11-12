/// Álbum digital de un cliente: una carpeta del Drive + una temática.
///
/// El cliente abre [url] (`/album/<liga>`) y ve las fotos y vídeos que haya en
/// la carpeta, sin cuenta. Al subir archivos al Drive aparecen solos.
class DigitalAlbum {
  const DigitalAlbum({
    this.id = 0,
    this.userId = 0,
    this.title = '',
    this.theme = 'boda',
    this.folder = '',
    this.eventDate = '',
    this.slug = '',
    this.url = '',
    this.published = false,
  });

  final int id;
  final int userId;
  final String title;

  /// `boda`, `xv` o `clasico`.
  final String theme;

  /// Ruta de la carpeta dentro del Drive.
  final String folder;
  final String eventDate;
  final String slug;

  /// Liga pública (`https://sitio/album/<slug>`), tal como la manda la API.
  final String url;
  final bool published;

  bool get isNew => id <= 0;

  factory DigitalAlbum.fromJson(Map<String, dynamic> json) {
    return DigitalAlbum(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      theme: (json['theme'] ?? 'boda').toString(),
      folder: (json['folder'] ?? '').toString(),
      eventDate: (json['eventDate'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      published: json['published'] == true,
    );
  }

  DigitalAlbum copyWith({
    String? title,
    String? theme,
    String? folder,
    String? eventDate,
    bool? published,
  }) {
    return DigitalAlbum(
      id: id,
      userId: userId,
      title: title ?? this.title,
      theme: theme ?? this.theme,
      folder: folder ?? this.folder,
      eventDate: eventDate ?? this.eventDate,
      slug: slug,
      url: url,
      published: published ?? this.published,
    );
  }
}

/// Temáticas disponibles: clave de la API + nombre visible + descripción.
const List<({String key, String label, String hint})> kAlbumThemes = [
  (key: 'boda', label: 'Boda', hint: 'Marfil, oro y tipografía clásica'),
  (key: 'xv', label: 'XV años', hint: 'Rosa suave y aire de celebración'),
  (
    key: 'clasico',
    label: 'Clásico',
    hint: 'Neutro y elegante, para cualquier evento',
  ),
];

String albumThemeLabel(String key) {
  for (final t in kAlbumThemes) {
    if (t.key == key) return t.label;
  }
  return 'Boda';
}
