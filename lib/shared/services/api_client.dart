import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_config.dart';
import 'api_exception.dart';

/// Файл для отправки формой.
class UploadFile {
  const UploadFile({
    required this.field,
    required this.filename,
    required this.bytes,
    required this.contentType,
  });

  final String field;
  final String filename;
  final List<int> bytes;
  final String contentType;
}

/// Один HTTP-клиент на приложение: подставляет токен и переводит ответы DRF
/// в понятные ошибки.
///
/// Токен клиент не хранит и не обновляет — он спрашивает его у того, кто
/// подключил, и сообщает ему же, что пора обновиться. Так `Auth` остаётся
/// единственным местом, где живут токены, а клиент не знает про экраны.
class ApiClient {
  ApiClient({http.Client? inner}) : _http = inner ?? http.Client();

  final http.Client _http;

  /// Откуда брать access-токен и как получить свежий, когда прежний протух.
  String? Function()? _token;
  Future<String?> Function()? _refresh;

  void bind({
    required String? Function() token,
    required Future<String?> Function() refresh,
  }) {
    _token = token;
    _refresh = refresh;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send((token) => _http.get(_uri(path, query), headers: _headers(token)));

  Future<dynamic> post(String path, Object body) => _send(
        (token) => _http.post(
          _uri(path, null),
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> patch(String path, Object body) => _send(
        (token) => _http.patch(
          _uri(path, null),
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> delete(String path) =>
      _send((token) => _http.delete(_uri(path, null), headers: _headers(token)));

  /// Отправляет файлы как обычную форму — так их ждёт `POST /api/invoices/`.
  ///
  /// `files` — пары «имя поля, файл». Одно и то же имя можно повторять: так
  /// уходят листы накладной, которых бывает больше одного.
  ///
  /// Тело собирается заново на каждую попытку: поток запроса одноразовый, и
  /// повторить тот же `MultipartRequest` после обновления токена нельзя.
  Future<dynamic> upload(String path, List<UploadFile> files) {
    return _send((token) async {
      final request = http.MultipartRequest('POST', _uri(path, null))
        ..headers.addAll(_headers(token))
        ..files.addAll(
          files.map(
            (file) => http.MultipartFile.fromBytes(
              file.field,
              file.bytes,
              filename: file.filename,
              // Без честного content-type http шлёт application/octet-stream, а
              // сервер отвечает «нужен JPEG, PNG, WEBP, HEIC или PDF» — снимок
              // теряется за этой надписью, потому что вины файла в ней нет.
              contentType: MediaType.parse(file.contentType),
            ),
          ),
        );

      return http.Response.fromStream(await request.send());
    });
  }

  /// Шлёт запрос и, если access протух, меняет его и повторяет — но ровно один
  /// раз: если и со свежим токеном пришёл 401, дело не в сроке годности.
  Future<dynamic> _send(
    Future<http.Response> Function(String? token) request,
  ) async {
    var response = await _run(() => request(_token?.call()));

    if (response.statusCode == 401 && _refresh != null) {
      final fresh = await _refresh!();

      if (fresh != null) {
        response = await _run(() => request(fresh));
      }
    }

    return _parse(response);
  }

  Future<http.Response> _run(Future<http.Response> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException('Сервер недоступен. Проверьте, запущен ли API.');
    }
  }

  Uri _uri(String path, Map<String, String>? query) =>
      Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers(String? token) => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _parse(http.Response response) {
    final body = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      _message(body) ?? 'Ошибка сервера. Попробуйте позже.',
      statusCode: response.statusCode,
    );
  }

  /// Ответ DRF → строка для человека. Сперва общий `detail` и `non_field_errors`
  /// — как на вебе, — а не нашлось и их, берём ошибку первого поля формы: имя
  /// поля зависит от ручки (`email`, `password`, `image` при загрузке фото),
  /// и перечислять их все здесь смысла нет — DRF всегда возвращает один и тот
  /// же вид ответа.
  String? _message(dynamic body) {
    final direct = _text(body);
    if (direct != null) {
      return direct;
    }

    if (body is! Map) {
      return null;
    }

    for (final key in ['detail', 'non_field_errors']) {
      final text = _text(body[key]);
      if (text != null) {
        return text;
      }
    }

    for (final value in body.values) {
      final text = _text(value);
      if (text != null) {
        return text;
      }
    }

    return null;
  }

  String? _text(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }

    if (value is List && value.isNotEmpty && value.first is String) {
      return value.first as String;
    }

    return null;
  }
}
