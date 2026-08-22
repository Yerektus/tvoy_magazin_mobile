/// Снятый лист накладной, готовый к отправке.
///
/// Тип файла носим рядом с байтами, а не выводим на месте: снимок с камеры
/// всегда JPEG, а из галереи приходит и PNG, и HEIC — соврать про формат
/// значит нарваться на отказ сервера «нужен JPEG, PNG, WEBP, HEIC или PDF».
class Shot {
  const Shot({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final List<int> bytes;
  final String filename;
  final String contentType;
}
