/// Состояние ответов ученика на анкету v1.
///
/// Поля соответствуют схеме SurveyAnswers на бэке.
/// Дефолтные значения — нейтральные "any" / средние числа,
/// чтобы кнопка «Отправить» могла быть активна сразу,
/// если ученик не хочет выражать предпочтений.
class QuestionnaireAnswers {
  // --- Блок 1: Тяжёлые предметы ---
  // ключ предмета → значение: 'lessons_1_2' | 'lessons_3_4' | 'lessons_5_6' | 'any'
  final Map<String, String> heavySubjects;

  // --- Блок 2: Контрольные ---
  final int examsMaxPerDay;    // 1..4
  final bool examsNoMonFri;

  // --- Блок 3: Окна ---
  final String freePeriodsChoice; // 'max_1' | 'max_3' | 'any'
  final bool freePeriodsPreferLong;

  // --- Блок 4: Физкультура ---
  final String pePreference; // 'first' | 'last' | 'middle' | 'any'

  // --- Блок 5: Свободный текст (опционально) ---
  final String? freeText;

  const QuestionnaireAnswers({
    Map<String, String>? heavySubjects,
    this.examsMaxPerDay = 2,
    this.examsNoMonFri = false,
    this.freePeriodsChoice = 'any',
    this.freePeriodsPreferLong = false,
    this.pePreference = 'any',
    this.freeText,
  }) : heavySubjects = heavySubjects ?? const {};

  /// Начальное состояние: все предметы = 'any'.
  factory QuestionnaireAnswers.initial() {
    return QuestionnaireAnswers(
      heavySubjects: {
        'math': 'any',
        'physics': 'any',
        'chemistry': 'any',
        'cs': 'any',
        'foreign_language': 'any',
      },
    );
  }

  /// Все обязательные поля заполнены.
  bool get isValid {
    const requiredSubjects = [
      'math', 'physics', 'chemistry', 'cs', 'foreign_language'
    ];
    for (final s in requiredSubjects) {
      if (!heavySubjects.containsKey(s)) return false;
    }
    return examsMaxPerDay >= 1 && examsMaxPerDay <= 4;
  }

  /// Сериализация в тело запроса POST /votes.
  Map<String, dynamic> toRequestJson() {
    return {
      'answers': {
        'heavy_subjects': Map<String, dynamic>.from(heavySubjects),
        'exams': {
          'max_per_day': examsMaxPerDay,
          'no_mon_fri': examsNoMonFri,
        },
        'free_periods': {
          'choice': freePeriodsChoice,
          'prefer_long': freePeriodsPreferLong,
        },
        'pe': {
          'preference': pePreference,
        },
        if (freeText != null && freeText!.isNotEmpty) 'free_text': freeText,
      },
    };
  }

  QuestionnaireAnswers copyWith({
    Map<String, String>? heavySubjects,
    int? examsMaxPerDay,
    bool? examsNoMonFri,
    String? freePeriodsChoice,
    bool? freePeriodsPreferLong,
    String? pePreference,
    String? freeText,
    bool clearFreeText = false,
  }) {
    return QuestionnaireAnswers(
      heavySubjects: heavySubjects ?? Map.from(this.heavySubjects),
      examsMaxPerDay: examsMaxPerDay ?? this.examsMaxPerDay,
      examsNoMonFri: examsNoMonFri ?? this.examsNoMonFri,
      freePeriodsChoice: freePeriodsChoice ?? this.freePeriodsChoice,
      freePeriodsPreferLong:
          freePeriodsPreferLong ?? this.freePeriodsPreferLong,
      pePreference: pePreference ?? this.pePreference,
      freeText: clearFreeText ? null : (freeText ?? this.freeText),
    );
  }
}
