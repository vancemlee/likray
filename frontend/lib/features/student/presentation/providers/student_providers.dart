import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/student_repository.dart';
import '../../domain/models/questionnaire.dart';
import '../../domain/models/questionnaire_answer.dart';

// ---------------------------------------------------------------------------
// Провайдер активной анкеты
// ---------------------------------------------------------------------------

/// Загружает структуру и мета-данные активного голосования через JWT ученика.
/// AutoDispose — освобождает ресурсы при уходе с экрана анкеты.
final activeVoteProvider =
    FutureProvider.autoDispose<ActiveVoteResponse>((ref) {
  return ref.watch(studentRepositoryProvider).getActiveVote();
});

// ---------------------------------------------------------------------------
// Провайдер/нотифайер состояния ответов
// ---------------------------------------------------------------------------

/// Хранит текущее состояние ответов ученика на анкету.
/// При уходе с экрана сбрасывается (autoDispose).
final surveyAnswersProvider = StateNotifierProvider.autoDispose<
    SurveyAnswersNotifier, QuestionnaireAnswers>(
  (ref) => SurveyAnswersNotifier(),
);

class SurveyAnswersNotifier extends StateNotifier<QuestionnaireAnswers> {
  SurveyAnswersNotifier() : super(QuestionnaireAnswers.initial());

  void setHeavySubject(String subjectKey, String value) {
    final updated = Map<String, String>.from(state.heavySubjects);
    updated[subjectKey] = value;
    state = state.copyWith(heavySubjects: updated);
  }

  void setExamsMaxPerDay(int value) {
    state = state.copyWith(examsMaxPerDay: value);
  }

  void setExamsNoMonFri(bool value) {
    state = state.copyWith(examsNoMonFri: value);
  }

  void setFreePeriodsChoice(String value) {
    state = state.copyWith(freePeriodsChoice: value);
  }

  void setFreePeriodsPreferLong(bool value) {
    state = state.copyWith(freePeriodsPreferLong: value);
  }

  void setPEPreference(String value) {
    state = state.copyWith(pePreference: value);
  }

  void setFreeText(String? value) {
    if (value == null || value.isEmpty) {
      state = state.copyWith(clearFreeText: true);
    } else {
      state = state.copyWith(freeText: value);
    }
  }
}

// ---------------------------------------------------------------------------
// Провайдер отправки голоса
// ---------------------------------------------------------------------------

/// AsyncNotifier для отправки голоса (один раз на сессию).
final voteSubmitProvider =
    AsyncNotifierProvider.autoDispose<VoteSubmitNotifier, void>(
  VoteSubmitNotifier.new,
);

class VoteSubmitNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit(QuestionnaireAnswers answers) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(studentRepositoryProvider).submitVote(answers),
    );
  }
}
