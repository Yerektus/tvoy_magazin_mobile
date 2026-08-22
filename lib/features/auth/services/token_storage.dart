import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

/// Где лежат токены между запусками. Ключи те же, что на вебе, — так проще
/// сверяться, когда что-то не сходится.
class TokenStorage {
  static const _access = 'tm.access';
  static const _refresh = 'tm.refresh';
  static const _user = 'tm.user';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<({String? access, String? refresh, AuthUser? user})> read() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_user);

    return (
      access: prefs.getString(_access),
      refresh: prefs.getString(_refresh),
      user: raw == null ? null : _user_(raw),
    );
  }

  Future<void> saveTokens(String access, String refresh) async {
    final prefs = await _prefs;
    await prefs.setString(_access, access);
    await prefs.setString(_refresh, refresh);
  }

  Future<void> saveUser(AuthUser user) async {
    final prefs = await _prefs;
    await prefs.setString(_user, jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await Future.wait([
      prefs.remove(_access),
      prefs.remove(_refresh),
      prefs.remove(_user),
    ]);
  }

  /// Разбитый профиль — не повод не пустить в приложение: токен важнее, а
  /// профиль дочитается с сервера.
  AuthUser? _user_(String raw) {
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
