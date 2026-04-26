/// Ответ на POST /auth/admin/login.
class AdminLoginResponse {
  final String accessToken;

  const AdminLoginResponse({required this.accessToken});

  factory AdminLoginResponse.fromJson(Map<String, dynamic> json) {
    return AdminLoginResponse(
      accessToken: json['access_token'] as String,
    );
  }
}
