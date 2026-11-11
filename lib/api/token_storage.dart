import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  StoredSession({
    required this.token,
    required this.refreshToken,
    required this.name,
    required this.userId,
  });

  final String token;
  final String refreshToken;
  final String name;
  // Null for sessions stored before it was kept; filled in on the next refresh.
  final String? userId;
}

class TokenStorage {
  TokenStorage._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  // Kept alongside the tokens so a restart can go straight to the home screen,
  // which greets the user by name, without a round trip to the API first.
  static const _nameKey = 'user_name';
  static const _userIdKey = 'user_id';

  static Future<void> save({
    required String token,
    required String refreshToken,
    required String name,
    required String userId,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _nameKey, value: name);
    await _storage.write(key: _userIdKey, value: userId);
  }

  // After a profile edit — the tokens themselves don't change.
  static Future<void> saveName(String name) => _storage.write(key: _nameKey, value: name);

  static Future<String?> readUserId() => _storage.read(key: _userIdKey);

  static Future<String?> readToken() => _storage.read(key: _tokenKey);

  static Future<String?> readRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  // Null unless there's a complete session to resume.
  static Future<StoredSession?> readSession() async {
    final token = await _storage.read(key: _tokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final name = await _storage.read(key: _nameKey);
    if (token == null || refreshToken == null || name == null) return null;
    return StoredSession(
      token: token,
      refreshToken: refreshToken,
      name: name,
      userId: await _storage.read(key: _userIdKey),
    );
  }

  static Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _userIdKey);
  }
}
