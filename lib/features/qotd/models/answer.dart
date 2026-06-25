/// A user's answer to a daily question.
class Answer {
  const Answer({
    required this.id,
    required this.questionId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.heartsCount,
    required this.isHearted,
    required this.createdAt,
    this.moderationStatus = 'approved',
  });

  final String id;
  final String questionId;
  final String authorId;
  final String authorName;
  final String body;
  final int heartsCount;
  final bool isHearted;
  final DateTime createdAt;
  final String moderationStatus;

  Answer copyWith({int? heartsCount, bool? isHearted}) {
    return Answer(
      id: id,
      questionId: questionId,
      authorId: authorId,
      authorName: authorName,
      body: body,
      heartsCount: heartsCount ?? this.heartsCount,
      isHearted: isHearted ?? this.isHearted,
      createdAt: createdAt,
    );
  }

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      id: (json['id'] ?? '').toString(),
      questionId: (json['question_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      heartsCount: (json['hearts_count'] is num)
          ? (json['hearts_count'] as num).toInt()
          : int.tryParse((json['hearts_count'] ?? '0').toString()) ?? 0,
      isHearted: json['is_hearted'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      moderationStatus: (json['moderation_status'] ?? 'approved').toString(),
    );
  }
}
