/// Результаты голосования по сессии.
///
/// Бэк реализует защиту от деанонимизации малых выборок:
/// если в классе менее 5 голосов, возвращается `suppressed: true`
/// и агрегаты не передаются (`results: null`).
///
/// Формат бэка (упрощённо):
/// ```
/// {
///   "voting_session": { "id": 1, "quarter": 2, "year": 2025,
///                       "school_name": "...", "closed_at": "...",
///                       "total_votes": 42 },
///   "classes": [{
///     "class_id": 1, "class_name": "10А", "vote_count": 8,
///     "suppressed": false, "reason": null,
///     "results": { "heavy_subjects": {...}, "exams": {...}, ... }
///   }],
///   "school_totals": {...}
/// }
/// ```
class ResultsModel {
  final int votingSessionId;
  final int quarter;
  final int year;
  final String schoolName;
  final int totalVotes;
  final List<ClassResultsModel> classes;

  const ResultsModel({
    required this.votingSessionId,
    required this.quarter,
    required this.year,
    required this.schoolName,
    required this.totalVotes,
    required this.classes,
  });

  factory ResultsModel.fromJson(Map<String, dynamic> json) {
    final meta = (json['voting_session'] as Map<String, dynamic>?) ?? const {};
    final rawClasses = json['classes'] as List<dynamic>? ?? const [];
    return ResultsModel(
      votingSessionId: (meta['id'] as int?) ?? 0,
      quarter: (meta['quarter'] as int?) ?? 0,
      year: (meta['year'] as int?) ?? 0,
      schoolName: (meta['school_name'] as String?) ?? '',
      totalVotes: (meta['total_votes'] as int?) ?? 0,
      classes: rawClasses
          .map((e) => ClassResultsModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Результат одного класса.
class ClassResultsModel {
  final int classId;
  final String className;
  final int voteCount;

  /// true — данных недостаточно (n < 5), показываем серую плашку.
  /// На бэке это поле называется `suppressed`.
  final bool hiddenDueToSmallCount;

  /// Агрегированные ответы по блокам (null при hiddenDueToSmallCount=true).
  /// На бэке это поле называется `results`.
  final Map<String, dynamic>? aggregates;

  const ClassResultsModel({
    required this.classId,
    required this.className,
    required this.voteCount,
    required this.hiddenDueToSmallCount,
    this.aggregates,
  });

  factory ClassResultsModel.fromJson(Map<String, dynamic> json) {
    return ClassResultsModel(
      classId: json['class_id'] as int,
      className: json['class_name'] as String,
      voteCount: json['vote_count'] as int,
      hiddenDueToSmallCount: json['suppressed'] as bool? ?? false,
      aggregates: json['results'] as Map<String, dynamic>?,
    );
  }
}
