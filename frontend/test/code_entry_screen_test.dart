import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:likray/features/student/data/student_repository.dart';
import 'package:likray/features/student/domain/models/questionnaire.dart';
import 'package:likray/features/student/domain/models/questionnaire_answer.dart';
import 'package:likray/features/student/domain/models/redeem_response.dart';
import 'package:likray/features/student/presentation/screens/code_entry_screen.dart';

// ---------------------------------------------------------------------------
// Мок-репозиторий для тестов
// ---------------------------------------------------------------------------

class _FakeStudentRepository implements StudentRepository {
  final bool shouldFail;
  final String? errorCode;

  const _FakeStudentRepository({
    this.shouldFail = false,
    this.errorCode,
  });

  @override
  Future<RedeemResponse> redeemCode(String code) async {
    if (shouldFail) {
      throw Exception('network error');
    }
    return const RedeemResponse(
      accessToken: 'fake_token',
      votingSessionId: 1,
      className: '10В',
    );
  }

  @override
  Future<ActiveVoteResponse> getActiveVote() async =>
      throw UnimplementedError();

  @override
  Future<void> submitVote(QuestionnaireAnswers answers) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Хелпер: оборачиваем виджет в минимальный роутер для go_router
// ---------------------------------------------------------------------------

Widget _wrapWithRouter(Widget child, {StudentRepository? repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
        path: '/questionnaire',
        builder: (_, __) => const Scaffold(body: Text('Анкета')),
      ),
      GoRoute(
        path: '/admin/login',
        builder: (_, __) => const Scaffold(body: Text('Логин')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (repo != null)
        studentRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

void main() {
  group('CodeEntryScreen', () {
    testWidgets('рендерится корректно', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(const CodeEntryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Likray'), findsOneWidget);
      expect(find.byKey(const Key('submit_button')), findsOneWidget);
    });

    testWidgets('кнопка «Войти» disabled когда поле пустое', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(const CodeEntryScreen()),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_button')),
      );
      // onPressed == null ↔ кнопка disabled
      expect(button.onPressed, isNull);
    });

    testWidgets('кнопка «Войти» enabled когда поле заполнено', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(const CodeEntryScreen()),
      );
      await tester.pumpAndSettle();

      // Вводим код в TextField
      await tester.enterText(find.byType(TextField).first, 'ABCD1234');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('показывает ошибку при неверном коде', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          const CodeEntryScreen(),
          repo: const _FakeStudentRepository(shouldFail: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'BADCODE');
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();

      // Должно появиться сообщение об ошибке
      expect(find.textContaining('Что-то пошло'), findsOneWidget);
    });
  });
}
