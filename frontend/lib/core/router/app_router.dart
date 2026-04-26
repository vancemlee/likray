import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/providers/admin_providers.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/admin/presentation/screens/admin_login_screen.dart';
import '../../features/admin/presentation/screens/codes_screen.dart';
import '../../features/admin/presentation/screens/results_screen.dart';
import '../../features/admin/presentation/screens/sessions_screen.dart';
import '../../features/student/presentation/screens/code_entry_screen.dart';
import '../../features/student/presentation/screens/questionnaire_screen.dart';
import '../../features/student/presentation/screens/thank_you_screen.dart';

/// Провайдер GoRouter.
///
/// Важно: НЕ делаем `ref.watch(authNotifierProvider)` в теле провайдера —
/// иначе при смене auth-состояния весь GoRouter пересоздаётся, MaterialApp.router
/// получает новый router с `initialLocation: '/'` и сбрасывает маршрут,
/// из-за чего после успешного логина пользователя выкидывает на стартовый экран.
///
/// Вместо watch берём `notifier` через `ref.read` (один раз за жизнь провайдера)
/// и передаём его в `refreshListenable` — go_router сам перевычислит redirect
/// при каждом изменении состояния, не пересоздавая router.
/// Мост между Riverpod-провайдером и Flutter `Listenable`,
/// которого ждёт `go_router.refreshListenable`. StateNotifier из пакета
/// `state_notifier` сам по себе не является Flutter Listenable —
/// его API addListener имеет другую сигнатуру.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AuthState>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final isAdminArea = state.matchedLocation.startsWith('/admin');
      final isLoginPage = state.matchedLocation == '/admin/login';
      // Читаем актуальное состояние токена в момент работы redirect.
      final hasToken = ref.read(authNotifierProvider).adminToken != null;

      // 1) Зашли в админ-зону без токена → на логин
      if (isAdminArea && !isLoginPage && !hasToken) {
        return '/admin/login';
      }
      // 2) Уже залогинен и зашёл на форму логина → сразу на дашборд
      if (isLoginPage && hasToken) {
        return '/admin';
      }
      return null;
    },
    routes: [
      // ── Ученик ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        builder: (context, state) => const CodeEntryScreen(),
      ),
      GoRoute(
        path: '/questionnaire',
        builder: (context, state) => const QuestionnaireScreen(),
      ),
      GoRoute(
        path: '/thank-you',
        builder: (context, state) => const ThankYouScreen(),
      ),

      // ── Администратор ───────────────────────────────────────────────────
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/classes/:id/codes',
        builder: (context, state) {
          final classId = int.parse(state.pathParameters['id']!);
          return CodesScreen(classId: classId);
        },
      ),
      GoRoute(
        path: '/admin/sessions',
        builder: (context, state) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/admin/sessions/:id/results',
        builder: (context, state) {
          final sessionId = int.parse(state.pathParameters['id']!);
          return ResultsScreen(sessionId: sessionId);
        },
      ),
    ],
  );
});
