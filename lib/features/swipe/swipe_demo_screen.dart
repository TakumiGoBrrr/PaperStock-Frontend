import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

class SwipeDemoScreen extends StatefulWidget {
  const SwipeDemoScreen({super.key});

  @override
  State<SwipeDemoScreen> createState() => _SwipeDemoScreenState();
}

class _SwipeDemoScreenState extends State<SwipeDemoScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 1; // 1 = Left (Skip), 2 = Right (Like), 3 = Down (Bookmark), 4 = Finished
  Offset _dragOffset = Offset.zero;
  bool _animatingOff = false;

  late final AnimationController _bounceController;
  late Animation<Offset> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _resetCardPosition() {
    setState(() {
      _dragOffset = Offset.zero;
      _animatingOff = false;
    });
  }

  void _animateOffAndAdvance(Offset targetDirection, int nextStep) {
    setState(() {
      _animatingOff = true;
    });

    // Animate card flying out of screen boundaries
    _bounceAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: targetDirection * 800,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutQuad,
    ));

    _bounceController.forward(from: 0).then((_) {
      _resetCardPosition();
      setState(() {
        _currentStep = nextStep;
      });
    });
  }

  void _returnToCenter() {
    _bounceAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutBack,
    ));
    _bounceController.forward(from: 0).then((_) {
      setState(() {
        _dragOffset = Offset.zero;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Premium dark obsidian-red velvet gradient
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1E0608), // Extremely dark velvet wine
        const Color(0xFF0F0304), // Deep obsidian black
      ],
    );

    // Active color styles depending on current step
    final highlightColor = _currentStep == 1
        ? Colors.redAccent.withAlpha((0.25 * 255).round())
        : _currentStep == 2
            ? Colors.greenAccent.withAlpha((0.25 * 255).round())
            : _currentStep == 3
                ? colorScheme.primary.withAlpha((0.25 * 255).round())
                : Colors.transparent;

    final highlightBorder = _currentStep == 1
        ? Colors.redAccent
        : _currentStep == 2
            ? Colors.greenAccent
            : _currentStep == 3
                ? colorScheme.primary
                : Colors.transparent;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: _currentStep == 4
                    ? _buildSuccessView(context)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          // Header Section
                          Text(
                            'How to read on PaperStock',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Let\'s practice swiping gestures first.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Progress Tracker Bar (4 practice steps)
                          _buildStepIndicator(colorScheme),
                          const SizedBox(height: 36),

                          // The Grayed-out Interactive Card Deck Area
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                // Step Direction Label Overlay (behind card or around it)
                                _buildDirectionalLabels(colorScheme),

                                // Swipe Practice Card
                                _animatingOff
                                    ? AnimatedBuilder(
                                        animation: _bounceAnimation,
                                        builder: (context, child) {
                                          return Transform.translate(
                                            offset: _bounceAnimation.value,
                                            child: Transform.rotate(
                                              angle: _bounceAnimation.value.dx * 0.0007,
                                              child: _buildPracticeCard(),
                                            ),
                                          );
                                        },
                                      )
                                    : GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanUpdate: (details) {
                                          setState(() {
                                            _dragOffset += details.delta;
                                          });
                                        },
                                        onPanEnd: (details) {
                                          final dx = _dragOffset.dx;
                                          final dy = _dragOffset.dy;

                                          if (_currentStep == 1 && dx < -100) {
                                            // Step 1: Swipe Left (Skip)
                                            _animateOffAndAdvance(const Offset(-1, 0), 2);
                                          } else if (_currentStep == 2 && dx > 100) {
                                            // Step 2: Swipe Right (Like)
                                            _animateOffAndAdvance(const Offset(1, 0), 3);
                                          } else if (_currentStep == 3 && dy < -100) {
                                            // Step 3: Swipe Up (Bookmark)
                                            _animateOffAndAdvance(const Offset(0, -1), 4);
                                          } else {
                                            // Invalid drag - bounce back to center
                                            _returnToCenter();
                                          }
                                        },
                                        child: Transform.translate(
                                          offset: _dragOffset,
                                          child: Transform.rotate(
                                            angle: _dragOffset.dx * 0.0007,
                                            child: _buildPracticeCard(
                                              highlightColor: highlightColor,
                                              highlightBorder: highlightBorder,
                                            ),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Swipe Guide Instructions Banner
                          _buildSwipeGuideInstructions(colorScheme),
                          const SizedBox(height: 20),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final stepNum = index + 1;
        final isActive = _currentStep == stepNum;
        final isDone = _currentStep > stepNum;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: isActive ? 28 : 12,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: isActive
                ? colorScheme.primary
                : isDone
                    ? Colors.greenAccent
                    : Colors.white24,
          ),
        );
      }),
    );
  }

  Widget _buildPracticeCard({Color? highlightColor, Color? highlightBorder}) {
    final borderCol = highlightBorder ?? cardCharcoalEdge;
    final bgCol = highlightColor ?? cardCharcoalDark;

    final String textAction;
    final IconData directionIcon;
    final Color iconColor;
    final String footerText;

    if (_currentStep == 1) {
      textAction = 'To Skip';
      directionIcon = Icons.arrow_back_rounded;
      iconColor = Colors.redAccent;
      footerText = 'Swipe Left';
    } else if (_currentStep == 2) {
      textAction = 'To Like';
      directionIcon = Icons.arrow_forward_rounded;
      iconColor = Colors.greenAccent;
      footerText = 'Swipe Right';
    } else {
      textAction = 'To Bookmark';
      directionIcon = Icons.arrow_upward_rounded;
      iconColor = Theme.of(context).colorScheme.primary;
      footerText = 'Swipe Up';
    }

    return Container(
      width: 340,
      height: 465,
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderCol, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.35 * 255).round()),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.07 * 255).round()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'PRACTICE CARD',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),

          // Big Glowing Direction Arrow
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withAlpha((0.1 * 255).round()),
                border: Border.all(
                  color: iconColor.withAlpha((0.35 * 255).round()),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withAlpha((0.08 * 255).round()),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                directionIcon,
                size: 52,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Serif Text Action Name
          Text(
            textAction,
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),

          const Spacer(),

          // Instruction Footer Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: iconColor.withAlpha((0.08 * 255).round()),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withAlpha((0.2 * 255).round()),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(directionIcon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  footerText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionalLabels(ColorScheme colorScheme) {
    return Stack(
      children: [
        // Skip label (Left)
        Positioned(
          left: -40,
          child: Opacity(
            opacity: _currentStep == 1 ? 0.9 : 0.15,
            child: RotatedBox(
              quarterTurns: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha((0.15 * 255).round()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha((0.4 * 255).round())),
                ),
                child: Text(
                  '◀  DRAG LEFT TO SKIP',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.redAccent),
                ),
              ),
            ),
          ),
        ),

        // Like label (Right)
        Positioned(
          right: -40,
          child: Opacity(
            opacity: _currentStep == 2 ? 0.9 : 0.15,
            child: RotatedBox(
              quarterTurns: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withAlpha((0.15 * 255).round()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withAlpha((0.4 * 255).round())),
                ),
                child: Text(
                  'DRAG RIGHT TO LIKE  ▶',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.greenAccent),
                ),
              ),
            ),
          ),
        ),

        // Bookmark label (Top)
        Positioned(
          top: -24,
          left: 0,
          right: 0,
          child: Center(
            child: Opacity(
              opacity: _currentStep == 3 ? 0.9 : 0.15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha((0.15 * 255).round()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary.withAlpha((0.4 * 255).round())),
                ),
                child: Text(
                  '▲  DRAG UP TO BOOKMARK',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: colorScheme.primary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeGuideInstructions(ColorScheme colorScheme) {
    String stepText = '';
    IconData stepIcon = Icons.info_outline;
    Color stepColor = Colors.white;

    switch (_currentStep) {
      case 1:
        stepText = 'Try dragging the card to the LEFT to SKIP a story you don\'t like.';
        stepIcon = Icons.arrow_back_rounded;
        stepColor = Colors.redAccent;
        break;
      case 2:
        stepText = 'Excellent! Now drag the card to the RIGHT to LIKE a story and update interests.';
        stepIcon = Icons.arrow_forward_rounded;
        stepColor = Colors.greenAccent;
        break;
      case 3:
        stepText = 'Superb! Finally, drag the card UPWARDS to BOOKMARK a story to your bookshelf.';
        stepIcon = Icons.arrow_upward_rounded;
        stepColor = colorScheme.primary;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24), // Dark sleek charcoal background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stepColor.withAlpha((0.35 * 255).round())),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: stepColor.withAlpha((0.15 * 255).round()),
            child: Icon(stepIcon, color: stepColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              stepText,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Elegant Success Circle Icon
          const Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF1A3D24),
              child: Icon(Icons.check_circle_rounded, size: 50, color: Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'You\'re ready!',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You have mastered all swiping controls. Get ready to explore personalized stories tailored for you.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: () => context.go('/community-guidelines?onboarding=true'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Start Reading',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
