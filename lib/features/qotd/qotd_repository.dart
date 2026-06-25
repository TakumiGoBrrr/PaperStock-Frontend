import 'package:dio/dio.dart';

import 'models/answer.dart';
import 'models/question.dart';

class QotdToday {
  const QotdToday({
    required this.question,
    required this.myAnswer,
    required this.hasAnswered,
    required this.totalAnswers,
  });

  final Question? question;
  final Answer? myAnswer;
  final bool hasAnswered;
  final int totalAnswers;
}

class QotdRepository {
  QotdRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<QotdToday> getToday() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/qotd/today');
    final body = response.data ?? const <String, dynamic>{};

    final questionJson = body['question'];
    final myAnswerJson = body['my_answer'];

    return QotdToday(
      question: (questionJson is Map<String, dynamic>)
          ? Question.fromJson(questionJson)
          : null,
      myAnswer: (myAnswerJson is Map<String, dynamic>)
          ? Answer.fromJson(myAnswerJson)
          : null,
      hasAnswered: body['has_answered'] == true,
      totalAnswers: (body['total_answers'] is num)
          ? (body['total_answers'] as num).toInt()
          : 0,
    );
  }

  Future<Answer> submitAnswer(String answerBody) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/qotd/today/answer',
      data: <String, dynamic>{'body': answerBody},
    );
    return Answer.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<Answer>> getDeck({int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/qotd/today/deck',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    final body = response.data ?? const <String, dynamic>{};
    final answers = (body['answers'] is List)
        ? (body['answers'] as List)
        : const <dynamic>[];
    return answers
        .whereType<Map<String, dynamic>>()
        .map(Answer.fromJson)
        .toList(growable: false);
  }

  Future<void> recordSwipe({
    required String answerId,
    required String direction,
  }) async {
    await _dio.post<void>(
      '/api/v1/qotd/answers/$answerId/swipe',
      data: <String, dynamic>{'direction': direction},
    );
  }

  Future<void> reportAnswer({
    required String answerId,
    required String reason,
  }) async {
    await _dio.post<void>(
      '/api/v1/qotd/answers/$answerId/report',
      data: <String, dynamic>{'reason': reason},
    );
  }

  /// Records that the current user opened a `?ref=` challenge link.
  Future<void> redeemChallenge({
    required String questionId,
    required String ref,
  }) async {
    try {
      await _dio.post<void>(
        '/api/v1/qotd/challenge/redeem',
        data: <String, dynamic>{'question_id': questionId, 'ref': ref},
      );
    } catch (_) {
      // Attribution is best-effort; never block the user.
    }
  }
}
