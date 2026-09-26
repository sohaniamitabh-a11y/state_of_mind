import 'mood_results.dart';

/// Fetches bucketed recommendations for a mood.
///
/// This is the seam between the UI and wherever the data actually comes
/// from. `results_page.dart` depends only on this interface, never on a
/// concrete implementation — today that's [StaticResultsRepository]
/// (see `static_results_repository.dart`), backed by hardcoded sample data.
/// A real implementation calling the Flask backend's
/// `GET /get-state?mood=<name>` endpoint can be dropped in later by
/// implementing this same interface; nothing above this layer needs to
/// change.
abstract class ResultsRepository {
  /// Returns bucketed recommendations for [moodName], which must be one of
  /// the exact API-contract strings in `mood/mood.dart`'s `kMoods`
  /// (e.g. `Happy/Excitement`).
  ///
  /// Throws a [ResultsRepositoryException] on any failure a caller should
  /// show to the user (network error, backend down, unrecognised mood).
  Future<MoodResults> getResults(String moodName);
}

/// Base class for the honest failure modes a [ResultsRepository] can raise.
///
/// Kept as a real exception hierarchy (not a single generic error string)
/// so the UI can distinguish "nothing matched" from "couldn't even ask" —
/// a distinction that will matter once a real backend is wired up and can
/// be down, slow, or return a 404 for an unrecognised mood
/// (`docs/08-DECISIONS.md`).
sealed class ResultsRepositoryException implements Exception {
  const ResultsRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The mood string didn't match anything the repository knows about.
class MoodNotFoundException extends ResultsRepositoryException {
  const MoodNotFoundException(String moodName)
    : super('No results available for mood "$moodName".');
}
