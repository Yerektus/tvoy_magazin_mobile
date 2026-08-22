import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/auth_user.dart';
import 'token_storage.dart';

/// Кто вошёл и чем ходит в API.
///
/// Единственное место, где живут токены: клиент только спрашивает их отсюда.
/// Токенов два — короткий access в каждом запросе и refresh на месяц; когда
/// первый протухает, второй меняется на новую пару.
class Auth extends ChangeNotifier {
  Auth({required ApiClient api, TokenStorage? storage})
    : _api = api,
      _storage = storage ?? TokenStorage() {
    _api.bind(token: () => _access, refresh: _exchange);
  }

  final ApiClient _api;
  final TokenStorage _storage;

  String? _access;
  String? _refresh;
  AuthUser? _user;
  bool _restoring = true;

  AuthUser? get user => _user;
  bool get isAuthenticated => _access != null;

  /// Пока читаем сохранённый вход, показывать форму рано — иначе она мигнёт
  /// у того, кто уже вошёл.
  bool get isRestoring => _restoring;

  /// Обновление, которое уже идёт.
  ///
  /// Запросов на экране несколько, и протухший токен они получают разом. Без
  /// общего обещания каждый пошёл бы обновляться сам, а из-за ротации на
  /// сервере выжил бы только первый — остальные предъявили бы уже погашенный
  /// refresh и выкинули бы человека на вход.
  Future<String?>? _refreshing;

  /// Поднимает сохранённый вход при запуске.
  Future<void> restore() async {
    final saved = await _storage.read();

    _access = saved.access;
    _refresh = saved.refresh;
    _user = saved.user;
    _restoring = false;
    notifyListeners();

    // Роль и организация могли смениться, пока приложение было закрыто.
    if (_access != null) {
      unawaited(reload());
    }
  }

  Future<void> signIn(String email, String password) async {
    final body =
        await _api.post('/auth/login/', {
              'email': email.trim(),
              'password': password,
            })
            as Map<String, dynamic>;

    _access = body['access'] as String;
    _refresh = body['refresh'] as String;
    _user = AuthUser.fromJson(Map<String, dynamic>.from(body['user'] as Map));

    await _storage.saveTokens(_access!, _refresh!);
    await _storage.saveUser(_user!);
    notifyListeners();
  }

  /// Перечитывает профиль с сервера: в хранилище он такой, каким был при входе.
  Future<void> reload() async {
    try {
      final body = await _api.get('/auth/me/') as Map<String, dynamic>;
      _user = AuthUser.fromJson(body);
      await _storage.saveUser(_user!);
      notifyListeners();
    } on ApiException {
      // Токен протух — этим займётся обновление, здесь молчим.
    }
  }

  /// Выход. Гасим refresh на сервере, чтобы им не воспользовались после нас.
  Future<void> signOut() async {
    final refresh = _refresh;
    await _forget();

    if (refresh == null) {
      return;
    }

    try {
      await _api.post('/auth/logout/', {'refresh': refresh});
    } on ApiException {
      // Сервер недоступен или токен уже недействителен — локально мы всё равно
      // вышли, и держать человека в аккаунте из-за этого незачем.
    }
  }

  Future<String?> _exchange() {
    return _refreshing ??= _swapTokens().whenComplete(() => _refreshing = null);
  }

  Future<String?> _swapTokens() async {
    final refresh = _refresh;

    if (refresh == null) {
      return null;
    }

    try {
      final body =
          await _api.post('/auth/refresh/', {'refresh': refresh})
              as Map<String, dynamic>;

      _access = body['access'] as String;
      // Сервер поворачивает refresh при каждом обмене; на всякий случай
      // оставляем прежний, если нового не прислали.
      _refresh = (body['refresh'] as String?) ?? refresh;
      await _storage.saveTokens(_access!, _refresh!);
      notifyListeners();

      return _access;
    } on ApiException {
      // Протух, погашен или подделан — восстановить нечего.
      await _forget();
      return null;
    }
  }

  Future<void> _forget() async {
    _access = null;
    _refresh = null;
    _user = null;
    await _storage.clear();
    notifyListeners();
  }
}
