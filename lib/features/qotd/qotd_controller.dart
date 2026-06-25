import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client_provider.dart';
import 'models/answer.dart';
import 'models/question.dart';
import 'qotd_repository.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final qotdRepositoryProvider = Provider<QotdRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return QotdRepository(dio: dio);
});

final qotdControllerProvider =
    AutoDisposeAsyncNotifierProvider<QotdController, QotdState>(
  QotdController.new,
);

// ─── State ────────────────────────────────────────────────────────────────────

class QotdState {
  const QotdState({
    required this.question,
    required this.myAnswer,
    required this.totalAnswers,
    required this.deck,
    required this.prevQuestionId,
    required this.nextQuestionId,
    required this.prevUnseenQuestionId,
    required this.isFirst,
    required this.isLast,
    required this.isToday,
    required this.isSubmitting,
    required this.isNavigating,
    required this.canUndo,
    this.rewindFromDir,
  });

  final Question? question;
  final Answer? myAnswer;
  final int totalAnswers;

  /// Other users' answers to the focused question, still to swipe.
  final List<Answer> deck;

  /// Chain links (null at the ends).
  final String? prevQuestionId; // older (any)
  final String? nextQuestionId; // newer (any)
  final String? prevUnseenQuestionId; // older day that still has unseen answers
  final bool isFirst;
  final bool isLast;

  final bool isToday;
  final bool isSubmitting;

  /// True while loading a different question (chain navigation).
  final bool isNavigating;

  /// True when the most recent answer swipe can be rewound.
  final bool canUndo;

  /// Transient one-shot hint set right after an undo so the deck can animate the
  /// restored card back IN from the side it left ('right'/'left'). Null normally;
  /// any subsequent state update clears it. Only set for same-question undos -
  /// cross-day undos are carried by the question-change entrance animation.
  final String? rewindFromDir;

  bool get hasQuestion => question != null;
  bool get hasAnswered => myAnswer != null;

  String get _answerStatus => myAnswer?.moderationStatus ?? '';

  /// Others' answers are revealed only once YOUR answer is approved - so a
  /// pending/gibberish answer can't unlock the deck.
  bool get isUnlocked => _answerStatus == 'approved';
  bool get isPending => _answerStatus == 'pending';
  bool get isRejected => _answerStatus == 'rejected';

  /// Show the composer when there's no answer yet, or the last one was rejected.
  bool get isGated => myAnswer == null || isRejected;

  QotdState copyWith({
    Question? question,
    Answer? myAnswer,
    int? totalAnswers,
    List<Answer>? deck,
    String? prevQuestionId,
    String? nextQuestionId,
    String? prevUnseenQuestionId,
    bool? isFirst,
    bool? isLast,
    bool? isToday,
    bool? isSubmitting,
    bool? isNavigating,
    bool? canUndo,
    String? rewindFromDir, // transient: reset to null unless explicitly passed
  }) {
    return QotdState(
      question: question ?? this.question,
      myAnswer: myAnswer ?? this.myAnswer,
      totalAnswers: totalAnswers ?? this.totalAnswers,
      deck: deck ?? this.deck,
      prevQuestionId: prevQuestionId ?? this.prevQuestionId,
      nextQuestionId: nextQuestionId ?? this.nextQuestionId,
      prevUnseenQuestionId: prevUnseenQuestionId ?? this.prevUnseenQuestionId,
      isFirst: isFirst ?? this.isFirst,
      isLast: isLast ?? this.isLast,
      isToday: isToday ?? this.isToday,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isNavigating: isNavigating ?? this.isNavigating,
      canUndo: canUndo ?? this.canUndo,
      rewindFromDir: rewindFromDir,
    );
  }

  static const QotdState empty = QotdState(
    question: null,
    myAnswer: null,
    totalAnswers: 0,
    deck: <Answer>[],
    prevQuestionId: null,
    nextQuestionId: null,
    prevUnseenQuestionId: null,
    isFirst: true,
    isLast: true,
    isToday: true,
    isSubmitting: false,
    isNavigating: false,
    canUndo: false,
  );
}

// ─── Controller ───────────────────────────────────────────────────────────────

/// One rewindable swipe: the full state as it was just before the swipe, plus
/// which answer was swiped and in which direction.
class _UndoEntry {
  const _UndoEntry(this.stateBefore, this.answerId, this.direction);
  final QotdState stateBefore;
  final String answerId;
  final String direction;
}

class QotdController extends AutoDisposeAsyncNotifier<QotdState> {
  final Set<String> _swipedThisSession = <String>{};

  // Rewind history: a full pre-swipe state snapshot per swipe, most-recent last.
  // Each undo restores the snapshot (jumping back across days if the swipe was
  // the last card that auto-advanced). The stack lives only for this controller
  // instance - leaving the Daily tab disposes it (auto-dispose) and closing the
  // app drops it, so undo never survives leaving the page.
  final List<_UndoEntry> _undoStack = <_UndoEntry>[];

  // Previous (older) question fetched ahead of time so that, when the current
  // deck is exhausted, we can rise straight into it without a loading gap or an
  // intermediate "that's everyone" screen.
  QotdDetail? _prefetchedPrev;
  String? _prefetchedPrevId;

  void _prefetchPrev(String? prevId) {
    if (prevId == null) return;
    if (_prefetchedPrevId == prevId && _prefetchedPrev != null) return;
    () async {
      try {
        final d = await ref.read(qotdRepositoryProvider).getQuestion(prevId);
        _prefetchedPrev = d;
        _prefetchedPrevId = prevId;
      } catch (_) {}
    }();
  }

  QotdState _stateFrom(QotdDetail d, {required List<Answer> deck}) {
    return QotdState(
      question: d.question,
      myAnswer: d.myAnswer,
      totalAnswers: d.totalAnswers,
      deck: deck,
      prevQuestionId: d.prevQuestionId,
      nextQuestionId: d.nextQuestionId,
      prevUnseenQuestionId: d.prevUnseenQuestionId,
      isFirst: d.isFirst,
      isLast: d.isLast,
      isToday: d.isToday,
      isSubmitting: false,
      isNavigating: false,
      // The rewind history outlives day changes, so a swipe that auto-advanced
      // (or any navigation afterwards) keeps the undo affordance available.
      canUndo: _undoStack.isNotEmpty,
    );
  }

  Future<List<Answer>> _deckFor(QotdDetail d) async {
    // The deck unlocks only when the viewer's own answer is approved.
    final approved = d.myAnswer != null && d.myAnswer!.moderationStatus == 'approved';
    if (d.question == null || !approved) return const <Answer>[];
    return ref.read(qotdRepositoryProvider).getDeck(questionId: d.question!.id, limit: 20);
  }

  @override
  Future<QotdState> build() async {
    _undoStack.clear(); // fresh start on (re)build, e.g. after refresh()
    final repo = ref.watch(qotdRepositoryProvider);
    try {
      final today = await repo.getToday();
      if (today.question == null) return QotdState.empty;
      final deck = await _deckFor(today);
      if (today.hasAnswered) _prefetchPrev(today.prevUnseenQuestionId);
      return _stateFrom(today, deck: deck);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return QotdState.empty;
      rethrow;
    }
  }

  /// Submit/update the answer for the focused question. The deck stays locked
  /// (empty) until a moderator approves the answer.
  Future<void> submitAnswer(String body) async {
    final current = state.valueOrNull;
    if (current?.question == null || current!.isSubmitting) return;

    state = AsyncData(current.copyWith(isSubmitting: true));
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final answer = await repo.submitAnswer(questionId: current.question!.id, body: body);

      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          myAnswer: answer,
          deck: const <Answer>[], // pending → locked
          isSubmitting: false,
        ),
      );
    } catch (e) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(isSubmitting: false));
      rethrow;
    }
  }

  /// Delete the caller's own answer for the focused question; the question
  /// returns to its gated state so they can answer again.
  Future<void> deleteMyAnswer() async {
    final current = state.valueOrNull;
    final ans = current?.myAnswer;
    final q = current?.question;
    if (current == null || ans == null || q == null) return;
    await ref.read(qotdRepositoryProvider).deleteAnswer(ans.id);
    await _loadQuestion(q.id);
  }

  Future<void> loadPrevious() async {
    final prevId = state.valueOrNull?.prevQuestionId;
    if (prevId != null) await _loadQuestion(prevId);
  }

  Future<void> loadNext() async {
    final nextId = state.valueOrNull?.nextQuestionId;
    if (nextId != null) await _loadQuestion(nextId);
  }

  Future<void> goToToday() async {
    final current = state.valueOrNull;
    if (current == null || current.isToday) return;
    state = AsyncData(current.copyWith(isNavigating: true));
    try {
      final today = await ref.read(qotdRepositoryProvider).getToday();
      if (today.question == null) {
        state = AsyncData(QotdState.empty);
        return;
      }
      final deck = await _deckFor(today);
      state = AsyncData(_stateFrom(today, deck: deck));
      if (today.hasAnswered) _prefetchPrev(today.prevUnseenQuestionId);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(isNavigating: false));
    }
  }

  Future<void> _loadQuestion(String questionId) async {
    final current = state.valueOrNull;
    if (current != null) state = AsyncData(current.copyWith(isNavigating: true));
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final detail = await repo.getQuestion(questionId);
      final deck = await _deckFor(detail);
      state = AsyncData(_stateFrom(detail, deck: deck));
      if (detail.hasAnswered) _prefetchPrev(detail.prevUnseenQuestionId);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(isNavigating: false));
    }
  }

  Future<void> swipe({required String answerId, required String direction}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final index = current.deck.indexWhere((a) => a.id == answerId);
    if (index < 0) return;

    _swipedThisSession.add(answerId);
    // Snapshot the pre-swipe state (cleaned of any transient rewind hint) so the
    // swipe can be rewound later - even after auto-advancing to another day.
    _undoStack.add(_UndoEntry(current.copyWith(), answerId, direction));
    final newDeck = List<Answer>.of(current.deck)..removeAt(index);
    // Auto-advance targets the previous day that still has UNSEEN answers.
    final prevId = current.prevUnseenQuestionId;

    // Record the swipe (fire-and-forget).
    final repo = ref.read(qotdRepositoryProvider);
    () async {
      try {
        await repo.recordSwipe(answerId: answerId, direction: direction);
      } catch (_) {}
    }();

    // Last answer + the previous unseen question is prefetched (and still gated):
    // rise STRAIGHT into it as the next card. Never render the empty deck or a
    // spinner - that's what caused the "that's everyone" flash.
    final canInstantAdvance = newDeck.isEmpty &&
        prevId != null &&
        _prefetchedPrev != null &&
        _prefetchedPrevId == prevId &&
        !_prefetchedPrev!.hasAnswered;

    if (canInstantAdvance) {
      final d = _prefetchedPrev!;
      _prefetchedPrev = null;
      _prefetchedPrevId = null;
      state = AsyncData(_stateFrom(d, deck: const <Answer>[]));
      _prefetchPrev(d.prevUnseenQuestionId); // line up the next one back
      return;
    }

    state = AsyncData(current.copyWith(deck: newDeck, canUndo: true));

    // Fallback (prefetch not ready): load the previous unseen question.
    if (newDeck.isEmpty) {
      if (prevId != null) {
        await _loadQuestion(prevId);
      }
      return;
    }
    if (newDeck.length <= 3 && current.question != null) {
      _refillDeck(questionId: current.question!.id, currentDeck: newDeck);
    }
  }

  /// Rewind the most recent answer swipe. Restores the exact pre-swipe state -
  /// which jumps back to the previous day if that swipe was the last card and we
  /// auto-advanced. The restored card lands back on top.
  Future<void> undoSwipe() async {
    final current = state.valueOrNull;
    if (current == null || _undoStack.isEmpty) return;

    final entry = _undoStack.removeLast();
    _swipedThisSession.remove(entry.answerId);

    final before = entry.stateBefore;
    final sameQuestion = current.question?.id == before.question?.id;

    state = AsyncData(before.copyWith(
      canUndo: _undoStack.isNotEmpty,
      // Same-day undo: animate the card back in from the side it left. Cross-day
      // undo changes the question, so the entrance animation covers it instead.
      rewindFromDir: sameQuestion ? entry.direction : null,
    ));
    // Re-line-up the prefetched previous question for the restored state.
    _prefetchPrev(before.prevUnseenQuestionId);

    // Best-effort: tell the server to forget the swipe so the card isn't
    // filtered out of future decks and any heart is withdrawn.
    try {
      await ref.read(qotdRepositoryProvider).undoSwipe();
    } catch (_) {}
  }

  Future<void> _refillDeck({required String questionId, required List<Answer> currentDeck}) async {
    try {
      final fresh = await ref.read(qotdRepositoryProvider).getDeck(questionId: questionId, limit: 20);
      final existingIds = currentDeck.map((a) => a.id).toSet();
      final merged = <Answer>[
        ...currentDeck,
        ...fresh.where((a) =>
            !existingIds.contains(a.id) && !_swipedThisSession.contains(a.id)),
      ];
      final latest = state.valueOrNull;
      if (latest == null || latest.question?.id != questionId) return;
      state = AsyncData(latest.copyWith(deck: merged));
    } catch (_) {}
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
