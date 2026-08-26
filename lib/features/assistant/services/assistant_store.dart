import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/chat_message.dart';

/// Переписки с аналитиком: открытая и все прошлые.
///
/// Историю держит сервер: разговор продолжается с телефона и из кабинета, а на
/// устройстве ему храниться незачем.
class AssistantStore extends ChangeNotifier {
  AssistantStore({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<ChatMessage> _messages = const [];
  List<ChatSummary> _chats = const [];

  /// Какая переписка открыта. `null` — новая: на сервере её ещё нет, она
  /// заведётся вместе с первым вопросом.
  int? _chatId;

  /// Следующий вопрос начинает новую переписку, а не продолжает последнюю.
  /// Нужно только между «начать заново» и первым вопросом.
  bool _fresh = false;

  bool _loading = false;
  bool _thinking = false;
  String? _error;

  List<ChatMessage> get messages => _messages;

  /// История: свежие сверху. Перечитывается по `loadHistory`, а не сама —
  /// список нужен, только когда его открыли.
  List<ChatSummary> get chats => _chats;

  int? get chatId => _chatId;
  bool get isLoading => _loading;

  /// Вопрос ушёл, ответа ещё нет. Отдельно от загрузки истории: пока аналитик
  /// думает, переписку видно, и мигать ей незачем.
  bool get isThinking => _thinking;

  String? get error => _error;

  /// Открывает переписку, в которой говорили последней.
  Future<void> load() => _open('/assistant/chat/');

  /// Открывает переписку из истории.
  Future<void> openChat(int id) => _open('/assistant/chats/$id/');

  Future<void> _open(String path) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _take(await _api.get(path));
      _fresh = false;
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Начать разговор заново.
  ///
  /// Ничего не спрашиваем у сервера: пустая переписка ему не нужна, а нажал и
  /// передумал — в истории не должно остаться строки без единой реплики. Новая
  /// заведётся сама вместе с первым вопросом.
  void startNew() {
    _messages = const [];
    _chatId = null;
    _fresh = true;
    _error = null;
    notifyListeners();
  }

  /// Читает историю переписок.
  Future<void> loadHistory() async {
    final body = await _api.get('/assistant/chats/') as Map<String, dynamic>;

    _chats = (body['chats'] as List)
        .map(
          (row) => ChatSummary.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    notifyListeners();
  }

  /// Убирает переписку из истории. Если убрали открытую — на экране остаётся
  /// новая: показывать реплики того, чего уже нет, нельзя.
  Future<void> remove(int id) async {
    await _api.delete('/assistant/chats/$id/');
    _chats = _chats.where((chat) => chat.id != id).toList();

    if (_chatId == id) {
      _messages = const [];
      _chatId = null;
      _fresh = true;
    }

    notifyListeners();
  }

  /// Задаёт вопрос. Реплику показываем сразу, не дожидаясь ответа: аналитик
  /// думает секунды, и всё это время человек должен видеть, что его услышали.
  Future<void> ask(String text) async {
    final question = text.trim();

    if (question.isEmpty || _thinking) {
      return;
    }

    _messages = [
      ..._messages,
      ChatMessage(id: 0, mine: true, text: question, createdAt: DateTime.now()),
    ];
    _thinking = true;
    notifyListeners();

    try {
      // Сервер возвращает вопрос и ответ вместе — своей временной репликой
      // заменяем обе, чтобы у вопроса появился настоящий id.
      final shown = _messages.sublist(0, _messages.length - 1);
      final body =
          await _api.post('/assistant/chat/', {
                'text': question,
                if (_chatId != null) 'chat': _chatId,
                if (_fresh) 'fresh': true,
              })
              as Map<String, dynamic>;

      _chatId = (body['chat'] as Map?)?['id'] as int?;
      _fresh = false;
      _messages = [...shown, ..._parse(body)];
    } finally {
      _thinking = false;
      notifyListeners();
    }
  }

  /// Забирает из ответа сервера и реплики, и то, какая переписка открыта.
  void _take(dynamic body) {
    final map = body as Map<String, dynamic>;

    _chatId = (map['chat'] as Map?)?['id'] as int?;
    _messages = _parse(map);
  }

  List<ChatMessage> _parse(Map<String, dynamic> body) {
    return (body['messages'] as List)
        .map(
          (row) => ChatMessage.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
