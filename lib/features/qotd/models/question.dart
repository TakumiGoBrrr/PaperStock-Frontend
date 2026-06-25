/// The daily prompt shown to everyone.
class Question {
  const Question({
    required this.id,
    required this.prompt,
    this.activeDate,
  });

  final String id;
  final String prompt;
  final String? activeDate;

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: (json['id'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      activeDate: json['active_date']?.toString(),
    );
  }
}
