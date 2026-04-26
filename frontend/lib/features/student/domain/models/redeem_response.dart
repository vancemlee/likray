/// Ответ на POST /auth/student/redeem.
/// Содержит анонимный JWT (без user_id) + мета-данные сессии.
class RedeemResponse {
  final String accessToken;
  final int votingSessionId;
  final String className;

  const RedeemResponse({
    required this.accessToken,
    required this.votingSessionId,
    required this.className,
  });

  factory RedeemResponse.fromJson(Map<String, dynamic> json) {
    return RedeemResponse(
      accessToken: json['access_token'] as String,
      votingSessionId: json['voting_session_id'] as int,
      className: json['class_name'] as String,
    );
  }
}
