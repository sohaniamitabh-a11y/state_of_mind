import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'mood.dart';

/// One mood-picker card: a skewed gradient glow bar behind a frosted-glass
/// panel, matching the live Vercel reference's mood-select screen exactly
/// (320×240 button, 112×288 glow bar skewed -12°, 75%-height glass panel
/// with `backdrop-blur-md`).
///
/// This widget only renders the card's own visuals and hover reaction; the
/// stacking-scroll rise/pin/shrink transform is applied by the caller
/// (`MoodStackPage`) via `Transform`/`Positioned`, not here.
class MoodCard extends StatefulWidget {
  const MoodCard({super.key, required this.mood, required this.onTap});

  final Mood mood;
  final VoidCallback onTap;

  static const double width = 240;
  static const double height = 320;

  @override
  State<MoodCard> createState() => _MoodCardState();
}

class _MoodCardState extends State<MoodCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: MoodCard.width,
          height: MoodCard.height,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _GlowBar(mood: mood, hovered: _hovered),
              _GlassPanel(mood: mood, hovered: _hovered),
            ],
          ),
        ),
      ),
    );
  }
}

/// The skewed, gradient-filled glow bar behind the glass panel.
///
/// Source: `<span class="absolute h-[120%] w-28 -skew-x-12 rounded-sm
/// bg-gradient-to-b ... shadow-[0_0_60px_-15px] ...
/// group-hover:-translate-y-6 group-hover:scale-105">`.
class _GlowBar extends StatelessWidget {
  const _GlowBar({required this.mood, required this.hovered});

  final Mood mood;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    const width = 112.0; // Tailwind w-28 = 7rem
    const height = MoodCard.height * 1.2; // h-[120%] of the button

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      // Tailwind composes transforms in a fixed order (translate, skew,
      // scale) regardless of utility-class order in the markup, so the
      // matrix chain below mirrors that rather than the class list order.
      transform: Matrix4.identity()
        ..translateByDouble(
          0.0,
          hovered ? -24.0 : 0.0,
          0.0,
          1.0,
        ) // group-hover:-translate-y-6
        ..multiply(Matrix4.skewX(-12 * math.pi / 180)) // -skew-x-12
        ..scaleByDouble(
          hovered ? 1.05 : 1.0,
          hovered ? 1.05 : 1.0,
          1.0,
          1.0,
        ), // group-hover:scale-105
      transformAlignment: Alignment.center,
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2), // rounded-sm
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [mood.gradientStart, mood.gradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: mood.glowColor.withValues(alpha: 0.6),
            blurRadius: 60,
            spreadRadius: -15,
          ),
        ],
      ),
    );
  }
}

/// The frosted-glass content panel in front of the glow bar.
///
/// Source: `<span class="relative z-10 flex h-3/4 w-full flex-col
/// justify-between rounded-xl border border-white/10 bg-white/5 p-6
/// text-left backdrop-blur-md ...">`.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.mood, required this.hovered});

  final Mood mood;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12), // rounded-xl
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // backdrop-blur-md
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: MoodCard.width,
          height: MoodCard.height * 0.75, // h-3/4
          padding: const EdgeInsets.all(24), // p-6
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            color: Colors.white.withValues(alpha: hovered ? 0.10 : 0.05),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible (not a plain Column) because the fixed 240×320
              // card size — matching the live reference exactly — leaves
              // only ~190px of vertical room here once padding is
              // subtracted. CSS flexbox silently allows this content to
              // overflow its box; Flutter's Column does not, so the title
              // and description are explicitly line-capped below to fit
              // reliably instead of throwing a render overflow error.
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        mood.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.0,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                    ),
                    Text(
                      mood.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mood.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.60),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: hovered ? 1.05 : 1.0,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Select mood',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
