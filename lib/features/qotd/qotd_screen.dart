import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/card_brightness_provider.dart';
import '../profile/controller/profile_controller.dart';
import 'models/answer.dart';
import 'qotd_controller.dart';

const _kCardRadius = 24.0;
const _kSwipeThresholdFraction = 0.22;
const _kFlingVelocity = 500.0;

/// Card colours that follow the sun/moon (card-brightness) toggle, matching the
/// Discover deck so the toggle visibly changes the QOTD cards too.
class _CardPalette {
  const _CardPalette(this.bg, this.mid, this.edge, this.text, this.subtext, this.accent);
  final Color bg, mid, edge, text, subtext, accent;
}

_CardPalette _palette(WidgetRef ref) {
  final isDark = (ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark) == Brightness.dark;
  return isDark
      ? const _CardPalette(cardCharcoalDark, cardCharcoalMid, cardCharcoalEdge,
          cardCharcoalText, cardCharcoalSubtext, cardCharcoalAccent)
      : const _CardPalette(cardCreamLight, cardCreamMid, cardCreamEdge,
          cardCreamText, cardCreamSubtext, cardCreamAccent);
}

/// The "Daily" tab. Each question is gated - you must answer it to see others'
/// answers - and you flip between days with prev/next. Answers advance with a
/// page-up / rise-from-below animation.
class QotdScreen extends ConsumerWidget {
  const QotdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(qotdControllerProvider);
    return async.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2.5)),
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
    // On wide screens, center the content in a comfortable column and cap the
    // swipe card so it doesn't stretch across the desktop.
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    const maxContentWidth = 600.0;
    const maxDeckHeight = 560.0;

    final c = ref.read(qotdControllerProvider.notifier);
    final onPrev = state.prevQuestionId != null ? () => c.loadPrevious() : null;
    final onNext = state.nextQuestionId != null ? () => c.loadNext() : null;

    final Widget content;
    if (state.isGated) {
      // No answer yet (or last one rejected) → focused invitation card.
      content = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: _DaySwiper(
          key: ValueKey('swipe-gate-${state.question!.id}'),
          onPrev: onPrev,
          onNext: onNext,
          child: _GatedQuestionCard(key: ValueKey('gate-${state.question!.id}'), state: state),
        ),
      );
    } else if (state.isPending) {
      // Answered but awaiting moderation → locked until approved.
      content = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: _DaySwiper(
          key: ValueKey('swipe-pend-${state.question!.id}'),
          onPrev: onPrev,
          onNext: onNext,
          child: _PendingReviewCard(key: ValueKey('pend-${state.question!.id}'), state: state),
        ),
      );
    } else {
      // Approved → banner stuck to top + the answer deck below.
      final deckArea = state.deck.isEmpty
          ? _DeckEmptyView(state: state)
          : _AnswerDeck(deck: state.deck, rewindDir: state.rewindFromDir);
      content = _RiseIn(
        key: ValueKey('ans-${state.question!.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _QuestionBanner(state: state),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                child: isWide
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: maxDeckHeight),
                          child: deckArea,
                        ),
                      )
                    : deckArea,
              ),
            ),
          ],
        ),
      );
    }

    final Widget sized = isWide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: content,
            ),
          )
        : content;

    return Stack(
      children: <Widget>[
        sized,
        // Floating rewind affordance. Lives at the screen level so it's reachable
        // from any state the last swipe could have landed on - including a gated
        // next-day card after an auto-advance.
        if (state.canUndo)
          Positioned(
            left: 0,
            right: 0,
            bottom: 108,
            child: Center(child: _UndoButton(onTap: () => c.undoSwipe())),
          ),
        if (state.isNavigating)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
          ),
      ],
    );
  }
}

/// Small floating pill that rewinds the last answer swipe.
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.undo_rounded, size: 17, color: cs.primary),
              const SizedBox(width: 6),
              Text('Undo',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a question card so it can be swiped horizontally to change day:
/// drag right → previous (older) question, drag left → next (newer). Passing a
/// null callback disables that direction (e.g. at the ends of the chain).
class _DaySwiper extends StatefulWidget {
  const _DaySwiper({super.key, required this.child, this.onPrev, this.onNext});
  final Widget child;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  State<_DaySwiper> createState() => _DaySwiperState();
}

class _DaySwiperState extends State<_DaySwiper> with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => setState(() => _dx = _anim.value));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    final nd = _dx + d.delta.dx;
    if (nd > 0 && widget.onPrev == null) return; // can't go older
    if (nd < 0 && widget.onNext == null) return; // can't go newer
    setState(() => _dx = nd);
  }

  void _onEnd(DragEndDetails d, double width) {
    final vx = d.velocity.pixelsPerSecond.dx;
    final threshold = width * 0.25;
    if ((_dx > threshold || vx > 600) && widget.onPrev != null) {
      _exit(width, widget.onPrev!);
    } else if ((_dx < -threshold || vx < -600) && widget.onNext != null) {
      _exit(-width, widget.onNext!);
    } else {
      _animateTo(0); // snap back
    }
  }

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _dx, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward(from: 0);
  }

  void _exit(double target, VoidCallback nav) {
    _anim = Tween<double>(begin: _dx, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward(from: 0).whenCompleteOrCancel(nav);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: (d) => _onEnd(d, width),
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(angle: _dx * 0.0005, child: widget.child),
          ),
        );
      },
    );
  }
}

/// Plays a gentle fade + rise on mount. Transform/Opacity are layout-transparent,
/// so wrapping Column/Expanded content is safe.
class _RiseIn extends StatefulWidget {
  const _RiseIn({super.key, required this.child});
  final Widget child;

  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - t) * 48), child: child),
        );
      },
      child: widget.child,
    );
  }
}

// ─── Day navigation (prev / today / next) ───────────────────────────────────────

class _QuestionNav extends ConsumerWidget {
  const _QuestionNav({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = ref.read(qotdControllerProvider.notifier);
    final accent = colorScheme.primary;

    final dateLabel = state.isToday
        ? 'Today'
        : (state.question?.activeDate ?? 'Earlier');

    return Row(
      children: <Widget>[
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          color: accent,
          // prev = older question
          onPressed: state.isFirst ? null : () => c.loadPrevious(),
          tooltip: 'Previous question',
        ),
        Expanded(
          child: Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          color: accent,
          // next = newer question
          onPressed: state.isLast ? null : () => c.loadNext(),
          tooltip: 'Next question',
        ),
      ],
    );
  }
}

// ─── Top banner (answered state) ────────────────────────────────────────────────

class _QuestionBanner extends ConsumerWidget {
  const _QuestionBanner({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final question = state.question!;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(state.isToday ? Icons.wb_sunny_rounded : Icons.history_rounded,
                    size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.isToday ? 'QUESTION OF THE DAY' : 'FROM ${question.activeDate ?? "earlier"}',
                    style: GoogleFonts.inter(
                      fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: colorScheme.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.ios_share_rounded, size: 18, color: colorScheme.primary),
                  tooltip: 'Challenge a friend',
                  onPressed: () => _shareQuestion(ref, question.id, question.prompt),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              question.prompt,
              style: GoogleFonts.lora(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25, color: colorScheme.onSurface),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            if (state.myAnswer != null) _MyAnswerButton(answer: state.myAnswer!),
            _QuestionNav(state: state),
          ],
        ),
      ),
    );
  }
}

/// Shows the author the review state of their own answer.
(IconData, String, Color) _answerStatusVisuals(ColorScheme cs, String status) {
  switch (status) {
    case 'approved':
      return (Icons.check_circle_rounded, 'Your answer is live', cs.primary);
    case 'rejected':
      return (Icons.cancel_rounded, "Your answer wasn't approved", cs.error);
    default:
      return (Icons.hourglass_top_rounded, 'Your answer is in review', cs.onSurfaceVariant);
  }
}

/// Compact pill in the banner. Tapping it opens a sheet with the full answer.
class _MyAnswerButton extends ConsumerWidget {
  const _MyAnswerButton({required this.answer});
  final Answer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final (icon, _, color) = _answerStatusVisuals(cs, answer.moderationStatus);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showMyAnswerSheet(context, ref, answer),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 13, color: color.withValues(alpha: 0.85)),
                  const SizedBox(width: 6),
                  Text('Your answer',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showMyAnswerSheet(BuildContext context, WidgetRef ref, Answer answer) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final (icon, statusText, color) = _answerStatusVisuals(cs, answer.moderationStatus);
      return Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(statusText, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Text(answer.body, style: GoogleFonts.lora(fontSize: 17, height: 1.55, color: cs.onSurface)),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeleteMyAnswer(context, ref);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text('Delete answer'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmDeleteMyAnswer(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete your answer?'),
      content: const Text('This removes your answer. You can write a new one afterwards.'),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(qotdControllerProvider.notifier).deleteMyAnswer();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e)), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

// ─── Gated invitation card (not answered) ───────────────────────────────────────

class _GatedQuestionCard extends ConsumerStatefulWidget {
  const _GatedQuestionCard({super.key, required this.state});
  final QotdState state;

  @override
  ConsumerState<_GatedQuestionCard> createState() => _GatedQuestionCardState();
}

class _GatedQuestionCardState extends ConsumerState<_GatedQuestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;

  @override
  void initState() {
    super.initState();
    // Rise in from the bottom like an answer card whenever a new question lands.
    _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..forward();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final p = _palette(ref);
    final state = widget.state;
    final question = state.question!;

    return AnimatedBuilder(
      animation: _in,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_in.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - t) * 70), child: child),
        );
      },
      child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openComposerSheet(context, ref),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                decoration: BoxDecoration(
                  color: p.bg,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: <Color>[
                      p.accent.withValues(alpha: 0.16),
                      p.accent.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  border: Border.all(color: p.accent.withValues(alpha: 0.22), width: 0.8),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(state.isToday ? Icons.wb_sunny_rounded : Icons.history_rounded,
                            size: 16, color: p.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            state.isToday ? 'QUESTION OF THE DAY' : 'FROM ${question.activeDate ?? "earlier"}',
                            style: GoogleFonts.inter(
                                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: p.accent),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.ios_share_rounded, size: 18, color: p.accent),
                          tooltip: 'Challenge a friend',
                          onPressed: () => _shareQuestion(ref, question.id, question.prompt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      question.prompt,
                      style: GoogleFonts.lora(fontSize: 30, fontWeight: FontWeight.w700, height: 1.28, color: p.text),
                    ),
                    if (state.isRejected) ...<Widget>[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.cancel_rounded, size: 18, color: colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('Your answer was rejected',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: colorScheme.error)),
                                  const SizedBox(height: 2),
                                  Text("It wasn't approved by a moderator. Write a new one below.",
                                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: colorScheme.error.withValues(alpha: 0.9))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Row(
                      children: <Widget>[
                        Icon(Icons.lock_outline_rounded, size: 14, color: p.subtext.withValues(alpha: 0.8)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Answer to unlock everyone else's replies.",
                            style: GoogleFonts.inter(
                                fontSize: 12.5, height: 1.4, color: p.subtext.withValues(alpha: 0.85)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: state.isSubmitting ? null : () => _openComposerSheet(context, ref),
                        icon: state.isSubmitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.edit_rounded, size: 18),
                        label: Text(state.isSubmitting ? 'Posting…' : 'Write your answer'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _QuestionNav(state: state),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Pending-review card (answered, awaiting moderation) ────────────────────────

/// Shown after answering while the answer is in review. The deck stays locked
/// until a moderator approves it - so a pending/gibberish answer can't peek.
class _PendingReviewCard extends ConsumerWidget {
  const _PendingReviewCard({super.key, required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = _palette(ref);
    final question = state.question!;
    return _RiseIn(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                decoration: BoxDecoration(
                  color: p.bg,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      p.accent.withValues(alpha: 0.14),
                      p.accent.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  border: Border.all(color: p.accent.withValues(alpha: 0.20), width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(state.isToday ? Icons.wb_sunny_rounded : Icons.history_rounded, size: 16, color: p.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            state.isToday ? 'QUESTION OF THE DAY' : 'FROM ${question.activeDate ?? "earlier"}',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: p.accent),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.ios_share_rounded, size: 18, color: p.accent),
                          tooltip: 'Challenge a friend',
                          onPressed: () => _shareQuestion(ref, question.id, question.prompt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      question.prompt,
                      style: GoogleFonts.lora(fontSize: 26, fontWeight: FontWeight.w700, height: 1.28, color: p.text),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.hourglass_top_rounded, size: 15, color: p.subtext.withValues(alpha: 0.9)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Your answer is in review. You'll see everyone's answers once it's approved.",
                            style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: p.subtext.withValues(alpha: 0.9)),
                          ),
                        ),
                      ],
                    ),
                    _MyAnswerButton(answer: state.myAnswer!),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _QuestionNav(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Answer deck (vertical: lift-up + rise-from-bottom) ──────────────────────────

class _AnswerDeck extends ConsumerStatefulWidget {
  const _AnswerDeck({required this.deck, this.rewindDir});
  final List<Answer> deck;

  /// When set ('right'/'left'), the top card was just restored by an undo and
  /// should animate back IN from that side.
  final String? rewindDir;

  @override
  ConsumerState<_AnswerDeck> createState() => _AnswerDeckState();
}

class _AnswerDeckState extends ConsumerState<_AnswerDeck> with TickerProviderStateMixin {
  double _dragX = 0;
  bool _transitioning = false;
  bool _awaitingDeckUpdate = false;
  Answer? _outgoing;
  String _dir = 'left';

  bool _rewinding = false;
  String _rewindDir = 'left';

  late final AnimationController _ctrl; // exit/enter
  late final AnimationController _snap; // snap-back
  late final AnimationController _rewindCtrl; // undo: card flies back in
  late Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 440))
      ..addStatusListener(_onEnd);
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
      ..addListener(() => setState(() => _dragX = _snapAnim.value));
    _rewindCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _rewinding = false);
      });
    _snapAnim = const AlwaysStoppedAnimation<double>(0);
    // A freshly built deck (e.g. an undo that switched from the empty view) may
    // already carry a rewind hint.
    if (widget.rewindDir != null) _startRewind(widget.rewindDir!);
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onEnd)
      ..dispose();
    _snap.dispose();
    _rewindCtrl.dispose();
    super.dispose();
  }

  void _startRewind(String dir) {
    _transitioning = false;
    _awaitingDeckUpdate = false;
    _outgoing = null;
    _dragX = 0;
    _rewinding = true;
    _rewindDir = dir;
    _rewindCtrl.forward(from: 0);
  }

  void _onEnd(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final card = _outgoing;
    if (card != null) {
      ref.read(qotdControllerProvider.notifier).swipe(answerId: card.id, direction: _dir == 'right' ? 'right' : 'left');
    }
    // Keep rendering the finished frame (outgoing off-screen, next in place)
    // until the parent delivers the updated deck. Resetting now would briefly
    // re-render the just-swiped card as the top card ("pops back in").
    setState(() => _awaitingDeckUpdate = true);
  }

  @override
  void didUpdateWidget(covariant _AnswerDeck old) {
    super.didUpdateWidget(old);
    final oldTop = old.deck.isNotEmpty ? old.deck.first.id : null;
    final newTop = widget.deck.isNotEmpty ? widget.deck.first.id : null;

    // An undo restored a (different) card on top with a rewind hint - fly it in.
    if (widget.rewindDir != null && newTop != null && newTop != oldTop) {
      _startRewind(widget.rewindDir!);
      return;
    }

    if (!_awaitingDeckUpdate) return;
    if (newTop != oldTop) {
      // New deck arrived → safe to return to idle on the new top card.
      _awaitingDeckUpdate = false;
      _transitioning = false;
      _outgoing = null;
      _dragX = 0;
      _ctrl.reset();
    }
  }

  void _commit(Answer top, String dir) {
    _outgoing = top;
    _dir = dir;
    setState(() => _transitioning = true);
    _ctrl.forward(from: 0);
  }

  void _snapBack() {
    _snapAnim = Tween<double>(begin: _dragX, end: 0).animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    _snap.forward(from: 0);
  }

  void _onPanEnd(DragEndDetails d, double width, Answer top) {
    if (_transitioning) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    final threshold = width * _kSwipeThresholdFraction;
    if (_dragX > threshold || (vx > _kFlingVelocity && _dragX > 0)) {
      _commit(top, 'right');
    } else if (_dragX < -threshold || (vx < -_kFlingVelocity && _dragX < 0)) {
      _commit(top, 'left');
    } else {
      _snapBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    if (deck.isEmpty) return const SizedBox.shrink();
    final top = deck[0];
    final next = deck.length > 1 ? deck[1] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;

        if (_rewinding) {
          // Undo: the restored card flies back IN from the side it left while
          // the card behind it (the one that had become top) sits still.
          return AnimatedBuilder(
            animation: _rewindCtrl,
            builder: (_, __) {
              final t = Curves.easeOutCubic.transform(_rewindCtrl.value);
              final sign = _rewindDir == 'right' ? 1.0 : -1.0;
              final dx = sign * w * 1.4 * (1 - t);
              return Stack(
                children: <Widget>[
                  if (next != null) _AnswerCard(answer: next),
                  Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.rotate(angle: dx * 0.0010, child: _AnswerCard(answer: top)),
                  ),
                ],
              );
            },
          );
        }

        if (_transitioning) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final tOut = Curves.easeInCubic.transform(_ctrl.value);
              final tIn = Curves.easeOutCubic.transform(_ctrl.value);
              // Incoming card rises from below into place.
              final inDy = (1 - tIn) * h * 0.55;
              final inScale = 0.94 + 0.06 * tIn;
              // Outgoing card flies OUT sideways in the swipe direction.
              final outTargetX = (_dir == 'right' ? 1 : -1) * w * 1.5;
              final outDx = _dragX + (outTargetX - _dragX) * tOut;
              return Stack(
                children: <Widget>[
                  if (next != null)
                    Opacity(
                      opacity: (0.7 + 0.3 * tIn).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, inDy),
                        child: Transform.scale(scale: inScale, child: _AnswerCard(answer: next)),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(outDx, 0),
                    child: Transform.rotate(angle: outDx * 0.0010, child: _AnswerCard(answer: _outgoing ?? top)),
                  ),
                ],
              );
            },
          );
        }

        return Stack(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _dragX += d.delta.dx),
              onPanEnd: (d) => _onPanEnd(d, w, top),
              child: Transform.translate(
                offset: Offset(_dragX, 0),
                child: Transform.rotate(
                  angle: _dragX * 0.0008,
                  child: Stack(
                    children: <Widget>[
                      _AnswerCard(answer: top),
                      if (_dragX.abs() > 12)
                        Positioned.fill(
                          child: _SwipeLabel(isLike: _dragX > 0, opacity: (_dragX.abs() / 80).clamp(0.0, 1.0)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AnswerCard extends ConsumerWidget {
  const _AnswerCard({required this.answer});
  final Answer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = _palette(ref);
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: p.edge, width: 0.8),
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
                  backgroundColor: p.accent.withValues(alpha: 0.16),
                  child: Text(
                    answer.authorName.isNotEmpty ? answer.authorName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: p.accent),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    answer.authorName.isNotEmpty ? answer.authorName : 'Anonymous',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: p.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.ios_share_rounded, size: 16, color: p.subtext.withValues(alpha: 0.7)),
                  tooltip: 'Share answer',
                  onPressed: () => _shareAnswer(ref, answer),
                ),
                const SizedBox(width: 10),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.flag_outlined, size: 16, color: p.subtext.withValues(alpha: 0.6)),
                  tooltip: 'Report answer',
                  onPressed: () => _reportAnswer(context, ref, answer),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(answer.body, style: GoogleFonts.lora(fontSize: 19, height: 1.55, color: p.text)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.swipe_rounded, size: 13, color: p.subtext.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text('Swipe right to ❤  ·  left to skip',
                    style: GoogleFonts.inter(fontSize: 12, color: p.subtext.withValues(alpha: 0.65))),
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
    // Mirror the Discover feed's drag label: a dark gradient sweeping from the
    // swipe edge toward centre, with a white icon + white text.
    final align = isLike ? Alignment.centerLeft : Alignment.centerRight;
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardRadius),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(isLike ? Icons.favorite_rounded : Icons.close_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  isLike ? 'LIKE' : 'SKIP',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.4,
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

// ─── Deck-empty / no-question / error views ─────────────────────────────────────

/// Terminal state: you've read everything available right now. Passive (no
/// auto-advance) so it never bounces away from a manually-opened question.
class _DeckEmptyView extends ConsumerWidget {
  const _DeckEmptyView({required this.state});
  final QotdState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.done_all_rounded, size: 52, color: colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            "You're all caught up",
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            "You've read every answer available right now. 🌱",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 20),
          if (!state.isToday)
            FilledButton.icon(
              onPressed: () => ref.read(qotdControllerProvider.notifier).goToToday(),
              icon: const Icon(Icons.wb_sunny_rounded, size: 18),
              label: const Text('Back to today'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            ),
        ],
      ),
    );
  }
}

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
            Text('Check back soon - a new question lands every day.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, height: 1.55, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
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
  await Share.share('On PaperStock: "$prompt"\n\nWhat\'s your answer? 👉 $base/q/$questionId$refSuffix',
      subject: 'Question of the Day');
}

Future<void> _shareAnswer(WidgetRef ref, Answer answer) async {
  final base = ApiConfig.baseUrl;
  await Share.share(
    '"${answer.body}"\n\nSeen on PaperStock 👉 $base/q/${answer.questionId}',
    subject: 'An answer on PaperStock',
  );
}

const int _kMinAnswerChars = 20;

Future<void> _openComposerSheet(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final len = controller.text.trim().length;
          final canPost = len >= _kMinAnswerChars;
          return Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Your answer', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'A sentence or two - paint the picture ✨',
                  style: GoogleFonts.inter(fontSize: 12.5, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 500, maxLines: 5, minLines: 3, autofocus: true,
                  onChanged: (_) => setSheetState(() {}),
                  style: GoogleFonts.inter(fontSize: 16, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Share your answer…',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                if (!canPost)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_kMinAnswerChars - len} more character${(_kMinAnswerChars - len) == 1 ? '' : 's'} to go',
                      style: GoogleFonts.inter(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    ),
                  ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: canPost ? () => Navigator.pop(ctx, controller.text.trim()) : null,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Post my answer'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Answers are reviewed before they appear to others.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
              ],
            ),
          );
        },
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
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(padding: EdgeInsets.all(16), child: Text('Report this answer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          for (final r in const ['Spam', 'Abuse or harassment', 'Inappropriate'])
            ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await ref.read(qotdRepositoryProvider).reportAnswer(answerId: answer.id, reason: reason);
    await ref.read(qotdControllerProvider.notifier).swipe(answerId: answer.id, direction: 'left');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks - the answer has been reported.'), behavior: SnackBarBehavior.floating),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(e)), behavior: SnackBarBehavior.floating));
    }
  }
}
