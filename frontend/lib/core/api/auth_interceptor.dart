import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// Перехватчик Dio, автоматически добавляющий Bearer-токен в Authorization.
///
/// Логика выбора токена:
///   — пути /admin/** (кроме /auth/admin/login) → admin_token
///   — все остальные пути → student_token
///
/// Если нужный токен отсутствует — заголовок не добавляется
/// (бэк сам вернёт 401, если путь требует аутентификации).
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;

  AuthInterceptor(this._tokenStorage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;
    // /auth/admin/login — публичный эндпоинт, токен не нужен
    final isPublic =
        path == '/auth/student/redeem' || path == '/auth/admin/login';

    if (!isPublic) {
      String? token;
      if (path.startsWith('/admin/')) {
        token = await _tokenStorage.readAdminToken();
      } else {
        // /votes/active, POST /votes
        token = await _tokenStorage.readStudentToken();
      }
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }
}
