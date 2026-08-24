import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/chat_message.dart';

/// Переписка с аналитиком.
///
/// Историю держит сервер: разговор продолжается с телефона и из кабинета, а
/// на устройстве ему храниться незачем.
class AssistantStore extends ChangeNotifier {
  AssistantStore({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<ChatMessage> _messages = const [];
  bool _loading = false;
  bool _thinking = false;
  String? _error;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _loading;

  /// Вопрос ушёл, ответа ещё нет. Отдельно от загрузки истории: пока аналитик
  /// думает, переписку видно, и мигать ей незачем.
  bool get isThinking => _thinking;

  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _messages = _parse(await _api.get('/assistant/chat/'));
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
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
      final fresh = _parse(
        await _api.post('/assistant/chat/', {'text': question}),
      );
      _messages = [..._messages.sublist(0, _messages.length - 1), ...fresh];
    } finally {
      _thinking = false;
      notifyListeners();
    }
  }

  /// Начать разговор заново.
  Future<void> clear() async {
    await _api.delete('/assistant/chat/');
    _messages = const [];
    notifyListeners();
  }

  List<ChatMessage> _parse(dynamic body) {
    final rows = (body as Map<String, dynamic>)['messages'] as List;

    return rows
        .map(
          (row) => ChatMessage.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
