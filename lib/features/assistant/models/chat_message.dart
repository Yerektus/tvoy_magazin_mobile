/// Реплика в переписке с аналитиком.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int,
    mine: json['role'] == 'user',
    text: (json['text'] ?? '') as String,
    createdAt: DateTime.tryParse(
      (json['created_at'] ?? '') as String,
    )?.toLocal(),
  );

  final int id;

  /// Наша реплика или ответ аналитика.
  final bool mine;

  final String text;
  final DateTime? createdAt;
}

/// Переписка в истории: чем была и когда в ней говорили последний раз.
///
/// Без реплик: список их не показывает, а тянуть все разговоры целиком ради
/// двух строк на экране незачем.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
    id: json['id'] as int,
    title: (json['title'] ?? '') as String,
    updatedAt: DateTime.tryParse(
      (json['updated_at'] ?? '') as String,
    )?.toLocal(),
  );

  final int id;

  /// Первый вопрос переписки — по нему её и вспоминают.
  final String title;

  final DateTime? updatedAt;

  /// Название для списка. Пустое бывает у переписки из одного фото без слов.
  String get name => title.isEmpty ? 'Без названия' : title;
}

/// Когда реплику отправили — так, как это подписывают в переписке.
///
/// Сегодняшним хватает времени: день и так «сегодня». У вчерашних и старше
/// нужна дата, иначе «14:32» под ответом ничего не говорит. Год пишем только
/// у прошлогодних: в этом он всюду один и тот же.
String formatSentAt(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final shift = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(day).inDays;
  final time = '${_two(date.hour)}:${_two(date.minute)}';

  if (shift == 0) {
    return time;
  }

  if (shift == 1) {
    return 'вчера, $time';
  }

  final year = date.year == today.year ? '' : ' ${date.year}';

  return '${date.day} ${_months[date.month - 1]}$year, $time';
}

/// Месяцы в родительном падеже: «18 августа», а не «18 август».
const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String _two(int value) => value.toString().padLeft(2, '0');
