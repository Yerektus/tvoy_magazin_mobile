import 'package:flutter/material.dart';

/// Статусы разбора накладной на бэкенде.
enum DocumentStatus {
  pending('В очереди', Icons.schedule, Color(0xFF737373)),
  processing('Распознаётся', Icons.autorenew, Color(0xFF0284C7)),
  done('Готово', Icons.check_circle_outline, Color(0xFF059669)),
  checked('Проверено', Icons.verified_outlined, Color(0xFF059669)),
  failed('Ошибка', Icons.error_outline, Color(0xFFDC2626));

  const DocumentStatus(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static DocumentStatus parse(String? raw) => values.firstWhere(
        (status) => status.name == raw,
        orElse: () => DocumentStatus.pending,
      );
}

/// Накладная в списке. Полей ровно столько, сколько показывает список: карточку
/// документа мобильное приложение пока не открывает.
class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.status,
    required this.supplier,
    required this.number,
    required this.issuedAt,
    required this.total,
    required this.linesCount,
    required this.createdAt,
  });

  factory DocumentItem.fromJson(Map<String, dynamic> json) => DocumentItem(
        id: json['id'] as int,
        status: DocumentStatus.parse(json['status'] as String?),
        supplier: (json['supplier'] ?? '') as String,
        number: (json['number'] ?? '') as String,
        issuedAt: _date(json['issued_at'] as String?),
        // Деньги приходят строкой: у DecimalField нет точного двойника в JSON.
        total: _decimal(json['total'] as String?),
        linesCount: (json['lines_count'] ?? 0) as int,
        createdAt: _date(json['created_at'] as String?),
      );

  final int id;
  final DocumentStatus status;
  final String supplier;
  final String number;
  final DateTime? issuedAt;
  final double? total;
  final int linesCount;
  final DateTime? createdAt;

  /// Заголовок строки: номер накладной, а пока его не прочитали — дата.
  String get title {
    if (number.isNotEmpty) {
      return 'Накладная №$number';
    }

    final date = issuedAt ?? createdAt;
    return date == null ? 'Накладная' : 'Накладная от ${formatDate(date)}';
  }

  String get supplierOrDash =>
      supplier.isEmpty ? 'Поставщик не распознан' : supplier;

  static DateTime? _date(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toLocal();

  static double? _decimal(String? raw) => raw == null ? null : double.tryParse(raw);
}

/// Количество без лишних нулей: «1.000» → «1», «8.290» → «8.29».
/// Число для поля ввода: без хвостовых нулей и без прочерка.
///
/// От [formatQuantity] отличается пустотой вместо «—»: в поле правят то, что
/// потом уйдёт на сервер, и прочерк там значил бы, что человеку надо сначала
/// стереть тире, а если не сотрёт — отправить его как число.
String numberForInput(double? value) => value == null ? '' : formatQuantity(value);

String formatQuantity(double? quantity) {
  if (quantity == null) {
    return '—';
  }

  final text = quantity.toStringAsFixed(3);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'\.?0+$'), '')
      : text;
}

String formatDate(DateTime date) =>
    '${_two(date.day)}.${_two(date.month)}.${date.year}';

/// Дата и время загрузки — то, что показывает список вместо числа позиций:
/// его видно и так по самим строкам, а вот когда накладную сняли, не видно
/// нигде больше.
String formatDateTime(DateTime date) =>
    '${formatDate(date)}, ${_two(date.hour)}:${_two(date.minute)}';

/// Только время: дату в списке несёт заголовок дня, и повторять её в каждой
/// строке значит тратить место на то, что и так написано выше.
String formatTime(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

/// Заголовок дня в списке: «ЧТ 21 АВГУСТА», а для сегодня и вчера — словами.
///
/// Своего дня недели и месяца в родительном падеже у `intl` для русского нет в
/// нужном виде, а тянуть локали ради двух списков ни к чему.
String formatDayHeader(DateTime date, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final start = DateTime(now.year, now.month, now.day);
  final shift = start.difference(day).inDays;

  if (shift == 0) {
    return 'СЕГОДНЯ';
  }

  if (shift == 1) {
    return 'ВЧЕРА';
  }

  final weekday = _weekdays[date.weekday - 1];
  final month = _months[date.month - 1];
  final year = date.year == now.year ? '' : ' ${date.year}';

  return '$weekday ${date.day} $month$year'.toUpperCase();
}

const _weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

/// Месяцы в родительном падеже: «21 августа», а не «21 август».
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

/// Тенге с разделителем тысяч.
///
/// Разделитель — неразрывный пробел (`\u00a0`): обычный позволил бы перенести
/// «1» и «140» на разные строки, и сумма читалась бы как два числа.
String formatMoney(double? amount) {
  if (amount == null) {
    return '—';
  }

  final whole = amount.round().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      buffer.write('\u00a0');
    }
    buffer.write(whole[i]);
  }

  return '$buffer\u00a0₸';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Позиция накладной — то, что модель вытащила из фотографии.
class DocumentLine {
  const DocumentLine({
    required this.id,
    required this.position,
    required this.name,
    required this.barcode,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.total,
    required this.umagProductName,
    required this.umagConfidence,
  });

  factory DocumentLine.fromJson(Map<String, dynamic> json) => DocumentLine(
        id: json['id'] as int,
        position: (json['position'] ?? 0) as int,
        name: (json['name'] ?? '') as String,
        barcode: (json['barcode'] ?? '') as String,
        quantity: _decimal(json['quantity'] as String?),
        unit: (json['unit'] ?? '') as String,
        price: _decimal(json['price'] as String?),
        total: _decimal(json['total'] as String?),
        umagProductName: (json['umag_product_name'] ?? '') as String,
        umagConfidence: (json['umag_confidence'] as num?)?.toDouble(),
      );

  final int id;
  final int position;
  final String name;
  final String barcode;
  final double? quantity;
  final String unit;
  final double? price;
  final double? total;

  /// Товар кабинета, с которым сведена строка.
  final String umagProductName;

  /// Единица — штрихкод с бумаги, меньше — его подставила модель.
  final double? umagConfidence;

  /// Штрихкод подставила модель, а не прочитала с бумаги.
  bool get barcodeGuessed =>
      umagProductName.isNotEmpty && umagConfidence != null && umagConfidence! < 1;

  static double? _decimal(String? raw) => raw == null ? null : double.tryParse(raw);
}

/// Накладная целиком — то, что показывает детальная страница.
///
/// Отдельно от `DocumentItem`: список тянет два десятка накладных разом, и
/// таскать в нём все позиции с фотографиями было бы расточительно.
class DocumentDetail {
  const DocumentDetail({
    required this.item,
    required this.supplierBin,
    required this.supplierBinAuto,
    required this.error,
    required this.imageUrl,
    required this.imageUrls,
    required this.model,
    required this.cost,
    required this.checkedByEmail,
    required this.umagSupplyId,
    required this.umagStoreId,
    required this.umagStoreName,
    required this.lines,
  });

  factory DocumentDetail.fromJson(Map<String, dynamic> json) => DocumentDetail(
        item: DocumentItem.fromJson(json),
        supplierBin: (json['supplier_bin'] ?? '') as String,
        supplierBinAuto: (json['supplier_bin_auto'] ?? false) as bool,
        error: (json['error'] ?? '') as String,
        // Выпрямленный снимок, если он получился, иначе исходный.
        imageUrl: (json['preview'] ?? json['image']) as String?,
        imageUrls: ((json['images'] ?? const []) as List).cast<String>(),
        model: (json['model'] ?? '') as String,
        cost: DocumentItem._decimal(json['cost'] as String?),
        checkedByEmail: json['checked_by_email'] as String?,
        umagSupplyId: json['umag_supply_id'] as int?,
        umagStoreId: json['umag_store_id'] as int?,
        umagStoreName: (json['umag_store_name'] ?? '') as String,
        lines: ((json['lines'] ?? []) as List)
            .map((row) => DocumentLine.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList(),
      );

  final DocumentItem item;
  final String supplierBin;

  /// БИН не прочитался с фото — его взяли из прошлой накладной поставщика.
  final bool supplierBinAuto;
  final String error;
  final String? imageUrl;

  /// Все листы накладной по порядку. У документов, загруженных до того, как мы
  /// научились принимать несколько, список пуст — тогда лист один, `imageUrl`.
  final List<String> imageUrls;

  /// Что показывать в просмотрщике: список листов, а если его нет — один снимок.
  List<String> get photos =>
      imageUrls.isNotEmpty ? imageUrls : [?imageUrl];
  final String model;
  final double? cost;
  final String? checkedByEmail;
  final int? umagSupplyId;

  /// Магазин, в который уехала приёмка. У старых накладных его нет — тогда
  /// берут тот, что выбран сейчас.
  final int? umagStoreId;

  final String umagStoreName;
  final List<DocumentLine> lines;

  /// Та же накладная без одной позиции.
  ///
  /// Нужна ровно для свайпа: `Dismissible` уже увёл строку с экрана, и если на
  /// следующей отрисовке она вернётся, Flutter упадёт с «A dismissed Dismissible
  /// widget is still part of the tree». Ждать ответа сервера тут нельзя.
  ///
  /// Итог не трогаем: его пересчитывает сервер, и подменять его своей арифметикой
  /// значило бы показать число, которого в базе нет.
  DocumentDetail withoutLine(int lineId) => DocumentDetail(
        item: item,
        supplierBin: supplierBin,
        supplierBinAuto: supplierBinAuto,
        error: error,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        model: model,
        cost: cost,
        checkedByEmail: checkedByEmail,
        umagSupplyId: umagSupplyId,
        umagStoreId: umagStoreId,
        umagStoreName: umagStoreName,
        lines: lines.where((line) => line.id != lineId).toList(),
      );
}
