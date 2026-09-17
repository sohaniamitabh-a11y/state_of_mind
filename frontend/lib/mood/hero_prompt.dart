import 'dart:ui';

import 'package:flutter/material.dart';

import 'mood.dart';

/// The landing copy: oversized frosted-glass type that picks up the
/// five mood colors only while the cursor is actually over it.
///
/// Resting (no hover) the glyphs are a cool, slightly translucent
/// white so the glass reads first. On hover a ShaderMask cross-fades
/// in the same five mood colors used on the cards, which is the
/// "color essence" — not a second animation loop, just one short
/// forward/reverse of a local [AnimationController] that is idle
/// the rest of the time.
///
/// The type is intentionally huge (and the glass panel even larger)
/// so that landing on this page almost requires the cursor to cross
/// the text, which is what activates the color.
class HeroPrompt extends StatefulWidget {
  const HeroPrompt({super.key, required this.opacity});

  /// Fades out as the user scrolls the first viewport of the stack.
  /// Below a small threshold this widget stops hit-testing so the
  /// rising cards can be tapped through it.
  final double opacity;

  @override
  State<HeroPrompt> createState() => _HeroPromptState();
}

class _HeroPromptState extends State<HeroPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hover;

  @override
  void initState() {
    super.initState();
    _hover = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.opacity < 0.12,
      child: Opacity(
        opacity: widget.opacity,
        child: Center(
          child: MouseRegion(
            onEnter: (_) => _hover.forward(),
            onExit: (_) => _hover.reverse(),
            cursor: SystemMouseCursors.basic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: AnimatedBuilder(
                  animation: _hover,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(_hover.value);
                    return _GlassFrame(t: t, child: child!);
                  },
                  child: const _HeroCopy(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted panel whose border and inner wash pick up mood color as [t]
/// goes 0 → 1. The blur is a single BackdropFilter that only exists
/// while the hero is on screen (it fades out with the copy).
class _GlassFrame extends StatelessWidget {
  const _GlassFrame({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Shadow has to live *outside* the ClipRRect — clipping the panel
    // for BackdropFilter would otherwise eat the hover glow.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: kMoods[1].glowColor.withValues(alpha: 0.22 * t),
            blurRadius: 36,
            spreadRadius: -8,
          ),
          BoxShadow(
            color: kMoods[0].glowColor.withValues(alpha: 0.16 * t),
            blurRadius: 48,
            offset: const Offset(18, 10),
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                width: 1.6,
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.32),
                  Colors.white.withValues(alpha: 0.0),
                  t,
                )!,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    Colors.white.withValues(alpha: 0.14),
                    kMoods[0].gradientStart.withValues(alpha: 0.24),
                    t,
                  )!,
                  Color.lerp(
                    Colors.white.withValues(alpha: 0.08),
                    kMoods[1].gradientStart.withValues(alpha: 0.20),
                    t,
                  )!,
                  Color.lerp(
                    Colors.white.withValues(alpha: 0.12),
                    kMoods[4].gradientStart.withValues(alpha: 0.20),
                    t,
                  )!,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 44),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment(-1.0 + t * 0.35, -0.25),
                    end: const Alignment(1.0, 0.35),
                    colors: [
                      Color.lerp(
                        const Color(0xF5FFFFFF),
                        kMoods[0].gradientStart,
                        t,
                      )!,
                      Color.lerp(
                        const Color(0xE6FFFFFF),
                        kMoods[1].gradientStart,
                        t,
                      )!,
                      Color.lerp(
                        const Color(0xDEFFFFFF),
                        kMoods[2].gradientStart,
                        t,
                      )!,
                      Color.lerp(
                        const Color(0xE6FFFFFF),
                        kMoods[3].gradientStart,
                        t,
                      )!,
                      Color.lerp(
                        const Color(0xF5FFFFFF),
                        kMoods[4].gradientStart,
                        t,
                      )!,
                    ],
                  ).createShader(rect);
                },
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'How do you feel\nright now?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 96,
              fontWeight: FontWeight.w700,
              height: 1.02,
              letterSpacing: -2.0,
            ),
          ),
        ),
        SizedBox(height: 22),
        Text(
          'Scroll to explore',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
