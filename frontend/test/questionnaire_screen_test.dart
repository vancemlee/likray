import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:likray/features/student/data/student_repository.dart';
import 'package:likray/features/student/domain/models/questionnaire.dart';
import 'package:likray/features/student/domain/models/questionnaire_answer.dart';
import 'package:likray/features/student/domain/models/redeem_response.dart';
import 'package:likray/features/student/presentation/screens/questionnaire_screen.dart';

// ---------------------------------------------------------------------------
// Мок-репозиторий, возвращающий заготовленную анкету
// ---------------------------------------------------------------------------

final _fakeQuestionnaire = {
  'version': 'v1',
  'blocks': [
    {
      'key': 'heavy_subjects',
      'title': 'Тяжёлые предметы',
      'description': 'Выберите время',
      'type': 'subjects_time',
      'subjects': [
        {'key': 'math', 'label': 'Математика'},
        {'key': 'physics', 'label': 'Физика'},
        {'key': 'chemistry', 'label': 'Химия'},
        {'key': 'cs', 'label': 'Информатика'},
        {'key': 'foreign_language', 'label': 'Иностранный язык'},
      ],
      'options': [
        {'value': 'lessons_1_2', 'label': '1–2 урок'},
        {'value': 'lessons_3_4', 'label': '3–4 урок'},
        {'value': 'lessons_5_6', 'label': '5–6 урок'},
        {'value': 'any', 'label': 'Не важно'},
      ],
    },
    {
      'key': 'exams',
      'title': 'Контрольные по дням недели',
      'type': 'exams',
      'fields': [],
    },
    {
      'key': 'free_periods',
      'title': 'Окна в расписании',
      'type': 'free_periods',
      'options': [
        {'value': 'max_1', 'label': 'Максимум 1 окно'},
        {'value': 'max_3', 'label': 'До 3 окон'},
        {'value': 'any', 'label': 'Не важно'},
      ],
      'extra_field': {
        'key': 'prefer_long',
        'label': 'Лучше одно длинное',
        'type': 'checkbox',
      },
    },
    {
      'key': 'pe',
      'title': 'Физкультура',
      'type': 'radio',
      'options': [
        {'value': 'first', 'label': 'Первым уроком'},
        {'value': 'last', 'label': 'Последним уроком'},
        {'value': 'middle', 'label': 'В середине дня'},
        {'value': 'any', 'label': 'Не важно'},
      ],
    },
    {
      'key': 'free_text',
      'title': 'Свободное пожелание (необязательно)',
      'type': 'text',
      'max_length': 280,
      'placeholder': 'Напиши пожелание...',
    },
  ],
};

class _MockStudentRepository implements StudentRepository {
  @override
  Future<RedeemResponse> redeemCode(String code) => throw UnimplementedError();

  @override
  Future<ActiveVoteResponse> getActiveVote() async {
    return ActiveVoteResponse(
      votingSessionId: 1,
      quarter: 2,
      year: 2025,
      className: '10В',
      questionnaire: _fakeQuestionnaire,
    );
  }

  @override
  Future<void> submitVote(QuestionnaireAnswers answers) async {}
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

Widget _wrapWithRouter(Widget child, {StudentRepository? repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
        path: '/thank-you',
        builder: (_, __) => const Scaffold(body: Text('Спасибо')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (repo != null) studentRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('QuestionnaireScreen', () {
    testWidgets('показывает индикатор загрузки', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          const QuestionnaireScreen(),
          repo: _MockStudentRepository(),
        ),
      );
      // До завершения Future — показываем CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('рендерит все 5 блоков анкеты', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          const QuestionnaireScreen(),
          repo: _MockStudentRepository(),
        ),
      );
      await tester.pumpAndSettle();

      // Все 5 заголовков блоков должны быть видны
      expect(find.text('Тяжёлые предметы'), findsOneWidget);
      expect(find.text('Контрольные по дням недели'), findsOneWidget);
      expect(find.text('Окна в расписании'), findsOneWidget);
      expect(find.text('Физкультура'), findsOneWidget);
      expect(find.text('Свободное пожелание (необязательно)'), findsOneWidget);
    });

    testWidgets('кнопка «Отправить голос» присутствует', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          const QuestionnaireScreen(),
          repo: _MockStudentRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('submit_vote_button')), findsOneWidget);
    });

    testWidgets('блок heavy_subjects показывает все предметы', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          const QuestionnaireScreen(),
          repo: _MockStudentRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Математика'), findsOneWidget);
      expect(find.text('Физика'), findsOneWidget);
      expect(find.text('Химия'), findsOneWidget);
      expect(find.text('Информатика'), findsOneWidget);
      expect(find.text('Иностранный язык'), findsOneWidget);
    });
  });
}
