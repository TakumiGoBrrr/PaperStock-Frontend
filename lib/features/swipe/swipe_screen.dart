import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/card_brightness_provider.dart';
import '../../core/widgets/nsfw_blur_overlay.dart';
import '../feed/models/post.dart';
import 'story_ad_screen.dart';
import 'swipe_controller.dart';

// ─── Thresholds ───────────────────────────────────────────────────────────────

const _kUpThresholdFraction = 0.20; // fraction of screen height for "save"
const _kFlingVelocity = 550.0; // px/s shortcut
const _kCardBorderRadius = 24.0;

// ─── Public: embeddable card-deck widget ──────────────────────────────────────

final showSwipeTutorialProvider = StateProvider<bool>((ref) => false);

/// Drop-in widget — no Scaffold/AppBar. Embed directly into a tab.
class SwipeDeckContent extends ConsumerWidget {
  const SwipeDeckContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(swipeDeckControllerProvider);
    final showTutorial = ref.watch(showSwipeTutorialProvider);

    return async.when(
      loading: () => const _DeckSkeleton(),
      error: (err, _) => _DeckErrorView(
        message: _friendlyDioError(err),
        onRetry: () => ref.invalidate(swipeDeckControllerProvider),
      ),
      data: (state) {
        if (state.isEmpty) return const _DeckEmptyView();

        final swipeBody = _SwipeBody(state: state);
        if (showTutorial) {
          return Column(
            children: [
              const _SwipeTutorialBanner(),
              Expanded(child: swipeBody),
            ],
          );
        }
        return swipeBody;
      },
    );
  }
}

// Converts a raw DioException / Exception into a readable one-liner.
String _friendlyDioError(Object err) {
  final s = err.toString();
  if (s.contains('SocketException') ||
      s.contains('connection') ||
      s.contains('Connection')) {
    return 'No internet connection.\nCheck your network and try again.';
  }
  if (s.contains('401') || s.contains('403')) {
    return 'Session expired. Please log in again.';
  }
  if (s.contains('500') || s.contains('502') || s.contains('503')) {
    return 'Server error. Try again in a moment.';
  }
  return 'Something went wrong. Please try again.';
}

class SwipeUndoButton extends ConsumerWidget {
  const SwipeUndoButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final canUndo = ref.watch(
      swipeDeckControllerProvider
          .select((v) => v.valueOrNull?.lastSwiped != null),
    );
    return IconButton(
      icon: Icon(
        Icons.undo_rounded,
        color: canUndo
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
      ),
      onPressed: canUndo
          ? () => ref.read(swipeDeckControllerProvider.notifier).undo()
          : null,
      tooltip: 'Undo',
    );
  }
}

// ─── Core swipe body ──────────────────────────────────────────────────────────

class _SwipeBody extends ConsumerStatefulWidget {
  const _SwipeBody({required this.state});
  final SwipeDeckState state;

  @override
  ConsumerState<_SwipeBody> createState() => _SwipeBodyState();
}

class _SwipeBodyState extends ConsumerState<_SwipeBody>
    with TickerProviderStateMixin {
  // ── Drag ──────────────────────────────────────────────────────────────────
  double _dragY = 0;
  double _dragX = 0;
  Axis? _dragAxis;
  bool _isSnappingBack = false;

  // ── Transition animation ──────────────────────────────────────────────────
  late final AnimationController _ctrl;
  late Animation<double> _exitYAnim; // Y of outgoing card
  late Animation<double> _exitXAnim; // X of outgoing card
  late Animation<double> _enterYAnim; // Y of incoming card (height → 0)

  bool _isTransitioning = false;
  Post? _outgoingCard;
  String _exitApiDirection =
      'left'; // 'left' = skip/next, 'up' = bookmark, 'right' = like

  late final AnimationController _snapBackCtrl;
  late Animation<Offset> _snapBackAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 310),
    )..addStatusListener(_onTransitionEnd);

    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        setState(() {});
      });

    _snapBackAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onTransitionEnd)
      ..dispose();
    _snapBackCtrl.dispose();
    super.dispose();
  }

  void _snapCardBack({required double startX, required double startY}) {
    setState(() {
      _isSnappingBack = true;
    });

    _snapBackAnim = Tween<Offset>(
      begin: Offset(startX, startY),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _snapBackCtrl,
      curve: Curves.easeOutBack,
    ));

    _snapBackCtrl.forward(from: 0).then((_) {
      setState(() {
        _dragX = 0;
        _dragY = 0;
        _dragAxis = null;
        _isSnappingBack = false;
      });
    });
  }

  void _onTransitionEnd(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_outgoingCard != null) {
      if (_exitApiDirection == 'sequel') {
        ref
            .read(swipeDeckControllerProvider.notifier)
            .replaceTopCardWithSequel(_outgoingCard!.nextPostId!);
      } else {
        ref.read(swipeDeckControllerProvider.notifier).swipe(
              storyId: _outgoingCard!.id,
              direction: _exitApiDirection,
            );
      }
    }
    setState(() {
      _isTransitioning = false;
      _dragY = 0;
      _dragX = 0;
      _dragAxis = null;
      _outgoingCard = null;
    });
    _ctrl.reset();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isTransitioning) return;
    setState(() {
      if (_dragAxis == null) {
        if (d.delta.dx.abs() > d.delta.dy.abs()) {
          _dragAxis = Axis.horizontal;
        } else if (d.delta.dy.abs() > d.delta.dx.abs()) {
          _dragAxis = Axis.vertical;
        }
      }

      if (_dragAxis == Axis.horizontal) {
        _dragX += d.delta.dx;
      } else if (_dragAxis == Axis.vertical) {
        _dragY = (_dragY + d.delta.dy).clamp(-double.infinity, 0.0);
      }
    });
  }

  void _onPanEnd(DragEndDetails d, Size screen, Post topCard) {
    if (_isTransitioning) return;
    final vy = d.velocity.pixelsPerSecond.dy;
    final vx = d.velocity.pixelsPerSecond.dx;
    final upThreshold = screen.height * _kUpThresholdFraction;
    final horizontalThreshold = screen.width * 0.25;

    if (_dragAxis == Axis.horizontal) {
      final isFlingLeft = vx < -_kFlingVelocity && _dragX < 0;
      final isFlingRight = vx > _kFlingVelocity && _dragX > 0;
      final isDragLeft = _dragX < -horizontalThreshold;
      final isDragRight = _dragX > horizontalThreshold;

      if (isDragLeft || isFlingLeft) {
        _startTransition(
            card: topCard, apiDir: 'left', screen: screen, dragDir: 'left');
      } else if (isDragRight || isFlingRight) {
        _startTransition(
            card: topCard, apiDir: 'right', screen: screen, dragDir: 'right');
      } else {
        _snapCardBack(startX: _dragX, startY: _dragY);
      }
    } else if (_dragAxis == Axis.vertical) {
      final isFlingUp = vy < -_kFlingVelocity && _dragY < 0;
      final isDragUp = _dragY < -upThreshold;

      if (isDragUp || isFlingUp) {
        _startTransition(
            card: topCard, apiDir: 'up', screen: screen, dragDir: 'up');
      } else {
        _snapCardBack(startX: _dragX, startY: _dragY);
      }
    } else {
      _snapCardBack(startX: _dragX, startY: _dragY);
    }
  }

  void _startTransition({
    required Post card,
    required String apiDir,
    required Size screen,
    String dragDir = 'up',
  }) {
    _outgoingCard = card;
    _exitApiDirection = apiDir;

    double endX = _dragX;
    double endY = _dragY;

    if (dragDir == 'left') {
      endX = -screen.width * 1.5;
    } else if (dragDir == 'right') {
      endX = screen.width * 1.5;
    } else if (dragDir == 'up') {
      endY = -screen.height * 1.35;
    } else if (dragDir == 'down') {
      endY = screen.height * 1.35;
    }

    _exitYAnim = Tween<double>(begin: _dragY, end: endY)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInCubic));

    _exitXAnim = Tween<double>(begin: _dragX, end: endX)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInCubic));

    _enterYAnim = Tween<double>(begin: screen.height * 0.75, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    setState(() => _isTransitioning = true);
    _ctrl.forward(from: 0);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  _DragDir get _dragDir {
    if (_dragAxis == Axis.horizontal) {
      if (_dragX < -16) return _DragDir.left;
      if (_dragX > 16) return _DragDir.right;
    } else if (_dragAxis == Axis.vertical) {
      if (_dragY < -16) return _DragDir.up;
    }
    return _DragDir.none;
  }

  double get _dragLabelOpacity {
    final maxDrag = _dragX.abs() > _dragY.abs() ? _dragX.abs() : _dragY.abs();
    return (maxDrag / 80).clamp(0.0, 1.0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final deck = widget.state.deck;
    if (deck.isEmpty) return const _DeckEmptyView();

    final topCard = deck[0];
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    // Check screen width to determine if the bottom navigation bar is visible.
    // This matches feed_screen.dart where: isDesktop = width > 1024.
    final isDesktop = screen.width > 1024;

    // If desktop, the bottom navigation bar is hidden (0 height).
    // If mobile/tablet, the bottom navigation bar height is 44 + bottomSafe.
    final bottomBarHeight = isDesktop ? 0.0 : (44.0 + bottomSafe);

    // Lowered the card deck visually, leaving more breathing room under the thinned title bar
    // while keeping the card beautifully tall and seated right above the bottom bar.
    final topPadding = isDesktop ? 32.0 : 28.0;
    final bottomPadding = (isDesktop ? 8.0 : 4.0) + bottomBarHeight;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
          child: _isTransitioning
              ? _buildTransition(screen, deck, topCard)
              : _buildIdle(screen, topCard),
        ),
      ],
    );
  }

  Widget _buildIdle(Size screen, Post topCard) {
    final offset =
        _isSnappingBack ? _snapBackAnim.value : Offset(_dragX, _dragY);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _isSnappingBack ? null : _onPanUpdate,
      onPanEnd: _isSnappingBack ? null : (d) => _onPanEnd(d, screen, topCard),
      onTap: _isSnappingBack
          ? null
          : () async {
              if (topCard.isAd) {
                _openAd(context, ref, topCard);
              } else {
                context.push(
                  '/post/${topCard.id}',
                  extra: <String, String>{
                    'authorId': topCard.authorId,
                    'authorName': topCard.authorName,
                  },
                );
              }
            },
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: offset.dx *
              0.0015, // Clockwise on right swipe, anti-clockwise on left
          child: Stack(
            children: <Widget>[
              _StoryCard(post: topCard),
              // Drag label overlay
              if (!_isSnappingBack && _dragLabelOpacity > 0)
                Positioned.fill(
                  child: _DragLabel(
                    dir: _dragDir,
                    opacity: _dragLabelOpacity,
                    hasSequel: topCard.nextPostId != null &&
                        topCard.nextPostId!.isNotEmpty,
                    isAd: topCard.isAd,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransition(Size screen, List<Post> deck, Post topCard) {
    final nextCard = deck.length > 1 ? deck[1] : null;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Stack(
          children: <Widget>[
            // Incoming card rises from below
            if (nextCard != null)
              Transform.translate(
                offset: Offset(0, _enterYAnim.value),
                child: Opacity(
                  opacity: _ctrl.value.clamp(0.0, 1.0),
                  child: _StoryCard(post: nextCard),
                ),
              ),
            // Outgoing card exits
            Transform.translate(
              offset: Offset(_exitXAnim.value, _exitYAnim.value),
              child: Transform.rotate(
                angle: _exitXAnim.value * 0.0015,
                child: Stack(
                  children: <Widget>[
                    _StoryCard(post: topCard),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Story Card ───────────────────────────────────────────────────────────────

/// Opens an ad based on its type:
///  - "story"  → an in-app reader showing the full story with a "Learn more" CTA
///  - "banner" → opens the target URL directly (also records a click)
/// In both cases an impression is recorded.
void _openAd(BuildContext context, WidgetRef ref, Post ad) {
  final realAdId = ad.id.split('_').first;
  final repo = ref.read(swipeRepositoryProvider);
  repo.recordAdImpression(realAdId);

  if (ad.adType == 'story') {
    context.push(
      '/sponsored-story',
      extra: StoryAdArgs(
        adId: realAdId,
        title: ad.title,
        body: ad.body,
        targetUrl: ad.adTargetUrl,
        onLearnMore: (id) => repo.recordAdClick(id),
      ),
    );
    return;
  }

  // Banner ad: open the link directly.
  if (ad.adTargetUrl != null && ad.adTargetUrl!.isNotEmpty) {
    repo.recordAdClick(realAdId);
    () async {
      try {
        await launchUrl(
          Uri.parse(ad.adTargetUrl!),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }();
  }
}

class _StoryCard extends ConsumerWidget {
  const _StoryCard({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    // ── Warm-charcoal card palette (independent of global theme) ──────────
    final cardBg = isDark ? cardCharcoalDark : cardCreamLight;
    final cardBorder = isDark ? cardCharcoalEdge : cardCreamEdge;
    final cardText = isDark ? cardCharcoalText : cardCreamText;
    final cardSub = isDark ? cardCharcoalSubtext : cardCreamSubtext;
    final cardAccent = isDark ? cardCharcoalAccent : cardCreamAccent;
    final cardMid = isDark ? cardCharcoalMid : cardCreamMid;

    return NsfwBlurOverlay(
      isNsfw: post.isNsfw,
      borderRadius: BorderRadius.circular(_kCardBorderRadius),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(_kCardBorderRadius),
          border: Border.all(color: cardBorder, width: 0.8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: post.isAd
                        ? () => _openAd(context, ref, post)
                        : () {
                            if (post.authorId.trim().isNotEmpty) {
                              context.push('/profile/${post.authorId}');
                            }
                          },
                    child: Row(
                      children: <Widget>[
                        // Author avatar
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cardAccent.withValues(alpha: 0.16),
                          ),
                          alignment: Alignment.center,
                          child: post.isAd
                              ? Icon(
                                  Icons.campaign_outlined,
                                  size: 16,
                                  color: cardAccent,
                                )
                              : Text(
                                  post.authorName.isNotEmpty
                                      ? post.authorName[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: cardAccent,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            post.isAd
                                ? 'Sponsored'
                                : (post.authorName.isNotEmpty
                                    ? post.authorName
                                    : 'Unknown'),
                            style: GoogleFonts.inter(
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cardSub,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardMid,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    post.isAd ? 'AD' : '${post.readTimeMinutes} min',
                    style: GoogleFonts.inter(
                      textStyle: theme.textTheme.labelSmall?.copyWith(
                        color: cardSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (!post.isAd) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.flag_outlined,
                      size: 16,
                      color: cardSub.withValues(alpha: 0.5),
                    ),
                    onPressed: () => _showReportDialog(context, ref, post),
                    tooltip: 'Report Story',
                  ),
                ],
              ],
            ),
          ),

          // ── Sequel / Series Indicator Badge ────────────────────────────────
          if (!post.isAd && ((post.parentId != null && post.parentId!.isNotEmpty) ||
              (post.nextPostId != null && post.nextPostId!.isNotEmpty))) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cardAccent.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cardAccent.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          post.parentId != null && post.parentId!.isNotEmpty
                              ? Icons.link_rounded
                              : Icons.auto_stories_rounded,
                          size: 13,
                          color: cardAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          post.parentId != null && post.parentId!.isNotEmpty
                              ? 'SEQUEL OF A STORY'
                              : 'FIRST OF A SEQUEL STORY',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: cardAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const SizedBox(height: 20),
          ],

          // ── Title ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              post.title,
              style: GoogleFonts.lora(
                textStyle: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                  color: cardText,
                ),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 14),

          // Thin divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: cardBorder.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 14),

          // ── Body preview (scrolls within card) ───────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                post.body,
                style: GoogleFonts.inter(
                  textStyle: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.65,
                    color: cardSub,
                  ),
                ),
                overflow: TextOverflow.fade,
              ),
            ),
          ),

          // ── Tags ─────────────────────────────────────────────────────────
          if (!post.isAd && post.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TagRow(tags: post.tags, accent: cardAccent, bg: cardMid),
            ),
          ],

          // ── Tap-to-read hint ─────────────────────────────────────────────
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  cardBg.withValues(alpha: 0),
                  cardBg,
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  post.isAd
                      ? (post.adType == 'story'
                          ? Icons.menu_book_outlined
                          : Icons.open_in_new_rounded)
                      : Icons.touch_app_outlined,
                  size: 13,
                  color: cardSub.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 5),
                Text(
                  post.isAd
                      ? (post.adType == 'story'
                          ? 'Tap to read · swipe up to open link'
                          : 'Tap or swipe up to open website')
                      : 'Tap to read full story',
                  style: GoogleFonts.inter(
                    textStyle: theme.textTheme.labelSmall?.copyWith(
                      color: cardSub.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Tags ─────────────────────────────────────────────────────────────────────

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tags,
    required this.accent,
    required this.bg,
  });
  final List<String> tags;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .take(4)
          .map((tag) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.inter(
                    textStyle: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ))
          .toList(growable: false),
    );
  }
}

// ─── Drag direction label ─────────────────────────────────────────────────────

enum _DragDir { up, left, right, none }

class _DragLabel extends StatelessWidget {
  const _DragLabel({
    required this.dir,
    required this.opacity,
    required this.hasSequel,
    this.isAd = false,
  });
  final _DragDir dir;
  final double opacity;
  final bool hasSequel;
  final bool isAd;

  @override
  Widget build(BuildContext context) {
    if (dir == _DragDir.none) return const SizedBox.shrink();

    final IconData icon;
    final String text;
    final Alignment align;

    if (dir == _DragDir.up) {
      icon = isAd ? Icons.open_in_new_rounded : Icons.bookmark_rounded;
      text = isAd ? 'LEARN MORE' : 'BOOKMARK';
      align = Alignment.bottomCenter;
    } else if (dir == _DragDir.right) {
      icon = isAd ? Icons.close_rounded : Icons.favorite_rounded;
      text = isAd ? 'SKIP' : 'LIKE';
      align = Alignment.centerLeft;
    } else {
      icon = Icons.close_rounded;
      text = 'SKIP';
      align = Alignment.centerRight;
    }

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 7),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardBorderRadius),
          gradient: LinearGradient(
            begin: align,
            end: Alignment.center,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: content,
          ),
        ),
      ),
    );
  }
}

// (Save badge removed to allow instantaneous swipe transitions)

// ─── Empty / Loading / Error ──────────────────────────────────────────────────

class _DeckEmptyView extends ConsumerWidget {
  const _DeckEmptyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded,
                size: 68, color: colorScheme.primary.withValues(alpha: 0.38)),
            const SizedBox(height: 22),
            Text(
              "You're all caught up!",
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'New stories are on their way.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(_kCardBorderRadius),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: colorScheme.primary.withValues(alpha: 0.45),
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}

class _DeckErrorView extends StatelessWidget {
  const _DeckErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Could not load stories',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: colorScheme.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeTutorialBanner extends ConsumerWidget {
  const _SwipeTutorialBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.20),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'How to use PaperStock',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.close_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    size: 16),
                onPressed: () =>
                    ref.read(showSwipeTutorialProvider.notifier).state = false,
                tooltip: 'Dismiss',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TutorialItem(
            icon: Icons.arrow_forward_rounded,
            color: Colors.green,
            text:
                'Swipe RIGHT to LIKE a story and add its tags to your interests.',
          ),
          const SizedBox(height: 6),
          _TutorialItem(
            icon: Icons.arrow_back_rounded,
            color: Colors.redAccent,
            text: 'Swipe LEFT to SKIP a story and penalize disliked topics.',
          ),
          const SizedBox(height: 6),
          _TutorialItem(
            icon: Icons.arrow_upward_rounded,
            color: Colors.purpleAccent,
            text:
                'Swipe UP to BOOKMARK a story to your shelf & add to interests.',
          ),
          const SizedBox(height: 6),
          _TutorialItem(
            icon: Icons.touch_app_rounded,
            color: Colors.orangeAccent,
            text:
                'Tap a card to read full stories, comments, or explore profiles.',
          ),
        ],
      ),
    );
  }
}

class _TutorialItem extends StatelessWidget {
  const _TutorialItem(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Post Reporting Dialogs ──────────────────────────────────────────────────

void _showReportDialog(BuildContext context, WidgetRef ref, Post post) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Story',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? cardCharcoalText : cardCreamText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Why are you reporting this story?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                ),
              ),
              const SizedBox(height: 20),
              _ReportOption(
                label: 'Spam',
                onTap: () => _submitReport(context, ref, post, 'spam'),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Abuse or Harassment',
                onTap: () => _submitReport(context, ref, post, 'abuse'),
                isDark: isDark,
              ),
              _ReportOption(
                label: 'Other',
                onTap: () async {
                  Navigator.pop(context); // close bottom sheet
                  final customReason = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
                        title: Text(
                          'Specify Reason',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                        ),
                        content: TextField(
                          controller: controller,
                          maxLength: 200,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter reason (up to 200 characters)...',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? cardCharcoalText : cardCreamText,
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'CANCEL',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final text = controller.text.trim();
                              if (text.isNotEmpty) {
                                Navigator.pop(context, text);
                              }
                            },
                            child: Text(
                              'SUBMIT',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalText : cardCreamText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                  if (customReason != null && customReason.isNotEmpty) {
                    if (context.mounted) {
                      _submitReport(context, ref, post, customReason, popContext: false);
                    }
                  }
                },
                isDark: isDark,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReportOption extends StatelessWidget {
  const _ReportOption({
    required this.label,
    required this.onTap,
    required this.isDark,
  });
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? cardCharcoalText : cardCreamText;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? cardCharcoalEdge : cardCreamEdge,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _submitReport(
  BuildContext context,
  WidgetRef ref,
  Post post,
  String reason, {
  bool popContext = true,
}) async {
  if (popContext) {
    Navigator.pop(context); // close bottom sheet
  }

  final dio = ref.read(apiClientProvider).dio;
  try {
    await dio.post<void>(
      '/api/v1/posts/${post.id}/report',
      data: <String, dynamic>{'reason': reason},
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you. The story has been reported for review.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Swipe away the reported post automatically so user doesn't see it
    ref.read(swipeDeckControllerProvider.notifier).swipe(
          storyId: post.id,
          direction: 'left', // swipe left (skip)
        );
  } on DioException catch (e) {
    if (!context.mounted) return;
    final msg = e.response?.data?['detail']?.toString() ?? 'Failed to submit report';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
