// Smoke tests for the shader background + stacking mood picker.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/background/shader_background.dart';
import 'package:frontend/main.dart';
import 'package:frontend/mood/mood.dart';
import 'package:frontend/mood/mood_card.dart';
import 'package:frontend/mood/mood_stack_page.dart';
import 'package:frontend/results/results_page.dart';

double _topOf(WidgetTester tester, Finder cardFinder) {
  final positioned = tester.widget<Positioned>(
    find.ancestor(of: cardFinder, matching: find.byType(Positioned)).first,
  );
  return positioned.top!;
}

void main() {
  testWidgets('renders the shader background and the mood stack', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(ShaderBackground), findsOneWidget);
    expect(find.byType(MoodStackPage), findsOneWidget);
    expect(find.byType(MoodCard), findsNWidgets(kMoods.length));
  });

  testWidgets('all mood cards start positioned below the visible viewport', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    final viewportHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;

    for (var i = 0; i < kMoods.length; i++) {
      final top = _topOf(tester, find.byType(MoodCard).at(i));
      expect(
        top,
        greaterThanOrEqualTo(viewportHeight),
        reason: 'Mood card $i should be hidden below the fold on entry',
      );
    }
  });

  testWidgets('scrolling brings the first mood card into view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    final viewportHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    final firstCardTopBefore = _topOf(tester, find.byType(MoodCard).first);

    // Drag up, simulating the user scrolling down through the hero and
    // into the first card's rise window.
    await tester.drag(
      find.byType(MoodStackPage),
      Offset(0, -(viewportHeight * 1.5)),
    );
    await tester.pump();

    final firstCardTopAfter = _topOf(tester, find.byType(MoodCard).first);
    expect(
      firstCardTopAfter,
      lessThan(firstCardTopBefore),
      reason: 'Scrolling should raise the first card toward its pinned spot',
    );
    expect(
      firstCardTopAfter,
      lessThan(viewportHeight),
      reason: 'After enough scrolling the first card should be on screen',
    );
  });

  testWidgets(
    'selecting a mood shows results without hiding the background',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());

      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      // Scroll the first card into view, then tap it.
      await tester.drag(
        find.byType(MoodStackPage),
        Offset(0, -(viewportHeight * 2.0)),
      );
      await tester.pump();
      await tester.tap(find.byType(MoodCard).first);
      await tester.pump();
      // Let the repository's simulated delay resolve before the test ends,
      // otherwise the test framework flags the leftover timer as an error.
      await tester.pump(const Duration(milliseconds: 600));

      // Regression check: the mood → results transition must not use an
      // opaque `Navigator.push`, which would stop the background from
      // being painted at all (see `main.dart`'s `HomeShell` doc comment).
      expect(find.byType(ShaderBackground), findsOneWidget);
      expect(find.byType(ResultsPage), findsOneWidget);
      expect(find.byType(MoodStackPage), findsNothing);
    },
  );
}
