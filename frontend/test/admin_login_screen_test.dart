import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:likray/features/admin/presentation/screens/admin_login_screen.dart';
import 'package:likray/features/admin/data/admin_repository.dart';
import 'package:likray/features/admin/domain/models/admin_login_response.dart';
import 'package:likray/features/admin/domain/models/class_model.dart';
import 'package:likray/features/admin/domain/models/results_model.dart';
import 'package:likray/features/admin/domain/models/voting_session_model.dart';

// ---------------------------------------------------------------------------
// Мок-репозиторий
// ---------------------------------------------------------------------------

class _MockAdminRepository implements AdminRepository {
  final bool loginSuccess;

  const _MockAdminRepository({this.loginSuccess = true});

  @override
  Future<AdminLoginResponse> login(String username, String password) async {
    if (!loginSuccess) {
      throw Exception('invalid credentials');
    }
    return const AdminLoginResponse(accessToken: 'admin_fake_token');
  }

  @override
  Future<List<ClassModel>> getClasses() async => [];

  @override
  Future<ClassModel> createClass(int grade, String letter) async =>
      ClassModel(id: 1, name: '$grade$letter', schoolId: 1);

  @override
  Future<List<String>> generateCodes(int classId, int count) async => [];

  @override
  Future<List<VotingSessionModel>> getSessions() async => [];

  @override
  Future<VotingSessionModel> createSession(int quarter, int year) async =>
      VotingSessionModel(
        id: 1,
        quarter: quarter,
        year: year,
        isOpen: false,
        schoolId: 1,
      );

  @override
  Future<void> openSession(int sessionId) async {}

  @override
  Future<void> closeSession(int sessionId) async {}

  @override
  Future<ResultsModel> getResults(int sessionId) async => const ResultsModel(
        votingSessionId: 0,
        quarter: 0,
        year: 0,
        schoolName: '',
        totalVotes: 0,
        classes: [],
      );
}

// ---------------------------------------------------------------------------
// Хелпер
// ---------------------------------------------------------------------------

Widget _wrapWithRouter(Widget child) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/admin/login', builder: (_, __) => child),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const Scaffold(body: Text('Dashboard')),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Главная')),
      ),
    ],
    initialLocation: '/admin/login',
  );

  return ProviderScope(
    overrides: [
      adminRepositoryProvider.overrideWithValue(
        const _MockAdminRepository(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

void main() {
  group('AdminLoginScreen', () {
    testWidgets('рендерится с полями логина и пароля', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const AdminLoginScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('username_field')), findsOneWidget);
      expect(find.byKey(const Key('password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_button')), findsOneWidget);
    });

    testWidgets('валидация: пустой логин показывает ошибку поля', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const AdminLoginScreen()));
      await tester.pumpAndSettle();

      // Нажимаем кнопку без заполнения полей
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Введите логин'), findsOneWidget);
    });

    testWidgets('валидация: пустой пароль показывает ошибку поля', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const AdminLoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('username_field')),
        'admin',
      );
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Введите пароль'), findsOneWidget);
    });

    testWidgets('кнопка «Войти» активна когда поля заполнены', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const AdminLoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('username_field')),
        'admin',
      );
      await tester.enterText(
        find.byKey(const Key('password_field')),
        'secret',
      );

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('login_button')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
