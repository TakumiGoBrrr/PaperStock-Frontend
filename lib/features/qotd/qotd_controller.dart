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
    required this.isFirst,
    required this.isToday,
    required this.isSubmitting,
    required this.isNavigating,
  });

  final Question? question;
  final Answer? myAnswer;
  final int totalAnswers;

  /// Other users' answers to the focused question, still to swipe.
  final List<Answer> deck;

  /// The previous day's question id (null when this is the first ever).
  final String? prevQuestionId;
  final bool isFirst;

  /// Whether the focused question is today's.
  final bool isToday;

  final bool isSubmitting;

  /// True while loading a different day's question (chain navigation).
  final bool isNavigating;

  bool get hasQuestion => question != null;
  bool get hasAnswered => myAnswer != null;

  /// Today's question hides others' answers until you answer; past questions
  /// are an open reading archive.
  bool get isGated => isToday && !hasAnswered;

  QotdState copyWith({
    Question? question,
    Answer? myAnswer,
    int? totalAnswers,
    List<Answer>? deck,
    String? prevQuestionId,
    bool clearPrev = false,
    bool? isFirst,
    bool? isToday,
    bool? isSubmitting,
    bool? isNavigating,
  }) {
    return QotdState(
      question: question ?? this.question,
      myAnswer: myAnswer ?? this.myAnswer,
      totalAnswers: totalAnswers ?? this.totalAnswers,
      deck: deck ?? this.deck,
      prevQuestionId: clearPrev ? null : (prevQuestionId ?? this.prevQuestionId),
      isFirst: isFirst ?? this.isFirst,
      isToday: isToday ?? this.isToday,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isNavigating: isNavigating ?? this.isNavigating,
    );
  }

  static const QotdState empty = QotdState(
    question: null,
    myAnswer: null,
    totalAnswers: 0,
    deck: <Answer>[],
    prevQuestionId: null,
    isFirst: true,
    isToday: true,
    isSubmitting: false,
    isNavigating: false,
  );
}

// ─── Controller ───────────────────────────────────────────────────────────────

class QotdController extends AutoDisposeAsyncNotifier<QotdState> {
  final Set<String> _swipedThisSession = <String>{};

  QotdState _stateFrom(QotdDetail d, {required List<Answer> deck}) {
    return QotdState(
      question: d.question,
      myAnswer: d.myAnswer,
      totalAnswers: d.totalAnswers,
      deck: deck,
      prevQuestionId: d.prevQuestionId,
      isFirst: d.isFirst,
      isToday: d.isToday,
      isSubmitting: false,
      isNavigating: false,
    );
  }

  Future<List<Answer>> _deckFor(QotdDetail d) async {
    // Today's question is gated until the user answers; past questions read freely.
    if (d.question == null) return const <Answer>[];
    final gated = d.isToday && !d.hasAnswered;
    if (gated) return const <Answer>[];
    return ref.read(qotdRepositoryProvider).getDeck(questionId: d.question!.id, limit: 20);
  }

  @override
  Future<QotdState> build() async {
    final repo = ref.watch(qotdRepositoryProvider);
    try {
      final today = await repo.getToday();
      if (today.question == null) return QotdState.empty;
      final deck = await _deckFor(today);
      return _stateFrom(today, deck: deck);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return QotdState.empty;
      rethrow;
    }
  }

  /// Submit/update the answer for the focused question, then reveal its deck.
  Future<void> submitAnswer(String body) async {
    final current = state.valueOrNull;
    if (current?.question == null || current!.isSubmitting) return;

    state = AsyncData(current.copyWith(isSubmitting: true));
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final answer = await repo.submitAnswer(questionId: current.question!.id, body: body);
      final deck = await repo.getDeck(questionId: current.question!.id, limit: 20);

      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          myAnswer: answer,
          deck: deck,
          totalAnswers: latest.hasAnswered ? latest.totalAnswers : latest.totalAnswers + 1,
          isSubmitting: false,
        ),
      );
    } catch (e) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(isSubmitting: false));
      rethrow;
    }
  }

  /// Walk back to the previous day's question (the reading archive).
  Future<void> loadPrevious() async {
    final current = state.valueOrNull;
    final prevId = current?.prevQuestionId;
    if (current == null || prevId == null) return;
    await _loadQuestion(prevId);
  }

  /// Jump back to today's question.
  Future<void> goToToday() async {
    final current = state.valueOrNull;
    if (current == null || current.isToday) return;
    state = AsyncData(current.copyWith(isNavigating: true));
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final today = await repo.getToday();
      if (today.question == null) {
        state = AsyncData(QotdState.empty);
        return;
      }
      final deck = await _deckFor(today);
      state = AsyncData(_stateFrom(today, deck: deck));
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(isNavigating: false));
    }
  }

  Future<void> _loadQuestion(String questionId) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(isNavigating: true));
    }
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final detail = await repo.getQuestion(questionId);
      final deck = await _deckFor(detail);
      state = AsyncData(_stateFrom(detail, deck: deck));
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
    final newDeck = List<Answer>.of(current.deck)..removeAt(index);
    state = AsyncData(current.copyWith(deck: newDeck));

    if (newDeck.length <= 3 && current.question != null) {
      _refillDeck(questionId: current.question!.id, currentDeck: newDeck);
    }

    try {
      await ref.read(qotdRepositoryProvider).recordSwipe(answerId: answerId, direction: direction);
    } catch (_) {
      // Recorded locally; silent fail is acceptable.
    }
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
      // Guard against a race where the user navigated to another question.
      if (latest == null || latest.question?.id != questionId) return;
      state = AsyncData(latest.copyWith(deck: merged));
    } catch (_) {
      // Keep current deck on failure.
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
