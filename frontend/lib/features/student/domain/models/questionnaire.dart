/// Ответ на GET /votes/active.
/// Содержит информацию об активной сессии + структуру анкеты v1.
///
/// Структура questionnaire хранится как сырой Map, поскольку Flutter
/// рендерит её динамически по полю "type" каждого блока.
/// Это позволяет бэку добавлять новые типы блоков без изменения клиента.
class ActiveVoteResponse {
  final int votingSessionId;
  final int quarter;
  final int year;
  final String className;

  /// Структура анкеты v1 — список блоков из QUESTIONNAIRE_V1 бэка.
  /// Ключ "blocks" — List<Map>, каждый блок содержит "key", "title", "type".
  final Map<String, dynamic> questionnaire;

  const ActiveVoteResponse({
    required this.votingSessionId,
    required this.quarter,
    required this.year,
    required this.className,
    required this.questionnaire,
  });

  factory ActiveVoteResponse.fromJson(Map<String, dynamic> json) {
    return ActiveVoteResponse(
      votingSessionId: json['voting_session_id'] as int,
      quarter: json['quarter'] as int,
      year: json['year'] as int,
      className: json['class_name'] as String,
      questionnaire: json['questionnaire'] as Map<String, dynamic>,
    );
  }

  /// Список блоков анкеты в удобном виде.
  List<Map<String, dynamic>> get blocks {
    final raw = questionnaire['blocks'];
    if (raw == null) return const [];
    return List<Map<String, dynamic>>.from(raw as List);
  }

  String get quarterLabel => '$quarter четверть $year года';
}
