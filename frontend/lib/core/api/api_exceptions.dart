import 'package:dio/dio.dart';

/// Унифицированное исключение API.
/// Содержит HTTP-статус, machine-readable код из бэка и читаемое сообщение.
class ApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException[$statusCode/$code]: $message';
}

// ---------------------------------------------------------------------------
// Коды ошибок, которые возвращает бэк (из detail.code)
// ---------------------------------------------------------------------------

const String kCodeNotFound = 'CODE_NOT_FOUND';
const String kCodeAlreadyUsed = 'CODE_ALREADY_USED';
const String kNoActiveSession = 'NO_ACTIVE_SESSION';
const String kSessionClosed = 'SESSION_CLOSED';
const String kInvalidCredentials = 'INVALID_CREDENTIALS';
const String kUnauthorized = 'UNAUTHORIZED';
const String kNetworkError = 'NETWORK_ERROR';
const String kUnknownError = 'UNKNOWN_ERROR';

// ---------------------------------------------------------------------------
// Маппинг DioException → ApiException
// ---------------------------------------------------------------------------

/// Преобразует DioException в типизированный ApiException.
/// Разбирает формат бэка: {"detail": {"code": "...", "message": "..."}}.
ApiException mapDioException(DioException e) {
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionTimeout) {
    return const ApiException(
      code: kNetworkError,
      message: 'Нет связи с сервером. Проверьте подключение к интернету.',
    );
  }

  final response = e.response;
  if (response == null) {
    return ApiException(
      code: kUnknownError,
      message: e.message ?? 'Неизвестная ошибка',
      statusCode: null,
    );
  }

  // Пробуем разобрать {"detail": {"code": "...", "message": "..."}}
  final data = response.data;
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is Map<String, dynamic>) {
      return ApiException(
        code: detail['code'] as String? ?? kUnknownError,
        message: detail['message'] as String? ?? 'Ошибка сервера',
        statusCode: response.statusCode,
      );
    }
    // FastAPI может вернуть detail как строку (например, 422 validation)
    if (detail is String) {
      return ApiException(
        code: kUnknownError,
        message: detail,
        statusCode: response.statusCode,
      );
    }
  }

  return ApiException(
    code: kUnknownError,
    message: 'Ошибка сервера (${response.statusCode})',
    statusCode: response.statusCode,
  );
}

/// Преобразует код ошибки API в понятное русское сообщение для ученика.
String studentFriendlyError(ApiException e) {
  switch (e.code) {
    case kCodeNotFound:
      return 'Код не найден. Проверьте правильность ввода.';
    case kCodeAlreadyUsed:
      return 'Этот код уже был использован. Каждый код работает один раз.';
    case kNoActiveSession:
      return 'Голосование сейчас не открыто. Обратитесь к классному руководителю.';
    case kSessionClosed:
      return 'Сессия голосования уже закрыта.';
    case kNetworkError:
      return 'Нет связи с сервером. Проверьте интернет и попробуйте снова.';
    default:
      return e.message;
  }
}
