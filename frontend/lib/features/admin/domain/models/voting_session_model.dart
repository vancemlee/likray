/// Сессия голосования (четверть + год + статус).
class VotingSessionModel {
  final int id;
  final int quarter;
  final int year;
  final bool isOpen;
  final int schoolId;

  const VotingSessionModel({
    required this.id,
    required this.quarter,
    required this.year,
    required this.isOpen,
    required this.schoolId,
  });

  factory VotingSessionModel.fromJson(Map<String, dynamic> json) {
    return VotingSessionModel(
      id: json['id'] as int,
      quarter: json['quarter'] as int,
      year: json['year'] as int,
      isOpen: json['is_open'] as bool,
      schoolId: json['school_id'] as int,
    );
  }

  String get label => '$quarter четверть $year';

  String get statusLabel => isOpen ? 'Открыто' : 'Закрыто';
}
