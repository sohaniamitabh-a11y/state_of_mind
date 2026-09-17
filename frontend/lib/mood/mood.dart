import 'package:flutter/material.dart';

/// One of the five fixed moods offered by the picker.
///
/// [name] is the backend API-contract string (e.g. `Happy/Excitement`,
/// matched against `moods.name`) documented in `docs/08-DECISIONS.md` of the
/// main repo: "the frontend offers exactly five fixed mood buttons and never
/// accepts free text... the exact strings — including the slash — are now
/// part of the contract." Nothing calls a backend yet (see
/// `results/static_results_repository.dart`), but keeping the real
/// contract string on the model now means the eventual API-backed
/// [results.ResultsRepository] implementation needs no model changes.
///
/// Colors and copy below are the exact values measured from the live
/// Vercel reference (`https://s0m-995fn02w3-cv-d11b.vercel.app`) via a
/// headless-browser inspection pass — canvas-converted computed styles,
/// not a guess at which Tailwind palette version was in use.
@immutable
class Mood {
  const Mood({
    required this.name,
    required this.category,
    required this.title,
    required this.description,
    required this.gradientStart,
    required this.gradientEnd,
    required this.glowColor,
  });

  /// Exact API-contract mood string.
  final String name;

  /// Small uppercase pill label, e.g. "High energy".
  final String category;

  /// Display title, e.g. "Happy / Excitement".
  final String title;

  final String description;

  /// Top stop of the card's glow-bar gradient.
  final Color gradientStart;

  /// Bottom stop of the card's glow-bar gradient.
  final Color gradientEnd;

  /// Color of the blurred box-shadow behind the glow bar.
  final Color glowColor;
}

/// The five moods, in the same order as the live reference.
const List<Mood> kMoods = [
  Mood(
    name: 'Happy/Excitement',
    category: 'High energy',
    title: 'Happy / Excitement',
    description: 'Uplifting, fast-paced media to keep the momentum going.',
    gradientStart: Color(0xFFFFB900), // Tailwind amber-400
    gradientEnd: Color(0xFFFF6900), // Tailwind orange-500
    glowColor: Color(0xFFFF6900), // Tailwind orange-500
  ),
  Mood(
    name: 'Calm/Serene',
    category: 'Atmospheric',
    title: 'Calm / Serene',
    description: 'Relaxing, ambient selections to slow the world down.',
    gradientStart: Color(0xFF00D3F2), // Tailwind cyan-400
    gradientEnd: Color(0xFF155DFC), // Tailwind blue-600
    glowColor: Color(0xFF2B7FFF), // Tailwind blue-500
  ),
  Mood(
    name: 'Sad/Melancholy',
    category: 'Narrative',
    title: 'Sad / Melancholy',
    description: 'Emotional, slow, and story-driven content for reflection.',
    gradientStart: Color(0xFF7C86FF), // Tailwind indigo-400
    gradientEnd: Color(0xFF7F22FE), // Tailwind violet-600
    glowColor: Color(0xFF8E52FF), // Tailwind violet-500
  ),
  Mood(
    name: 'Anger/Rage',
    category: 'Intense',
    title: 'Anger / Rage',
    description: 'Aggressive, heavy, and high-impact experiences.',
    gradientStart: Color(0xFFFB2C36), // Tailwind red-500
    gradientEnd: Color(0xFFC70036), // Tailwind rose-700
    glowColor: Color(0xFFFF2057), // Tailwind rose-500
  ),
  Mood(
    name: 'Confusion/Anxiety',
    category: 'Mind-bending',
    title: 'Confusion / Anxiety',
    description: 'Complex, thrilling media that keeps you guessing.',
    gradientStart: Color(0xFF00D492), // Tailwind emerald-400
    gradientEnd: Color(0xFF00BBA7), // Tailwind teal-500
    glowColor: Color(0xFF00BC7D), // Tailwind emerald-500
  ),
];
