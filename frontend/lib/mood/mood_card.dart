import 'dart:ui';

import 'package:flutter/material.dart';

import 'mood.dart';

/// One mood-picker card: a frosted-glass panel with a mood-colored
/// gradient *stroke* (not a filled slab).
///
/// Earlier this matched the live Vercel reference exactly — a skewed
/// glow strip behind the glass. Those strips read as disoriented while
/// the stacking-scroll transform was moving the cards. They were
/// replaced with a 2px gradient border in the same mood colors.
///
/// The border is painted as a stroke in front of the glass, not as a
/// gradient-filled parent with a translucent child sitting on top of
/// it. The parent-fill trick looks fine when the child is opaque, but
/// with real glass the parent's gradient shows through the whole panel
/// and the card reads as a solid orange/cyan/etc. slab — which is the
/// thing we were trying to get rid of.
///
/// The stacking-scroll rise/pin/shrink transform is applied by the
/// caller (`MoodStackPage`), not here.
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
    final strokeWidth = _hovered ? 2.5 : 2.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          scale: _hovered ? 1.03 : 1.0,
          child: Container(
            width: MoodCard.width,
            height: MoodCard.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: mood.glowColor.withValues(
                    alpha: _hovered ? 0.32 : 0.16,
                  ),
                  blurRadius: _hovered ? 18 : 10,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: CustomPaint(
              foregroundPainter: _GradientBorderPainter(
                start: mood.gradientStart,
                end: mood.gradientEnd,
                radius: 16,
                strokeWidth: strokeWidth,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: ColoredBox(
                    color: Colors.white.withValues(
                      alpha: _hovered ? 0.10 : 0.055,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _CardBody(mood: mood, hovered: _hovered),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strokes a rounded-rect gradient border. Stroke-only so a translucent
/// glass child never composites against a filled gradient.
class _GradientBorderPainter extends CustomPainter {
  const _GradientBorderPainter({
    required this.start,
    required this.end,
    required this.radius,
    required this.strokeWidth,
  });

  final Color start;
  final Color end;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter old) =>
      old.start != start ||
      old.end != end ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.mood, required this.hovered});

  final Mood mood;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Flexible (not a plain Column) because the fixed 240×320 card
        // size leaves a tight vertical budget once padding is subtracted.
        // CSS flexbox silently allows this content to overflow its box;
        // Flutter's Column does not, so the title and description are
        // explicitly line-capped below to fit reliably instead of
        // throwing a render overflow error.
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
                    color: mood.gradientStart.withValues(alpha: 0.55),
                  ),
                ),
                child: Text(
                  mood.category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                    color: Colors.white.withValues(alpha: 0.80),
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
                  color: Colors.white.withValues(alpha: 0.70),
                ),
              ),
            ],
          ),
        ),
        AnimatedScale(
          duration: const Duration(milliseconds: 280),
          scale: hovered ? 1.05 : 1.0,
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
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
    );
  }
}
