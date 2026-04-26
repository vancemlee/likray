import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/token_storage.dart';
import '../../data/admin_repository.dart';
import '../../domain/models/admin_login_response.dart';
import '../../domain/models/class_model.dart';
import '../../domain/models/results_model.dart';
import '../../domain/models/voting_session_model.dart';

// ---------------------------------------------------------------------------
// Auth-состояние администратора
// ---------------------------------------------------------------------------

class AuthState {
  final String? adminToken;

  const AuthState({this.adminToken});

  bool get isAuthenticated => adminToken != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final TokenStorage _storage;

  AuthNotifier(this._storage) : super(const AuthState());

  /// Загружает токен из secure_storage при старте приложения.
  Future<void> initialize() async {
    final token = await _storage.readAdminToken();
    state = AuthState(adminToken: token);
  }

  Future<void> setToken(String token) async {
    await _storage.saveAdminToken(token);
    state = AuthState(adminToken: token);
  }

  Future<void> logout() async {
    await _storage.deleteAdminToken();
    state = const AuthState();
  }
}

/// Глобальный провайдер auth-состояния администратора.
/// Используется в go_router для redirect-логики.
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(tokenStorageProvider));
});

// ---------------------------------------------------------------------------
// Провайдер логина администратора
// ---------------------------------------------------------------------------

final adminLoginProvider =
    AsyncNotifierProvider.autoDispose<AdminLoginNotifier, void>(
  AdminLoginNotifier.new,
);

class AdminLoginNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      final AdminLoginResponse result = await repo.login(username, password);
      await ref.read(authNotifierProvider.notifier).setToken(result.accessToken);
    });
  }
}

// ---------------------------------------------------------------------------
// Провайдеры данных (классы, сессии, результаты)
// ---------------------------------------------------------------------------

final adminClassesProvider =
    FutureProvider.autoDispose<List<ClassModel>>((ref) {
  return ref.watch(adminRepositoryProvider).getClasses();
});

final adminSessionsProvider =
    FutureProvider.autoDispose<List<VotingSessionModel>>((ref) {
  return ref.watch(adminRepositoryProvider).getSessions();
});

final adminResultsProvider =
    FutureProvider.autoDispose.family<ResultsModel, int>((ref, sessionId) {
  return ref.watch(adminRepositoryProvider).getResults(sessionId);
});

// ---------------------------------------------------------------------------
// Провайдер генерации кодов
// ---------------------------------------------------------------------------

final generateCodesProvider =
    AsyncNotifierProvider.autoDispose<GenerateCodesNotifier, List<String>>(
  GenerateCodesNotifier.new,
);

class GenerateCodesNotifier extends AutoDisposeAsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async => [];

  Future<void> generate(int classId, int count) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).generateCodes(classId, count),
    );
  }
}

// ---------------------------------------------------------------------------
// Провайдер создания класса
// ---------------------------------------------------------------------------

final createClassProvider =
    AsyncNotifierProvider.autoDispose<CreateClassNotifier, ClassModel?>(
  CreateClassNotifier.new,
);

class CreateClassNotifier extends AutoDisposeAsyncNotifier<ClassModel?> {
  @override
  Future<ClassModel?> build() async => null;

  Future<ClassModel?> create(int grade, String letter) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).createClass(grade, letter),
    );
    return state.value;
  }
}

// ---------------------------------------------------------------------------
// Провайдер управления сессиями
// ---------------------------------------------------------------------------

final sessionActionProvider =
    AsyncNotifierProvider.autoDispose<SessionActionNotifier, void>(
  SessionActionNotifier.new,
);

class SessionActionNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> openSession(int sessionId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).openSession(sessionId),
    );
  }

  Future<void> closeSession(int sessionId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).closeSession(sessionId),
    );
  }
}

// ---------------------------------------------------------------------------
// Провайдер создания сессии голосования
// ---------------------------------------------------------------------------

final createSessionProvider =
    AsyncNotifierProvider.autoDispose<CreateSessionNotifier, VotingSessionModel?>(
  CreateSessionNotifier.new,
);

class CreateSessionNotifier
    extends AutoDisposeAsyncNotifier<VotingSessionModel?> {
  @override
  Future<VotingSessionModel?> build() async => null;

  Future<VotingSessionModel?> create(int quarter, int year) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).createSession(quarter, year),
    );
    return state.value;
  }
}
