import 'package:flutter/material.dart';

import 'background/shader_background.dart';
import 'mood/mood.dart';
import 'mood/mood_stack_page.dart';
import 'results/results_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'State of Mind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeShell(),
    );
  }
}

/// Owns the single piece of navigation state this app has (which mood, if
/// any, is selected) and keeps [ShaderBackground] mounted and visible the
/// whole time.
///
/// Deliberately *not* using `Navigator.push` for the mood → results
/// transition: `MaterialPageRoute` is opaque by default, and an opaque
/// route stops the framework from rendering anything behind it — including
/// this app's only background, [ShaderBackground] — which was tried first
/// and produced a blank white screen once on the results page. Swapping
/// the foreground content in place, with the background as a permanent
/// sibling layer, avoids that entirely.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Mood? _selectedMood;

  @override
  Widget build(BuildContext context) {
    final selectedMood = _selectedMood;

    return Scaffold(
      body: Stack(
        children: [
          // Isolated in its own RepaintBoundary: this layer repaints
          // every frame regardless of anything else on screen, and
          // shouldn't force the foreground layer above it to repaint.
          const RepaintBoundary(child: ShaderBackground()),
          // Isolated in its own RepaintBoundary: this layer only repaints
          // in reaction to user input (scrolling the mood stack, loading
          // results), and shouldn't force the continuously-animating
          // shader below it to redo any extra work.
          RepaintBoundary(
            child: selectedMood == null
                ? MoodStackPage(
                    onMoodSelected: (mood) =>
                        setState(() => _selectedMood = mood),
                  )
                : ResultsPage(
                    mood: selectedMood,
                    onBack: () => setState(() => _selectedMood = null),
                  ),
          ),
        ],
      ),
    );
  }
}
