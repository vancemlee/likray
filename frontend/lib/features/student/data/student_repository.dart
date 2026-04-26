import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exceptions.dart';
import '../domain/models/questionnaire.dart';
import '../domain/models/questionnaire_answer.dart';
import '../domain/models/redeem_response.dart';

/// Абстракция репозитория ученика (нужна для подмены в тестах).
abstract class StudentRepository {
  Future<RedeemResponse> redeemCode(String code);
  Future<ActiveVoteResponse> getActiveVote();
  Future<void> submitVote(QuestionnaireAnswers answers);
}

/// Реализация через Dio → бэкенд FastAPI.
class StudentRepositoryImpl implements StudentRepository {
  final Dio _dio;

  const StudentRepositoryImpl(this._dio);

  @override
  Future<RedeemResponse> redeemCode(String code) async {
    try {
      final response = await _dio.post(
        '/auth/student/redeem',
        data: {'code': code},
      );
      return RedeemResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ActiveVoteResponse> getActiveVote() async {
    try {
      final response = await _dio.get('/votes/active');
      return ActiveVoteResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> submitVote(QuestionnaireAnswers answers) async {
    try {
      await _dio.post('/votes', data: answers.toRequestJson());
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Провайдер репозитория ученика.
final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepositoryImpl(ref.read(dioProvider));
});
