import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Seamless video background that renders the blooming flower video.
///
/// Visual rules applied:
/// 1. Full-screen background is a vertical gradient blend measured from the
///    video background and darkened by 10%:
///    - Top: #05070B (10% darker than #06080C)
///    - Upper-mid: #14171F (10% darker than #161A22)
///    - Lower-mid: #252D35 (10% darker than #29323B)
///    - Bottom: #42515A (10% darker than #495A64)
/// 2. Glassmorphism effect applied over the gradient, beneath the flower.
/// 3. The video is anchored to [Alignment.bottomCenter] so the stem touches
///    the very bottom edge of the screen, creating the visual effect of
///    growing directly out of the bottom rather than floating in space.
/// 4. Sized so the bloom rests in the lower center of the screen.
/// 5. Soft edge-feathering on the top and sides for seamless blending into
///    the full-screen gradient on wide/desktop displays.
class FlowerVideoBackground extends StatefulWidget {
  final ScrollController scrollController;

  const FlowerVideoBackground({super.key, required this.scrollController});

  @override
  State<FlowerVideoBackground> createState() => _FlowerVideoBackgroundState();
}

class _FlowerVideoBackgroundState extends State<FlowerVideoBackground> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isBlooming = false;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _initController();
    
    // Listen to scroll to aggressively speed up video if the user rushes
    widget.scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_isInitialized || !_controller.value.isPlaying) return;
    
    // If the user starts scrolling down while video is playing, fast-forward it
    if (widget.scrollController.offset > 50) {
      if (_controller.value.playbackSpeed != 4.0) {
        _controller.setPlaybackSpeed(4.0);
      }
    } else {
      if (_controller.value.playbackSpeed != 1.8) {
        _controller.setPlaybackSpeed(1.8);
      }
    }

    // Toggle the scrolled state for the smooth text animation
    final isScrolledNow = widget.scrollController.offset > 50;
    if (_isScrolled != isScrolledNow) {
      setState(() {
        _isScrolled = isScrolledNow;
      });
    }
  }

  Future<void> _initController() async {
    try {
      _controller = VideoPlayerController.asset('assets/videos/flower.mp4');
      await _controller.initialize();
      
      // 1: increase speed (1.8x feels alive), and persistent (loop = false)
      await _controller.setLooping(false);
      await _controller.setVolume(0.0);
      await _controller.setPlaybackSpeed(1.8);

      _controller.addListener(() {
        final position = _controller.value.position.inMilliseconds;
        // Since we play faster, the visual bloom still happens at the 4.5s mark of the video's internal clock.
        final isBloomingNow = position >= 4500;
        if (_isBlooming != isBloomingNow) {
          setState(() {
            _isBlooming = isBloomingNow;
          });
        }
      });

      await _controller.play();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing flower video: $e');
      }
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Full-screen exact gradient background matching the video's vertical palette
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF06080C), // Top void
                Color(0xFF101720), // 20%
                Color(0xFF222C36), // 40%
                Color(0xFF354450), // 60%
                Color(0xFF4C5D6A), // 80%
                Color(0xFF647683), // Bottom slate blend
              ],
              stops: [0.0, 0.20, 0.40, 0.60, 0.80, 1.0],
            ),
          ),
        ),

        // 2. Glassmorphism effect applied OVER the gradient, behind the flower
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.03), // Frosted glass tint
            ),
          ),
        ),

        // 3. The flower video with full-height alignment and 2D soft-feathered edges
        if (_isInitialized)
          Align(
            alignment: Alignment.bottomCenter,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenH = constraints.maxHeight;
                final aspectRatio = _controller.value.aspectRatio > 0
                    ? _controller.value.aspectRatio
                    : (720 / 1280);

                // Video matches screen height so the vertical gradient coordinates align 1:1
                final targetH = screenH;
                final targetW = targetH * aspectRatio;

                return SizedBox(
                  width: targetW,
                  height: targetH,
                  child: ShaderMask(
                    // Horizontal soft feathering: melts left and right borders away completely
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Color(0x22000000),
                          Color(0x88000000),
                          Colors.black,
                          Colors.black,
                          Color(0x88000000),
                          Color(0x22000000),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.15, 0.30, 0.46, 0.54, 0.70, 0.85, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: ShaderMask(
                      // Vertical soft feathering: dissolves top edge into the dark void
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x44000000),
                            Colors.black,
                            Colors.black,
                          ],
                          stops: [0.0, 0.12, 0.28, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                );
              },
            ),
          ),

        // 3. Global 10% darkening scrim across the entire canvas
        // This darkens both the background and video by the exact same amount uniformly,
        // fulfilling the 10% darker requirement with zero seam or color mismatch.
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Color(0x1A000000), // Exactly 10% black overlay (255 * 0.10 ~ 26 = 0x1A)
            ),
          ),
        ),

        // 4. "STATE OF MIND" Overlay
        // Fades in rapidly matching the 1.8x bloom pace.
        // Once scrolled, smoothly detaches and animates to the top permanently.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              // Completely opaque (1.0) so it's fully visible and dark
              opacity: (_isBlooming || _isScrolled) ? 1.0 : 0.0, 
              duration: const Duration(milliseconds: 300), // Very fast fade to match rapid bloom
              curve: Curves.easeIn,
              child: AnimatedAlign(
                alignment: _isScrolled ? const Alignment(0.0, -0.85) : Alignment.center,
                duration: const Duration(milliseconds: 1000), // Smooth 1-second float up
                curve: Curves.easeInOutCubic,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 1000), // Matches alignment duration
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    fontFamily: 'Pinyon Script',
                    fontFamilyFallback: const ['cursive', 'serif'],
                    fontSize: _isScrolled ? 48.0 : 92.0, // Gracefully shrinks
                    letterSpacing: 1.5,
                    color: Colors.black, // Dark black text
                    fontWeight: FontWeight.normal,
                    shadows: [
                      // Subtle light glow so the dark text pops off the dark background
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.25),
                        blurRadius: 12.0,
                      ),
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.15),
                        blurRadius: 24.0,
                      ),
                    ],
                  ),
                  child: const Text(
                    'State of Mind',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
