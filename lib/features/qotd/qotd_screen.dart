import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_config.dart';
import '../profile/controller/profile_controller.dart';
import 'models/answer.dart';
import 'qotd_controller.dart';

const _kCardRadius = 24.0;
const _kSwipeThresholdFraction = 0.25;
const _kFlingVelocity = 550.0;

/// The "Daily" tab — today's question on top, with a readable archive of past
/// days chained behind it (run out of today's answers → read yesterday's, and
/// so on back to the very first question).
class QotdScreen extends ConsumerWidget {
  const QotdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(qotdControllerProvider);

    return async.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      error: (err, _) => _ErrorView(onRetry: () => ref.invalidate(qotdControllerProvider)),
      data: (state) {
        if (!state.hasQuestion) return const _NoQuestionView();
        return _QotdBody(state: state);
      },
    );
  }
}

class _QotdBody extends ConsumerWidget {
  const _QotdBody({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gated (today, not yet answered): show the big question card invitation.
    final Widget content = state.isGated
        ? _GatedQuestionCard(state: state)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _QuestionHeader(state: state),
              const SizedBox(height: 16),
              Expanded(child: _DeckArea(state: state)),
            ],
          );

    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: content,
        ),
        if (state.isNavigating)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
          ),
      ],
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _QuestionHeader extends ConsumerWidget {
  const _QuestionHeader({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final question = state.question!;
    final label = state.isToday
        ? 'QUESTION OF THE DAY'
        : 'FROM ${(question.activeDate ?? 'a past day').toUpperCase()}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primary.withValues(alpha: 0.14),
            colorScheme.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.20), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(state.isToday ? Icons.wb_sunny_rounded : Icons.history_rounded,
                  size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!state.isToday)
                TextButton(
                  onPressed: () => ref.read(qotdControllerProvider.notifier).goToToday(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Back to today'),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.ios_share_rounded, size: 18, color: colorScheme.primary),
                tooltip: 'Challenge a friend',
                onPressed: () => _shareQuestion(ref, question.id, question.prompt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question.prompt,
            style: GoogleFonts.lora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (state.totalAnswers > 0)
                Text(
                  '${state.totalAnswers} ${state.totalAnswers == 1 ? 'answer' : 'answers'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              if (state.hasAnswered) ...<Widget>[
                if (state.totalAnswers > 0) const SizedBox(width: 12),
                Icon(Icons.check_circle, size: 13, color: colorScheme.primary.withValues(alpha: 0.8)),
                const SizedBox(width: 4),
                Text(
                  'You answered',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Gated question card (today, not yet answered) ──────────────────────────────

/// A focused invitation card: the question, big. Tap anywhere (or the button)
/// to write your answer — which unlocks everyone else's replies.
class _GatedQuestionCard extends ConsumerWidget {
  const _GatedQuestionCard({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final question = state.question!;

    return Center(
      child: SingleChildScrollView(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openComposerSheet(context, ref),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colorScheme.primary.withValues(alpha: 0.16),
                  colorScheme.primary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(_kCardRadius),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22), width: 0.8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.wb_sunny_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'QUESTION OF THE DAY',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.ios_share_rounded, size: 18, color: colorScheme.primary),
                      tooltip: 'Challenge a friend',
                      onPressed: () => _shareQuestion(ref, question.id, question.prompt),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // The question, big.
                Text(
                  question.prompt,
                  style: GoogleFonts.lora(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 28),
                // Small gating hint.
                Row(
                  children: <Widget>[
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "To see everyone else's answers, share one of your own.",
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.4,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.isSubmitting ? null : () => _openComposerSheet(context, ref),
                    icon: state.isSubmitting
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.edit_rounded, size: 18),
                    label: Text(state.isSubmitting ? 'Posting…' : 'Write your answer'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Tap anywhere to answer',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Deck area (today after answering, or any past question) ─────────────────────

class _DeckArea extends ConsumerWidget {
  const _DeckArea({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!state.hasAnswered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => _openComposerSheet(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Add your answer'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        Expanded(
          child: state.deck.isEmpty
              ? _ChainEmptyView(state: state)
              : _AnswerDeck(deck: state.deck),
        ),
      ],
    );
  }
}

/// Shown when the focused question's answer deck is exhausted: walk back to the
/// previous day, or — at the very first question — "this is where it all started".
class _ChainEmptyView extends ConsumerWidget {
  const _ChainEmptyView({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final canGoBack = state.prevQuestionId != null && !state.isFirst;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(canGoBack ? Icons.history_rounded : Icons.spa_rounded,
                size: 56, color: colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              canGoBack ? "That's everyone for this day" : 'This is where it all started',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              canGoBack
                  ? 'Keep reading — go back to the previous day’s question.'
                  : 'You’ve reached the very first Question of the Day. 🌱',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 14, height: 1.5, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            if (canGoBack)
              FilledButton.icon(
                onPressed: () => ref.read(qotdControllerProvider.notifier).loadPrevious(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text("Previous day's question"),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              )
            else if (!state.isToday)
              FilledButton.icon(
                onPressed: () => ref.read(qotdControllerProvider.notifier).goToToday(),
                icon: const Icon(Icons.wb_sunny_rounded, size: 18),
                label: const Text("Back to today"),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Answer swipe deck ──────────────────────────────────────────────────────────

class _AnswerDeck extends ConsumerStatefulWidget {
  const _AnswerDeck({required this.deck});
  final List<Answer> deck;

  @override
  ConsumerState<_AnswerDeck> createState() => _AnswerDeckState();
}

class _AnswerDeckState extends ConsumerState<_AnswerDeck> with SingleTickerProviderStateMixin {
  double _dragX = 0;
  late final AnimationController _ctrl;
  late Animation<double> _exitX;
  bool _transitioning = false;
  Answer? _outgoing;
  String _exitDirection = 'left';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..addStatusListener(_onEnd);
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onEnd)
      ..dispose();
    super.dispose();
  }

  void _onEnd(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final card = _outgoing;
    if (card != null) {
      ref.read(qotdControllerProvider.notifier).swipe(
            answerId: card.id,
            direction: _exitDirection == 'right' ? 'right' : 'left',
          );
    }
    setState(() {
      _transitioning = false;
      _dragX = 0;
      _outgoing = null;
    });
    _ctrl.reset();
  }

  void _startExit({required Answer card, required String dir, required double width}) {
    _outgoing = card;
    _exitDirection = dir;
    final endX = dir == 'right' ? width * 1.5 : -width * 1.5;
    _exitX = Tween<double>(begin: _dragX, end: endX)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInCubic));
    setState(() => _transitioning = true);
    _ctrl.forward(from: 0);
  }

  void _onPanEnd(DragEndDetails d, Size screen, Answer top) {
    if (_transitioning) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    final threshold = screen.width * _kSwipeThresholdFraction;
    if (_dragX > threshold || (vx > _kFlingVelocity && _dragX > 0)) {
      _startExit(card: top, dir: 'right', width: screen.width);
    } else if (_dragX < -threshold || (vx < -_kFlingVelocity && _dragX < 0)) {
      _startExit(card: top, dir: 'left', width: screen.width);
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final deck = widget.deck;
    if (deck.isEmpty) return const SizedBox.shrink();

    final top = deck[0];
    final next = deck.length > 1 ? deck[1] : null;

    return Stack(
      children: <Widget>[
        if (next != null)
          Positioned.fill(child: Transform.scale(scale: 0.96, child: _AnswerCard(answer: next))),
        if (_transitioning)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.translate(
              offset: Offset(_exitX.value, 0),
              child: Transform.rotate(
                  angle: _exitX.value * 0.0012, child: _AnswerCard(answer: _outgoing ?? top)),
            ),
          )
        else
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _dragX += d.delta.dx),
              onPanEnd: (d) => _onPanEnd(d, screen, top),
              child: Transform.translate(
                offset: Offset(_dragX, 0),
                child: Transform.rotate(
                  angle: _dragX * 0.0012,
                  child: Stack(
                    children: <Widget>[
                      _AnswerCard(answer: top),
                      if (_dragX.abs() > 12)
                        Positioned.fill(
                          child: _SwipeLabel(
                              isLike: _dragX > 0, opacity: (_dragX.abs() / 100).clamp(0.0, 1.0)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AnswerCard extends ConsumerWidget {
  const _AnswerCard({required this.answer});
  final Answer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 0.8),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.16),
                  child: Text(
                    answer.authorName.isNotEmpty ? answer.authorName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    answer.authorName.isNotEmpty ? answer.authorName : 'Anonymous',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.flag_outlined, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  tooltip: 'Report answer',
                  onPressed: () => _reportAnswer(context, ref, answer),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(answer.body,
                    style: GoogleFonts.lora(fontSize: 19, height: 1.55, color: colorScheme.onSurface)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.swipe_rounded, size: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text('Swipe right to ❤  ·  left to skip',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeLabel extends StatelessWidget {
  const _SwipeLabel({required this.isLike, required this.opacity});
  final bool isLike;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Align(
        alignment: isLike ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(isLike ? Icons.favorite_rounded : Icons.close_rounded,
                  color: isLike ? Colors.pinkAccent : Colors.redAccent, size: 26),
              const SizedBox(width: 8),
              Text(
                isLike ? 'LIKE' : 'SKIP',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: isLike ? Colors.pinkAccent : Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── No question / error views ────────────────────────────────────────────────

class _NoQuestionView extends StatelessWidget {
  const _NoQuestionView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wb_twilight_rounded, size: 64, color: colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            Text('No question today',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('Check back soon — a new question lands every day.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 15, height: 1.55, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text("Could not load today's question", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────────

String _friendlyError(Object e) {
  if (e is DioException) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] != null) return detail['detail'].toString();
  }
  return 'Something went wrong. Please try again.';
}

Future<void> _shareQuestion(WidgetRef ref, String questionId, String prompt) async {
  final meId = await ref.read(currentUserIdProvider.future);
  final base = ApiConfig.baseUrl;
  final refSuffix = (meId != null && meId.isNotEmpty) ? '?ref=$meId' : '';
  final link = '$base/q/$questionId$refSuffix';
  await Share.share('On PaperStock: "$prompt"\n\nWhat\'s your answer? 👉 $link',
      subject: 'Question of the Day');
}

Future<void> _openComposerSheet(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Your answer',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 5,
              minLines: 3,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 16, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Share your answer…',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Post my answer'),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  if (result == null || result.isEmpty) return;
  try {
    await ref.read(qotdControllerProvider.notifier).submitAnswer(result);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e)), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

Future<void> _reportAnswer(BuildContext context, WidgetRef ref, Answer answer) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Report this answer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final r in const ['Spam', 'Abuse or harassment', 'Inappropriate'])
              ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
          ],
        ),
      );
    },
  );
  if (reason == null) return;
  try {
    await ref.read(qotdRepositoryProvider).reportAnswer(answerId: answer.id, reason: reason);
    await ref.read(qotdControllerProvider.notifier).swipe(answerId: answer.id, direction: 'left');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — the answer has been reported.'), behavior: SnackBarBehavior.floating),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e)), behavior: SnackBarBehavior.floating),
      );
    }
  }
}
