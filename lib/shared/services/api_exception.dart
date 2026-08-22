/// Ошибка, текст которой можно показать человеку.
///
/// DRF отвечает по-разному — то `detail`, то список ошибок поля, — поэтому
/// разбор ответа собран в одном месте, а наружу идёт готовая строка.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Токен протух или его не приняли — это лечится входом заново.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}
