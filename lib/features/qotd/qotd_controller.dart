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
    required this.isSubmitting,
  });

  final Question? question;
  final Answer? myAnswer;
  final int totalAnswers;

  /// Other users' answers still to swipe. Index 0 is the top card.
  final List<Answer> deck;

  final bool isSubmitting;

  bool get hasQuestion => question != null;
  bool get hasAnswered => myAnswer != null;

  QotdState copyWith({
    Question? question,
    Answer? myAnswer,
    int? totalAnswers,
    List<Answer>? deck,
    bool? isSubmitting,
  }) {
    return QotdState(
      question: question ?? this.question,
      myAnswer: myAnswer ?? this.myAnswer,
      totalAnswers: totalAnswers ?? this.totalAnswers,
      deck: deck ?? this.deck,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  static const QotdState empty = QotdState(
    question: null,
    myAnswer: null,
    totalAnswers: 0,
    deck: <Answer>[],
    isSubmitting: false,
  );
}

// ─── Controller ───────────────────────────────────────────────────────────────

class QotdController extends AutoDisposeAsyncNotifier<QotdState> {
  /// Answers swiped this session — prevents a concurrent refill from re-adding
  /// an answer before the server has recorded the swipe.
  final Set<String> _swipedThisSession = <String>{};

  @override
  Future<QotdState> build() async {
    final repo = ref.watch(qotdRepositoryProvider);
    try {
      final today = await repo.getToday();
      if (today.question == null) {
        return QotdState.empty;
      }

      // Only load other people's answers once the user has answered.
      final deck = today.hasAnswered
          ? await repo.getDeck(limit: 20)
          : const <Answer>[];

      return QotdState(
        question: today.question,
        myAnswer: today.myAnswer,
        totalAnswers: today.totalAnswers,
        deck: deck,
        isSubmitting: false,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return QotdState.empty;
      }
      rethrow;
    }
  }

  /// Submit (or update) the current user's answer, then load the answer deck.
  Future<void> submitAnswer(String body) async {
    final current = state.valueOrNull;
    if (current == null || current.isSubmitting) return;

    state = AsyncData(current.copyWith(isSubmitting: true));

    try {
      final repo = ref.read(qotdRepositoryProvider);
      final answer = await repo.submitAnswer(body);
      final deck = await repo.getDeck(limit: 20);

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

  /// Optimistically remove the top answer card and record the swipe.
  Future<void> swipe({required String answerId, required String direction}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final index = current.deck.indexWhere((a) => a.id == answerId);
    if (index < 0) return;

    _swipedThisSession.add(answerId);
    final newDeck = List<Answer>.of(current.deck)..removeAt(index);
    state = AsyncData(current.copyWith(deck: newDeck));

    if (newDeck.length <= 3) {
      _refillDeck(currentDeck: newDeck);
    }

    try {
      final repo = ref.read(qotdRepositoryProvider);
      await repo.recordSwipe(answerId: answerId, direction: direction);
    } catch (_) {
      // Swipe is recorded locally; silent fail is acceptable.
    }
  }

  Future<void> _refillDeck({required List<Answer> currentDeck}) async {
    try {
      final repo = ref.read(qotdRepositoryProvider);
      final fresh = await repo.getDeck(limit: 20);
      final existingIds = currentDeck.map((a) => a.id).toSet();
      final merged = <Answer>[
        ...currentDeck,
        ...fresh.where((a) =>
            !existingIds.contains(a.id) && !_swipedThisSession.contains(a.id)),
      ];
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(latest.copyWith(deck: merged));
    } catch (_) {
      // Keep the current deck on failure.
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
