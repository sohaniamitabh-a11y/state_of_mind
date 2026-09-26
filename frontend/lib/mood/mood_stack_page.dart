import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'hero_prompt.dart';
import 'mood.dart';
import 'mood_card.dart';

/// The mood picker, built as a scroll-driven "stacking cards" experience.
///
/// On entry, none of the five mood cards are visible — only the animated
/// shader background (painted behind this widget by the caller) and a
/// short scroll hint. As the user scrolls (mouse wheel, trackpad, or
/// touch-drag), the cards rise up from below one at a time, each pinning
/// in place once fully risen while the next card rises over it; already-
/// pinned cards shrink slightly as later cards arrive, producing a
/// receding, layered stack. This mirrors the "sticky card" scrollytelling
/// pattern from the pasted Lenis + Framer Motion reference component
/// (`internal/react-source-components.tsx:346-477` in the Project store),
/// re-derived for Flutter per `docs/frontend-architecture-plan.md` §1.2 —
/// with one deliberate adaptation: the reference rises all cards against
/// one shared scroll region with overlapping windows, whereas here each
/// card gets its own non-overlapping viewport-height scroll window so the
/// "hidden until scrolled" requirement holds exactly (see the scale-range
/// note on [_rangeStartFor] below for the other adaptation).
///
/// Flutter has no `position: sticky` primitive and no native scroll-linked
/// transform hook equivalent to Framer's `useScroll`/`useTransform`, so the
/// scroll offset here is a plain tracked value driven manually by
/// [Listener.onPointerSignal] (mouse wheel / trackpad) and
/// [GestureDetector.onVerticalDragUpdate] (touch drag) — not an actual
/// Flutter `Scrollable`. Card positions, scale, the hero hint's opacity,
/// and the scroll wobble are all recomputed from that one value on every
/// change — there is no extra ticker for the wobble, on purpose (see
/// [_wobbleFor]).
class MoodStackPage extends StatefulWidget {
  const MoodStackPage({super.key, required this.onMoodSelected});

  /// Called when the user taps a card's "Select mood" button, i.e. the
  /// card itself (there is no separate hit target).
  final ValueChanged<Mood> onMoodSelected;

  @override
  State<MoodStackPage> createState() => _MoodStackPageState();
}

class _MoodStackPageState extends State<MoodStackPage> {
  double _scrollOffset = 0;

  /// Vertical stagger between consecutive pinned cards, so already-pinned
  /// cards peek out slightly behind the newest one instead of perfectly
  /// overlapping (mirrors the reference's `top: calc(-5vh + i*25px)`).
  static const double _stagger = 18;

  void _applyScrollDelta(double dy, double maxOffset) {
    setState(() {
      _scrollOffset = (_scrollOffset + dy).clamp(0.0, maxOffset);
    });
  }

  /// The root-progress point (0–1, over the whole card section only) at
  /// which card [i] starts shrinking.
  ///
  /// The reference component uses `i * 0.25` for its 5 cards (i.e.
  /// `i / (len - 1)`), which makes the *last* card's range collapse to a
  /// single point (`[1, 1]`) — meaning it never visibly shrinks during
  /// normal scrolling (see `docs/frontend-architecture-plan.md` §1.2). This
  /// port uses `i / len` instead (`0, 0.2, 0.4, 0.6, 0.8` for 5 cards) so
  /// every card, including the last, has a well-defined, non-degenerate
  /// shrink range — a deliberate adaptation, not an oversight.
  static double _rangeStartFor(int index, int cardCount) =>
      index / cardCount;

  /// Tiny, GPU-composited wobble driven purely by the current scroll
  /// offset. Amplitude is ~0.7° of rotation and ~4px of horizontal
  /// translation — small enough that a dropped frame is invisible, which
  /// is the whole point of not introducing a second ticker (the shader
  /// background already owns one, isolated in its own [RepaintBoundary]).
  ///
  /// Per-card phase so the stack doesn't tilt in lockstep. Rest pose is
  /// whatever `sin(offset)` lands on, but at this amplitude that's
  /// visually a flat card.
  static ({double angle, double dx}) _wobbleFor(int index, double offset) {
    final angle =
        math.sin(offset * 0.014 + index * 0.85) * 0.012; // radians
    final dx = math.sin(offset * 0.011 + index * 0.55) * 4.0;
    return (angle: angle, dx: dx);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewportWidth = size.width;
    final viewportHeight = size.height;
    final cardCount = kMoods.length;

    // One full screen of "nothing yet" before the first card starts rising.
    final heroHeight = viewportHeight;
    final maxScrollOffset = heroHeight + cardCount * viewportHeight;

    final heroOpacity = 1.0 - (_scrollOffset / heroHeight).clamp(0.0, 1.0);
    final rootProgress =
        ((_scrollOffset - heroHeight) / (cardCount * viewportHeight)).clamp(
          0.0,
          1.0,
        );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _applyScrollDelta(event.scrollDelta.dy, maxScrollOffset);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) =>
            _applyScrollDelta(-details.delta.dy, maxScrollOffset),
        child: SizedBox(
          width: viewportWidth,
          height: viewportHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: HeroPrompt(opacity: heroOpacity),
              ),
              for (var i = 0; i < cardCount; i++)
                _buildCard(
                  index: i,
                  cardCount: cardCount,
                  heroHeight: heroHeight,
                  viewportWidth: viewportWidth,
                  viewportHeight: viewportHeight,
                  rootProgress: rootProgress,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required int index,
    required int cardCount,
    required double heroHeight,
    required double viewportWidth,
    required double viewportHeight,
    required double rootProgress,
  }) {
    final mood = kMoods[index];

    // This card's own rise window: hidden below the fold until the scroll
    // offset reaches its slot, then rises to pinned over one viewport
    // height's worth of scrolling.
    final windowStart = heroHeight + index * viewportHeight;
    final localProgress = ((_scrollOffset - windowStart) / viewportHeight)
        .clamp(0.0, 1.0);

    final targetScale = 1 - (cardCount - index) * 0.05;
    final rangeStart = _rangeStartFor(index, cardCount);
    final scaleProgress = ((rootProgress - rangeStart) / (1 - rangeStart))
        .clamp(0.0, 1.0);
    final scale = lerpDouble(1.0, targetScale, scaleProgress)!;

    final pinnedTop =
        (viewportHeight - MoodCard.height) / 2 + index * _stagger;
    final enterTop = viewportHeight + 40; // fully below the visible area
    final top = lerpDouble(enterTop, pinnedTop, localProgress)!;
    final left = (viewportWidth - MoodCard.width) / 2;
    final wobble = _wobbleFor(index, _scrollOffset);

    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter, // CSS `origin-top` equivalent
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(wobble.dx, 0.0, 0.0, 1.0)
            ..rotateZ(wobble.angle),
          child: MoodCard(
            mood: mood,
            onTap: () => widget.onMoodSelected(mood),
          ),
        ),
      ),
    );
  }
}
