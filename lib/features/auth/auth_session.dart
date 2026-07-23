import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in user's access token, captured from the login window's
/// hand-off payload when the dashboard window is created. Null when
/// running without the login flow (e.g. plain `flutter run` during
/// development).
class AuthSession {
  const AuthSession({
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

final authSessionProvider = StateProvider<AuthSession?>((ref) => null);
