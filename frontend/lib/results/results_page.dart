import 'package:flutter/material.dart';

import '../mood/mood.dart';
import 'media_item.dart';
import 'mood_results.dart';
import 'results_repository.dart';
import 'static_results_repository.dart';

/// Shows the bucketed recommendations for one [Mood].
///
/// Talks only to the [ResultsRepository] interface — today that's
/// [StaticResultsRepository], but nothing in this widget assumes that.
/// Renders three honest states: loading (while the future is pending),
/// error (the future rejected), and loaded-with-possibly-empty-buckets —
/// there is no fake "always shows something" state that would hide a
/// genuine empty bucket or a genuine failure.
class ResultsPage extends StatefulWidget {
  const ResultsPage({
    super.key,
    required this.mood,
    required this.onBack,
    this.repository = const StaticResultsRepository(),
  });

  final Mood mood;

  /// Called when the user wants to return to the mood picker. Not
  /// `Navigator.pop` — this page is swapped in over the picker by
  /// `HomeShell`, not pushed as a separate route (see `main.dart` for why).
  final VoidCallback onBack;
  final ResultsRepository repository;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  late Future<MoodResults> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = widget.repository.getResults(widget.mood.name);
  }

  void _retry() {
    setState(() {
      _resultsFuture = widget.repository.getResults(widget.mood.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Change mood',
          onPressed: widget.onBack,
        ),
        title: Text(mood.title),
      ),
      body: FutureBuilder<MoodResults>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error!, onRetry: _retry);
          }
          return _ResultsBody(results: snapshot.data!);
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 40),
            const SizedBox(height: 16),
            Text(
              'Couldn\'t load recommendations.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.results});

  final MoodResults results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No recommendations yet for this mood.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _Section(title: 'Movies & TV', items: results.moviesTv),
        _Section(title: 'Music', items: results.music),
        _Section(title: 'Games', items: results.games),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'Nothing here yet.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            )
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    width: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.category,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
