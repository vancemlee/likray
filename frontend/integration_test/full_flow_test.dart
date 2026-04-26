/// Integration-тест: полный флоу ученика через ProviderScope override.
/// Без реального HTTP — только мок-репозиторий и in-memory токен-хранилище.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';

import 'package:likray/app.dart';
import 'package:likray/core/storage/token_storage.dart';
import 'package:likray/features/student/data/student_repository.dart';
import 'package:likray/features/student/domain/models/questionnaire.dart';
import 'package:likray/features/student/domain/models/questionnaire_answer.dart';
import 'package:likray/features/student/domain/models/redeem_response.dart';

// In-memory замена secure_storage — не нужен Keychain
class _FakeTokenStorage extends TokenStorage {
  final _map = <String, String>{};
  _FakeTokenStorage() : super(const FlutterSecureStorage());

  @override Future<void> saveStudentToken(String t) async => _map['s'] = t;
  @override Future<String?> readStudentToken() async => _map['s'];
  @override Future<void> deleteStudentToken() async => _map.remove('s');
  @override Future<void> saveAdminToken(String t) async => _map['a'] = t;
  @override Future<String?> readAdminToken() async => _map['a'];
  @override Future<void> deleteAdminToken() async => _map.remove('a');
}

// Мок-репозиторий с захардкоженными ответами
class _FakeStudentRepo implements StudentRepository {
  @override
  Future<RedeemResponse> redeemCode(String code) async =>
      const RedeemResponse(accessToken: 'tok', votingSessionId: 1, className: '10В');

  @override
  Future<ActiveVoteResponse> getActiveVote() async => ActiveVoteResponse(
        votingSessionId: 1, quarter: 2, year: 2025, className: '10В',
        questionnaire: {
          'version': 'v1',
          'blocks': [
            {'key': 'heavy_subjects', 'title': 'Тяжёлые предметы', 'description': '',
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
               {'value': 'any', 'label': 'Не важно'},
             ]},
            {'key': 'exams', 'title': 'Контрольные', 'type': 'exams', 'fields': []},
            {'key': 'free_periods', 'title': 'Окна', 'type': 'free_periods',
             'options': [{'value': 'any', 'label': 'Не важно'}],
             'extra_field': {'key': 'prefer_long', 'label': 'Длинное', 'type': 'checkbox'}},
            {'key': 'pe', 'title': 'Физкультура', 'type': 'radio',
             'options': [{'value': 'any', 'label': 'Не важно'}]},
            {'key': 'free_text', 'title': 'Свободное пожелание (необязательно)',
             'type': 'text', 'max_length': 280, 'placeholder': '...'},
          ],
        },
      );

  @override
  Future<void> submitVote(QuestionnaireAnswers a) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full student flow: ввод кода → анкета → спасибо', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        studentRepositoryProvider.overrideWithValue(_FakeStudentRepo()),
      ],
      child: const LikrayApp(),
    ));
    await tester.pumpAndSettle();

    // Экран ввода кода
    expect(find.text('Likray'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ANYCODE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    // Экран анкеты — все 5 заголовков блоков
    expect(find.text('Тяжёлые предметы'), findsOneWidget);
    expect(find.text('Контрольные'), findsOneWidget);
    expect(find.text('Окна'), findsOneWidget);
    expect(find.text('Физкультура'), findsOneWidget);
    expect(find.text('Свободное пожелание (необязательно)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('submit_vote_button')));
    await tester.pumpAndSettle();

    // Экран спасибо
    expect(find.text('Спасибо!'), findsOneWidget);

    // Возврат на главную
    await tester.tap(find.byKey(const Key('home_button')));
    await tester.pumpAndSettle();
    expect(find.text('Likray'), findsOneWidget);
  });
}
