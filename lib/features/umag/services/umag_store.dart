import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/umag_account.dart';

/// Подключение к UMAG и выбранный магазин.
///
/// Живёт отдельно от списка накладных: накладные принадлежат организации, а
/// кабинет UMAG — конкретному сотруднику, и у каждого он свой.
class UmagAccountStore extends ChangeNotifier {
  UmagAccountStore({required ApiClient api}) : _api = api;

  final ApiClient _api;

  UmagAccount _account = UmagAccount.empty;
  bool _busy = false;

  UmagAccount get account => _account;

  /// Идёт смена магазина: на это время выбор запирается, чтобы два запроса не
  /// разошлись и в кабинете не оказался тот магазин, который выбрали первым.
  bool get isBusy => _busy;

  /// Читает состояние. Молча: сайдбар не место для сообщений об ошибках, а без
  /// кабинета UMAG приложение остаётся рабочим — просто без выбора магазина.
  Future<void> load() async {
    try {
      final body = await _api.get('/umag/account/') as Map<String, dynamic>;
      _account = UmagAccount.fromJson(body);
      notifyListeners();
    } on ApiException {
      _account = UmagAccount.empty;
      notifyListeners();
    }
  }

  /// Меняет магазин. Ошибку отдаём наверх: этот выбор человек сделал руками и
  /// должен узнать, если он не прижился.
  Future<void> select(int storeId) async {
    if (_busy || storeId == _account.storeId) {
      return;
    }

    _busy = true;
    notifyListeners();

    try {
      final body =
          await _api.patch('/umag/account/', {'store_id': storeId})
              as Map<String, dynamic>;
      _account = UmagAccount.fromJson(body);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Вышли из приложения — состояние чужого кабинета помнить незачем.
  void forget() {
    _account = UmagAccount.empty;
    notifyListeners();
  }
}
