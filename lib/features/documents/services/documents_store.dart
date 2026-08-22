import 'package:flutter/foundation.dart';

import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../models/document.dart';
import '../models/shot.dart';

/// Вкладки списка — те же, что на вебе.
enum DocumentsTab {
  all('Все', null),
  pending('Ожидают', 'pending'),
  checked('Проверенные', 'checked');

  const DocumentsTab(this.label, this.query);

  final String label;

  /// Чем вкладка отбирается на бэкенде. У «Всех» отбора нет.
  final String? query;
}

/// Список накладных организации.
///
/// Держит один экран, поэтому и состояние простое: что загружено, что грузится
/// и что пошло не так. Постраничность бэкенд отдаёт, но список короткий —
/// подгрузку добавим, когда накладных станет много.
class DocumentsStore extends ChangeNotifier {
  DocumentsStore({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<DocumentItem> _items = const [];
  DocumentsTab _tab = DocumentsTab.all;
  bool _loading = false;
  String? _error;

  List<DocumentItem> get items => _items;
  DocumentsTab get tab => _tab;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> select(DocumentsTab tab) async {
    if (_tab == tab) {
      return;
    }

    _tab = tab;
    _items = const [];
    notifyListeners();
    await load();
  }

  /// Отправляет накладную: один лист или несколько.
  ///
  /// Листов бывает больше одного, когда позиции не поместились на страницу.
  /// Уходят они вместе и разбираются как один документ: шапка стоит только на
  /// первом.
  ///
  /// Разбор идёт на сервере, поэтому сразу после загрузки в списке появляется
  /// строка со статусом «в очереди».
  Future<void> upload(List<Shot> pages) async {
    if (pages.isEmpty) {
      return;
    }

    await _api.upload('/invoices/', [
      for (final (index, page) in pages.indexed)
        UploadFile(
          // Первый лист — обычный снимок накладной, остальные идут рядом
          // полем `pages`: это один документ, а не несколько.
          field: index == 0 ? 'image' : 'pages',
          filename: page.filename,
          bytes: page.bytes,
          contentType: page.contentType,
        ),
    ]);

    await load();
  }

  /// Одна накладная целиком — для детальной страницы.
  ///
  /// Состояние тут не держим: страница живёт своей жизнью и сама решает, что
  /// показывать, пока грузится. Списку про это знать незачем.
  Future<DocumentDetail> detail(int id) async {
    final body = await _api.get('/invoices/$id/') as Map<String, dynamic>;

    return DocumentDetail.fromJson(body);
  }

  /// Правка поставщика. Название и БИН стоят на печати, а не в таблице, и
  /// читаются с фото хуже всего — их чаще прочего приходится вписывать руками.
  ///
  /// Список после этого перечитываем: имя поставщика видно прямо в строке.
  Future<DocumentDetail> updateDocument(int id, Map<String, dynamic> patch) async {
    final body = await _api.patch('/invoices/$id/', patch) as Map<String, dynamic>;
    await load();

    return DocumentDetail.fromJson(body);
  }

  /// Правка позиции: модель ошибается, бумага — источник истины.
  ///
  /// Возвращает не строку, а всю накладную: сервер пересчитывает итог по
  /// строкам, и после правки количества или цены он уже другой.
  ///
  /// Список тут не трогаем: он всё равно перечитывается, когда с карточки
  /// возвращаются назад, а ждать его здесь — держать человека перед полоской
  /// занятости лишний запрос.
  Future<DocumentDetail> updateLine(
    int invoiceId,
    int lineId,
    Map<String, dynamic> patch,
  ) async {
    await _api.patch('/invoices/$invoiceId/lines/$lineId/', patch);

    return detail(invoiceId);
  }

  /// Перезапустить разбор.
  ///
  /// На сервере это удаляет все строки и пишет их заново, поэтому спрашивать
  /// разрешения обязан вызывающий: ручные правки после этого не вернуть.
  ///
  /// Ответ приходит сразу, ещё до разбора — со статусом «в очереди».
  Future<DocumentDetail> retry(int id) async {
    final body = await _api.post('/invoices/$id/retry/', const {}) as Map<String, dynamic>;
    await load();

    return DocumentDetail.fromJson(body);
  }

  /// Отметить накладную проверенной.
  ///
  /// Это подпись человека под тем, что строки сходятся с бумагой. Пока её нет,
  /// сервер не даёт отправить накладную в UMAG — и правильно делает.
  Future<DocumentDetail> check(int id) async {
    final body = await _api.post('/invoices/$id/check/', const {}) as Map<String, dynamic>;
    await load();

    return DocumentDetail.fromJson(body);
  }

  /// Создать черновик приёмки в UMAG.
  ///
  /// Возвращает номер приёмки. Дальше её ведёт кабинет: недостающие данные
  /// человек вносит уже там.
  Future<int?> sendToUmag(int id) async {
    final body = await _api.post('/umag/invoices/$id/', const {}) as Map<String, dynamic>;

    return body['supply_id'] as int?;
  }

  /// Выкинуть позицию.
  ///
  /// Модель то придумывает лишнюю строку, то дублирует соседнюю — такие в
  /// накладной не нужны. Сервер после удаления перенумеровывает оставшиеся и
  /// пересчитывает итог, поэтому возвращаем накладную целиком.
  Future<DocumentDetail> deleteLine(int invoiceId, int lineId) async {
    await _api.delete('/invoices/$invoiceId/lines/$lineId/');

    return detail(invoiceId);
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final body = await _api.get(
        '/invoices/',
        query: {if (_tab.query != null) 'tab': _tab.query!},
      ) as Map<String, dynamic>;

      _items = (body['results'] as List)
          .map((row) => DocumentItem.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
