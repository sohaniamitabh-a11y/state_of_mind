import 'media_item.dart';

/// Bucketed recommendations for one mood.
///
/// Shape matches exactly what the real backend's `/get-state?mood=<name>`
/// returns once wired up (`docs/05-BACKEND.md`): a `mood` echo plus three
/// buckets, always present even when empty. Keeping this shape now — while
/// [ResultsRepository] is backed only by static sample data — means the
/// eventual HTTP-backed implementation is a drop-in, not a rewrite.
class MoodResults {
  const MoodResults({
    required this.mood,
    required this.moviesTv,
    required this.music,
    required this.games,
  });

  final String mood;
  final List<MediaItem> moviesTv;
  final List<MediaItem> music;
  final List<MediaItem> games;

  bool get isEmpty => moviesTv.isEmpty && music.isEmpty && games.isEmpty;
}
