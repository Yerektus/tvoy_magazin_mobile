import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_config.dart';

/// Адрес бэкенда зависит от того, где приложение запущено, и однажды уже был
/// не тем: сборка уходила на `10.0.2.2` — особый адрес эмулятора, которого на
/// живом телефоне не существует, — и просто висела.
void main() {
  test('в браузере — местный бэкенд, на телефоне — боевой', () {
    if (kIsWeb) {
      expect(apiBaseUrl, 'http://127.0.0.1:8000/api');
    } else {
      expect(
        apiBaseUrl,
        'https://tvoymagazinapi-production.up.railway.app/api',
      );
    }
  });

  test('адрес кончается на /api и без косой черты', () {
    // Клиент склеивает пути как `$apiBaseUrl/invoices/` — лишняя черта дала бы
    // `//invoices/`, а Django на такое отвечает 404.
    expect(apiBaseUrl, endsWith('/api'));
  });

  test('на телефоне ходим по https', () {
    // Android с девятой версии рвёт открытый http, и разрешение на него стоит
    // только в отладочной сборке.
    if (!kIsWeb) {
      expect(apiBaseUrl, startsWith('https://'));
    }
  });
}
