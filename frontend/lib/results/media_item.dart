/// A single recommended title within one bucket of a [MoodResults] response.
///
/// Field names mirror the shape the real `/get-state` backend returns per
/// item (`docs/05-BACKEND.md`: `id`, `title`, `media_type`, ...) so a future
/// JSON-backed [ResultsRepository] can populate this model directly.
class MediaItem {
  const MediaItem({required this.title, required this.category});

  final String title;
  final String category;
}
