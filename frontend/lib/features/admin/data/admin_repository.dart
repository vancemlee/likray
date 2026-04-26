import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exceptions.dart';
import '../domain/models/admin_login_response.dart';
import '../domain/models/class_model.dart';
import '../domain/models/results_model.dart';
import '../domain/models/voting_session_model.dart';

/// Абстракция репозитория администратора (нужна для подмены в тестах).
abstract class AdminRepository {
  Future<AdminLoginResponse> login(String username, String password);
  Future<List<ClassModel>> getClasses();
  Future<ClassModel> createClass(int grade, String letter);
  Future<List<String>> generateCodes(int classId, int count);
  Future<List<VotingSessionModel>> getSessions();
  Future<VotingSessionModel> createSession(int quarter, int year);
  Future<void> openSession(int sessionId);
  Future<void> closeSession(int sessionId);
  Future<ResultsModel> getResults(int sessionId);
}

/// Реализация через Dio → бэкенд FastAPI.
class AdminRepositoryImpl implements AdminRepository {
  final Dio _dio;

  const AdminRepositoryImpl(this._dio);

  /// Логин администратора.
  /// Бэк ожидает form data (OAuth2 PasswordRequestForm), не JSON!
  @override
  Future<AdminLoginResponse> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/auth/admin/login',
        data: {'username': username, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return AdminLoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ClassModel>> getClasses() async {
    try {
      final response = await _dio.get('/admin/classes');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ClassModel> createClass(int grade, String letter) async {
    try {
      final response = await _dio.post(
        '/admin/classes',
        data: {'grade': grade, 'letter': letter},
      );
      return ClassModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Сгенерировать N одноразовых кодов для класса.
  /// Возвращает коды в открытом виде (показываются один раз!).
  @override
  Future<List<String>> generateCodes(int classId, int count) async {
    try {
      final response = await _dio.post(
        '/admin/classes/$classId/codes/generate',
        data: {'count': count},
      );
      final list = response.data['codes'] as List<dynamic>;
      return list.map((e) => e as String).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<VotingSessionModel>> getSessions() async {
    try {
      final response = await _dio.get('/admin/voting-sessions');
      final list = response.data as List<dynamic>;
      return list
          .map((e) =>
              VotingSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<VotingSessionModel> createSession(int quarter, int year) async {
    try {
      final response = await _dio.post(
        '/admin/voting-sessions',
        data: {'quarter': quarter, 'year': year},
      );
      return VotingSessionModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> openSession(int sessionId) async {
    try {
      await _dio.post('/admin/voting-sessions/$sessionId/open');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> closeSession(int sessionId) async {
    try {
      await _dio.post('/admin/voting-sessions/$sessionId/close');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ResultsModel> getResults(int sessionId) async {
    try {
      final response =
          await _dio.get('/admin/voting-sessions/$sessionId/results');
      return ResultsModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Провайдер репозитория администратора.
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepositoryImpl(ref.read(dioProvider));
});
