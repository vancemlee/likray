import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

/// Базовый URL API.
///
/// Резолвится в таком порядке:
/// 1. Compile-time `--dart-define=API_BASE_URL=...` (для локальной разработки
///    и кастомных деплоев);
/// 2. Иначе — относительный путь `/api/v1`. На web-Static-Site Render фронт
///    отдают с того же origin, что и бэк (через `routes` rewrite в render.yaml),
///    поэтому относительного пути достаточно.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '/api/v1',
);

/// Провайдер Dio-клиента (singleton).
/// Настроен с таймаутами 10 секунд и Auth-интерцептором.
final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.read(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(AuthInterceptor(tokenStorage));

  // В debug-режиме логируем запросы (убрать в production)
  assert(() {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[Dio] $obj'),
    ));
    return true;
  }());

  return dio;
});
