/// Класс школы (например, «10В»).
class ClassModel {
  final int id;
  final String name;
  final int schoolId;

  const ClassModel({
    required this.id,
    required this.name,
    required this.schoolId,
  });

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id'] as int,
      name: json['name'] as String,
      schoolId: json['school_id'] as int,
    );
  }
}
