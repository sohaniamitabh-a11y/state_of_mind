import 'package:flutter/material.dart';
import 'mood.dart';
import 'mood_card.dart';

/// Displays mood cards in a stack that animates in as the user scrolls.
/// Cards stack from bottom-up with 80ms stagger between each.
class MoodStack extends StatefulWidget {
  final ScrollController scrollController;
  final Function(Mood) onMoodSelected;

  const MoodStack({
    super.key,
    required this.scrollController,
    required this.onMoodSelected,
  });

  @override
  State<MoodStack> createState() => _MoodStackState();
}

class _MoodStackState extends State<MoodStack> {
  late List<double> _cardAnimationValues;

  @override
  void initState() {
    super.initState();
    _cardAnimationValues = List.filled(moods.length, 0.0);
    widget.scrollController.addListener(_updateCardAnimations);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateCardAnimations);
    super.dispose();
  }

  void _updateCardAnimations() {
    // Start revealing cards after 200px of scroll
    final scrollOffset = widget.scrollController.offset;
    final startScroll = 200.0;
    final cardRevealDistance = 100.0; // Pixels needed to fully reveal one card
    final staggerDelay = 80.0; // Pixels between card reveals (stagger effect)

    setState(() {
      for (int i = 0; i < moods.length; i++) {
        // Calculate when this card should start revealing
        final cardStartScroll = startScroll + (i * staggerDelay);

        // Clamp the animation value between 0 and 1
        final rawValue = (scrollOffset - cardStartScroll) / cardRevealDistance;
        _cardAnimationValues[i] = rawValue.clamp(0.0, 1.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.85;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(moods.length, (index) {
          final mood = moods[index];
          final animationValue = _cardAnimationValues[index];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: SizedBox(
              width: cardWidth,
              child: MoodCard(
                emoji: mood.emoji,
                name: mood.name,
                description: mood.description,
                animationValue: animationValue,
                onTap: () {
                  widget.onMoodSelected(mood);
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}