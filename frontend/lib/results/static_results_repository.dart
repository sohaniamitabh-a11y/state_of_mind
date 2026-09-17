import 'media_item.dart';
import 'mood_results.dart';
import 'results_repository.dart';

/// [ResultsRepository] backed by hardcoded sample data.
///
/// The real Flask backend's `/get-state` bucketing (Stage 5:
/// dedupe/bucket/top-5 cap) is not wired up yet — this app is currently
/// frontend-only. The sample data below stands in for it, in the exact
/// same `{mood, movies_tv, music, games}` shape, so swapping in an
/// HTTP-backed [ResultsRepository] later requires no change above this
/// file.
///
/// The `Happy/Excitement` entries below are the actual titles/categories
/// observed on the live Vercel reference
/// (`https://s0m-995fn02w3-cv-d11b.vercel.app`) during inspection. The
/// other four moods' entries are invented placeholders, not real catalog
/// data — one bucket (`Sad/Melancholy`'s games) is deliberately left empty
/// so the empty-bucket UI state is genuinely exercised rather than assumed
/// to work.
class StaticResultsRepository implements ResultsRepository {
  const StaticResultsRepository();

  @override
  Future<MoodResults> getResults(String moodName) async {
    // A small simulated delay so the loading state is genuinely exercised
    // (and visually verifiable) rather than resolving synchronously.
    await Future.delayed(const Duration(milliseconds: 500));

    final results = _sampleData[moodName];
    if (results == null) {
      throw MoodNotFoundException(moodName);
    }
    return results;
  }
}

const Map<String, MoodResults> _sampleData = {
  'Happy/Excitement': MoodResults(
    mood: 'Happy/Excitement',
    moviesTv: [
      MediaItem(title: 'Guardians of the Galaxy', category: 'Sci-Fi'),
      MediaItem(title: 'La La Land', category: 'Musical'),
    ],
    music: [
      MediaItem(title: 'Blinding Lights', category: 'Synthpop'),
      MediaItem(title: 'Uptown Funk', category: 'Funk'),
    ],
    games: [
      MediaItem(title: 'Mario Kart 8', category: 'Racing'),
      MediaItem(title: 'Fall Guys', category: 'Party'),
    ],
  ),
  'Calm/Serene': MoodResults(
    mood: 'Calm/Serene',
    moviesTv: [
      MediaItem(title: 'Spirited Away', category: 'Animation'),
      MediaItem(title: "Chef's Table", category: 'Documentary'),
    ],
    music: [
      MediaItem(title: 'Weightless', category: 'Ambient'),
      MediaItem(title: 'Clair de Lune', category: 'Classical'),
    ],
    games: [
      MediaItem(title: 'Stardew Valley', category: 'Simulation'),
      MediaItem(title: 'Journey', category: 'Adventure'),
    ],
  ),
  'Sad/Melancholy': MoodResults(
    mood: 'Sad/Melancholy',
    moviesTv: [
      MediaItem(title: 'Manchester by the Sea', category: 'Drama'),
      MediaItem(title: 'This Is Us', category: 'Drama'),
    ],
    music: [
      MediaItem(title: 'Skinny Love', category: 'Acoustic'),
      MediaItem(title: 'Someone Like You', category: 'Ballad'),
    ],
    // Deliberately empty — proves the empty-bucket UI state actually
    // renders honestly instead of being assumed to work.
    games: [],
  ),
  'Anger/Rage': MoodResults(
    mood: 'Anger/Rage',
    moviesTv: [
      MediaItem(title: 'Mad Max: Fury Road', category: 'Action'),
      MediaItem(title: 'The Boys', category: 'Action'),
    ],
    music: [
      MediaItem(title: 'Break Stuff', category: 'Nu-Metal'),
      MediaItem(title: 'Bodies', category: 'Metal'),
    ],
    games: [
      MediaItem(title: 'DOOM Eternal', category: 'Shooter'),
      MediaItem(title: 'Mortal Kombat 11', category: 'Fighting'),
    ],
  ),
  'Confusion/Anxiety': MoodResults(
    mood: 'Confusion/Anxiety',
    moviesTv: [
      MediaItem(title: 'Inception', category: 'Sci-Fi'),
      MediaItem(title: 'Dark', category: 'Mystery'),
    ],
    music: [
      MediaItem(title: 'Time', category: 'Electronic'),
      MediaItem(
        title: 'Everything In Its Right Place',
        category: 'Experimental',
      ),
    ],
    games: [
      MediaItem(title: 'Inside', category: 'Puzzle'),
      MediaItem(title: 'Portal 2', category: 'Puzzle'),
    ],
  ),
};
