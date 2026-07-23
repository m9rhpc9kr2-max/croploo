import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.email,
    required this.username,
    required this.name,
  });

  final String accessToken;
  final String email;
  final String username;
  final String name;
}

/// Talks to the Node/Express backend's `/v1/auth` endpoints.
class AuthApi {
  AuthApi({
    this.baseUrl = 'https://croploo-backend-78230737866.europe-west1.run.app/v1',
  });

  final String baseUrl;

  /// Starts registration: creates the (unverified) account and sends an
  /// 8-digit code to [email]. Call [verifyEmail] with that code to finish.
  Future<void> register({
    required String email,
    required String username,
    required String password,
    required String name,
    String? referralCode,
  }) =>
      _post('register', {
        'email': email,
        'username': username,
        'password': password,
        'name': name,
        if (referralCode != null && referralCode.trim().isNotEmpty)
          'referral_code': referralCode.trim(),
      });

  Future<AuthResult> verifyEmail({
    required String email,
    required String code,
  }) =>
      _authPost('verify-email', {'email': email, 'code': code});

  Future<void> resendCode(String email) => _post('resend-code', {'email': email});

  /// [emailOrUsername] is matched against either field server-side, so
  /// users don't have to remember which one they signed up with.
  Future<AuthResult> login({
    required String emailOrUsername,
    required String password,
  }) =>
      _authPost('login', {'email': emailOrUsername, 'password': password});

  /// Starts the reset flow: sends an 8-digit code to the account's email
  /// if [emailOrUsername] matches one, silently no-ops otherwise (never
  /// reveals whether an account exists). Returns the account's email
  /// (needed for [resetPassword]) when a match was found, else null.
  Future<String?> forgotPassword(String emailOrUsername) async {
    final json = await _post('forgot-password', {'email_or_username': emailOrUsername});
    return json['email'] as String?;
  }

  Future<AuthResult> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _authPost('reset-password', {
        'email': email,
        'code': code,
        'new_password': newPassword,
      });

  /// Validates a previously stored [accessToken] and fetches the current
  /// user — used to restore a session on app startup without showing the
  /// login screen. Throws [AuthException] if the token is missing/expired.
  Future<AuthResult> me(String accessToken) async {
    final http.Response res;
    try {
      res = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } catch (_) {
      throw AuthException('Cannot reach Croploo backend at $baseUrl');
    }
    if (res.statusCode != 200) {
      throw AuthException('Session expired');
    }
    final user = jsonDecode(res.body) as Map<String, dynamic>;
    return AuthResult(
      accessToken: accessToken,
      email: user['email'] as String,
      username: (user['username'] ?? '') as String,
      name: (user['name'] ?? '') as String,
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await http.post(
        Uri.parse('$baseUrl/auth/$path'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw AuthException('Cannot reach Croploo backend at $baseUrl');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw AuthException(json['detail'] as String? ?? 'Request failed');
    }
    return json;
  }

  Future<AuthResult> _authPost(String path, Map<String, dynamic> body) async {
    final json = await _post(path, body);
    final user = json['user'] as Map<String, dynamic>;
    return AuthResult(
      accessToken: json['access_token'] as String,
      email: user['email'] as String,
      username: (user['username'] ?? '') as String,
      name: (user['name'] ?? '') as String,
    );
  }
}
