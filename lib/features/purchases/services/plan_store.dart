import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/plan.dart';

/// План закупа по выбранному магазину.
///
/// План живёт на сервере и считается по товарному отчёту UMAG: одним запросом
/// оттуда приходят и продажи за период, и остаток на сейчас. Здесь мы его
/// только читаем и просим пересчитать.
class PlanStore extends ChangeNotifier {
  PlanStore({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Plan? _plan;
  bool _loading = false;
  bool _connected = false;
  String? _error;

  Plan? get plan => _plan;
  bool get isLoading => _loading;

  /// Подключено ли расширение «Планирование закупов». Подключают его в
  /// веб-кабинете и только владелец с администратором — с телефона нечего и
  /// предлагать, поэтому просто говорим, что оно выключено.
  bool get isConnected => _connected;

  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final access =
          await _api.get('/purchases/access/') as Map<String, dynamic>;
      _connected = (access['connected'] ?? false) as bool;

      if (_connected) {
        final body = await _api.get('/purchases/plan/');
        // Плана ещё нет — сервер отвечает пустотой, и это не ошибка.
        _plan = body == null
            ? null
            : Plan.fromJson(body as Map<String, dynamic>);
      }
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Считает план заново. Прежний сервер удаляет — планов по магазину один.
  Future<void> rebuild({int? days, int? horizon}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final body =
          await _api.post('/purchases/plan/', {
                'days': ?days,
                'horizon': ?horizon,
              })
              as Map<String, dynamic>;

      _plan = Plan.fromJson(body);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
