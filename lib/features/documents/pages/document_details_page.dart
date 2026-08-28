import 'package:flutter/material.dart';

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/back_label.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/inline_field.dart';
import '../../../shared/widgets/message.dart';
import '../../umag/models/umag_account.dart';
import '../../umag/services/umag_store.dart';
import '../models/document.dart';
import '../services/documents_store.dart';
import 'line_details_page.dart';
import 'photo_page.dart';

/// Карточка накладной: что прочитано с бумаги и куда это уехало.
///
/// Самого снимка здесь нет — он открывается кнопкой поверх экрана. Полоска
/// превью съедала верх страницы, а разобрать на ней что-либо всё равно было
/// нельзя: накладная это мелкий шрифт, его нужно увеличивать.
///
/// Поставщика правят прямо здесь: его название и БИН стоят на печати, а не в
/// таблице, и читаются с фото хуже всего. Позиции правят на своей странице —
/// у строки шесть полей, в один экран с остальным они не помещаются.
class DocumentDetailsPage extends StatefulWidget {
  const DocumentDetailsPage({
    super.key,
    required this.store,
    required this.item,
    required this.umag,
  });

  final DocumentsStore store;

  /// Кабинет UMAG: из его списка магазинов собирается адрес черновика.
  final UmagAccountStore umag;

  /// Уже загруженная строка списка: по ней рисуем шапку, пока едет остальное.
  final DocumentItem item;

  @override
  State<DocumentDetailsPage> createState() => _DocumentDetailsPageState();
}

class _DocumentDetailsPageState extends State<DocumentDetailsPage> {
  DocumentDetail? _detail;
  String? _error;
  bool _saving = false;

  /// Развёрнута ли общая информация о накладной.
  ///
  /// Раскрыта по умолчанию: свернув её при первом открытии, мы спрятали бы
  /// поставщика и статус от того, кто ещё не знает, что их можно раскрыть.
  bool _infoOpen = true;

  /// Развёрнут ли список позиций. Тоже раскрыт: ради него карточку и
  /// открывают — строки сверяют с бумагой.
  bool _linesOpen = true;

  /// Идёт то самое действие, что стоит под шапкой: отметка проверенной или
  /// загрузка в UMAG.
  ///
  /// Отдельно от `_saving`: тот поднимается и на удалении позиции, и на правке
  /// поставщика, а к кнопке они отношения не имеют — от их работы она гаснуть
  /// не должна.
  bool _acting = false;

  /// Пока накладная в разборе, страница перечитывает себя сама: разбор идёт на
  /// сервере и о своём конце знать не даёт, а после «распознать заново» человек
  /// смотрит именно на этот экран и ждёт строк.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);

    try {
      final detail = await widget.store.detail(widget.item.id);

      if (mounted) {
        setState(() => _detail = detail);
        _watchWhileParsing(detail);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    }
  }

  /// Ставит или снимает повторный опрос — смотря разбирается накладная или уже
  /// разобрана. Опрос одноразовый: каждая загрузка решает про следующую заново,
  /// поэтому он гаснет сам, как только статус перестал быть промежуточным.
  void _watchWhileParsing(DocumentDetail detail) {
    _poll?.cancel();

    const waiting = {DocumentStatus.pending, DocumentStatus.processing};

    if (waiting.contains(detail.item.status)) {
      _poll = Timer(const Duration(seconds: 3), _load);
    }
  }

  /// Перезапуск разбора. Спрашиваем всегда: сервер удаляет все строки и пишет
  /// их заново, так что любая ручная правка пропадёт безвозвратно.
  Future<void> _retry() async {
    if (_saving) {
      return;
    }

    final agreed = await confirm(
      context,
      title: 'Распознать заново?',
      message:
          'Строки прочитаются с фотографии заново. '
          'Всё, что вы поправили руками, пропадёт, а отметка о проверке снимется.',
      action: 'Распознать',
      dangerous: true,
    );

    if (!agreed || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      final detail = await widget.store.retry(widget.item.id);

      if (mounted) {
        setState(() => _detail = detail);
        _watchWhileParsing(detail);
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось перезапустить',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Отметить проверенной. Это подпись под тем, что строки сходятся с бумагой,
  /// поэтому спрашиваем: нажатие мимо не должно ничего подписывать.
  Future<void> _check() async {
    if (_saving) {
      return;
    }

    final agreed = await confirm(
      context,
      title: 'Всё сходится с бумагой?',
      message: 'После этого её можно отправить в UMAG.',
      action: 'Проверено',
    );

    if (!agreed || !mounted) {
      return;
    }

    await _act(() async {
      final detail = await widget.store.check(widget.item.id);

      if (mounted) {
        setState(() => _detail = detail);
      }
    }, failure: 'Не удалось отметить');
  }

  /// Создать черновик приёмки в UMAG.
  Future<void> _sendToUmag() async {
    if (_saving) {
      return;
    }

    final agreed = await confirm(
      context,
      title: 'Загрузить в UMAG?',
      message:
          'В кабинете появится черновик приёмки. '
          'Недостающие данные вносят уже там.',
      action: 'Загрузить',
    );

    if (!agreed || !mounted) {
      return;
    }

    await _act(() async {
      final supplyId = await widget.store.sendToUmag(widget.item.id);
      // Номер приёмки лежит в самой накладной — перечитываем, чтобы он
      // появился в разделе «Обработка», а кнопка отсюда ушла.
      await _load();

      if (mounted && supplyId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Приёмка №$supplyId создана в UMAG')),
        );
      }
    }, failure: 'Не удалось загрузить в UMAG');
  }

  /// Общая обвязка для действий: полоска занятости и понятный отказ.
  Future<void> _act(
    Future<void> Function() action, {
    required String failure,
  }) async {
    setState(() {
      _saving = true;
      _acting = true;
    });

    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        // Полоску гасим до окна, а не после: работа кончилась — пусть и
        // неудачей, — а бегущая под сообщением об ошибке лента обещает, что
        // что-то ещё происходит.
        setState(() {
          _saving = false;
          _acting = false;
        });
        await showErrorDialog(context, title: failure, message: error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _acting = false;
        });
      }
    }
  }

  /// Показывает итог накладной.
  ///
  /// Листом, а не строкой внизу экрана: сумму сверяют с бумагой один раз, а
  /// место она занимала всегда. Здесь же рядом стоит и число позиций — эти два
  /// числа и сверяют вместе.
  Future<void> _showTotal() async {
    final detail = _detail;

    if (detail == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) =>
          _TotalSheet(total: detail.item.total, lines: detail.lines.length),
    );
  }

  /// Поправить дату документа.
  ///
  /// Кабинет её проверяет: приход раньше проведённой инвентаризации он не
  /// принимает, а модель нет-нет да и прочитает «2020» вместо «2026». Пока
  /// дату нельзя было поправить, такая накладная не уезжала вовсе.
  Future<void> _editDate() async {
    final detail = _detail;

    if (detail == null || _saving) {
      return;
    }

    final today = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: detail.item.issuedAt ?? today,
      // Год назад и день вперёд: накладную выписывают до привоза, но не
      // будущим месяцем, а разбирают её через день-другой, не через годы.
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: DateTime(today.year, today.month, today.day + 1),
      helpText: 'Дата накладной',
    );

    if (chosen == null || !mounted || chosen == detail.item.issuedAt) {
      return;
    }

    final iso =
        '${chosen.year.toString().padLeft(4, '0')}-'
        '${chosen.month.toString().padLeft(2, '0')}-'
        '${chosen.day.toString().padLeft(2, '0')}';

    await _editSupplier('issued_at', iso);
  }

  /// Дописать позицию, которую модель пропустила.
  ///
  /// Строка заводится пустой и сразу открывается: одна она никому не нужна,
  /// нужна заполненная, а вбивать её всё равно с бумаги.
  Future<void> _addLine() async {
    setState(() => _saving = true);

    try {
      final detail = await widget.store.addLine(widget.item.id);

      if (!mounted) {
        return;
      }

      setState(() => _detail = detail);

      // Сервер ставит новую строку первой — она же и открывается.
      if (detail.lines.isNotEmpty) {
        await _openLine(detail.lines.first);
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось добавить позицию',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Выкинуть позицию. Спрашиваем: вернуть строку нечем — заново её пришлось бы
  /// вбивать руками, глядя в бумагу.
  Future<bool> _confirmDelete(DocumentLine line) async {
    return confirm(
      context,
      title: 'Удалить позицию?',
      message: line.name,
      action: 'Удалить',
      dangerous: true,
    );
  }

  Future<void> _deleteLine(DocumentLine line) async {
    // Сначала убираем строку из списка, и только потом идём на сервер: см.
    // `DocumentDetail.withoutLine` — вернуть её в дерево уже нельзя.
    setState(() {
      _saving = true;
      _detail = _detail?.withoutLine(line.id);
    });

    try {
      final detail = await widget.store.deleteLine(widget.item.id, line.id);

      if (mounted) {
        setState(() => _detail = detail);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        await showErrorDialog(
          context,
          title: 'Не удалось удалить позицию',
          message: error.message,
        );
        // Строка осталась в базе, а с экрана уже ушла — возвращаем её, иначе
        // человек будет думать, что удалил, пока не откроет накладную заново.
        await _load();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Открывает черновик приёмки в кабинете UMAG.
  Future<void> _openSupply() async {
    final detail = _detail;
    final supplyId = detail?.umagSupplyId;

    if (detail == null || supplyId == null || _saving) {
      return;
    }

    // Список магазинов мог ещё не приехать — тогда ждём его: без него мы знаем
    // только запасной вариант «первый магазин», а он ведёт в чужую приёмку.
    // Список магазинов мог ещё не приехать — тогда ждём его: без него мы знаем
    // только запасной вариант «первый магазин», а он ведёт в чужую приёмку.
    if (widget.umag.account.stores.isEmpty) {
      await widget.umag.load();

      if (!mounted) {
        return;
      }
    }

    // Накладная помнит свой магазин; у старых его нет — берём выбранный сейчас.
    final stores = widget.umag.account.stores;
    final storeId = detail.umagStoreId ?? widget.umag.account.storeId;
    final url = Uri.parse(supplyUrl(supplyId, storeIndexOf(stores, storeId)));

    // Кабинет открываем снаружи, а не внутри приложения: там свой вход, и во
    // встроенном окне человек оказался бы разлогинен.
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      await showErrorDialog(
        context,
        title: 'Не удалось открыть кабинет',
        message: 'Откройте вручную: $url',
      );
    }
  }

  /// Открывает листы накладной поверх экрана.
  void _openPhoto() {
    final photos = _detail?.photos ?? const <String>[];

    if (photos.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoPage(urls: photos, title: widget.item.title),
      ),
    );
  }

  /// Правка поставщика: значение уходит, как только поле теряет фокус.
  Future<void> _editSupplier(String field, String value) async {
    setState(() => _saving = true);

    try {
      final detail = await widget.store.updateDocument(widget.item.id, {
        field: value,
      });

      if (mounted) {
        setState(() => _detail = detail);
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось сохранить',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Открывает позицию. Правки внутри уже сохранены на сервере, поэтому по
  /// возвращении просто перечитываем накладную — вместе с пересчитанным итогом.
  Future<void> _openLine(DocumentLine line) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LineDetailsPage(
          store: widget.store,
          umag: widget.umag,
          invoiceId: widget.item.id,
          line: line,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _detail?.photos ?? const <String>[];
    final action = _action;

    return Scaffold(
      appBar: AppBar(
        // Номера накладных длинные, и полноразмерный заголовок обрезается
        // многоточием уже на середине — мельче он помещается целиком.
        // Следующий шаг — в шапке справа: он на экране один, и место у правого
        // края под него и держат. Полосой под шапкой он занимал целую строку
        // ради одной кнопки.
        //
        // Кнопка стоит в строке заголовка, а не в `actions`: там она рисуется,
        // но нажатия до неё не доходят — человек тычет в мёртвое место. Здесь
        // обе части делят ширину честно: заголовок ужимается многоточием,
        // кнопка занимает столько, сколько просит.
        // Заголовка нет: «Накладная от 27.08.2026» повторяло дату, которая
        // стоит строкой ниже, и ужималось в многоточие, отбирая место у
        // единственной кнопки. В шапке остаётся то, ради чего сюда смотрят, —
        // следующий шаг.
        titleSpacing: 4,
        automaticallyImplyLeading: false,
        title: Row(
          children: [const BackLabel('Документы'), const Spacer(), ?action],
        ),
        // Место под полоску работы держим всегда. Раньше она появлялась и
        // исчезала вместе с высотой шапки, и всё под ней дёргалось вниз-вверх
        // на два пикселя.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _saving
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      // Полоса действий лежит поверх списка, а не в `bottomNavigationBar`: тот
      // отрезает себе полосу экрана насовсем, и под накладную остаётся меньше.
      // Здесь список идёт до самого низа, а полоса висит над ним.
      body: Stack(
        children: [
          RefreshIndicator(onRefresh: _load, child: _body()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Toolbar(
              onRetry: _saving ? null : _retry,
              onTotal: _detail == null ? null : _showTotal,
              // Снимка нет у накладных, залитых до того, как мы стали хранить
              // оригинал: открывать там нечего.
              onPhoto: photos.isEmpty ? null : _openPhoto,
            ),
          ),
        ],
      ),
    );
  }

  /// Следующий шаг накладной, если он есть.
  ///
  /// Шагов два и идут они строго по очереди: сначала человек отмечает, что
  /// строки сходятся с бумагой, и только потом накладная уезжает в UMAG. Тот же
  /// порядок держит и сервер — отправку без отметки он отклоняет.
  Widget? get _action {
    final detail = _detail;

    if (detail == null) {
      return null;
    }

    // В шапке кнопка живёт по своим размерам: в общей теме у `FilledButton`
    // задана высота через `Size.fromHeight`, а это бесконечная ширина — в
    // строке шапки такую разложить нельзя.
    final compact = FilledButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      // Кнопка второстепенная: бледная заливка своего цвета вместо сплошной
      // синей. Залитая тянула на себя весь экран, хотя карточку открывают
      // ради строк накладной, а не ради неё.
      backgroundColor: accentPale,
      foregroundColor: accentDark,
      disabledBackgroundColor: const Color(0xFFF5F5F5),
      disabledForegroundColor: const Color(0xFFA3A3A3),
    );

    // Гаснет кнопка только от своей работы (`_acting`). На чужую — удаление
    // позиции, правку поставщика — не смотрим: раньше она пропадала на время
    // любой, ряд дёргался, и снимок прыгал вправо и обратно.

    // Порядок важен: уже отправленная накладная перебивает всё остальное — её
    // могли перераспознать, и статус снова стал «Готово», но черновик в
    // кабинете от этого никуда не делся.
    if (detail.umagSupplyId == null &&
        detail.item.status == DocumentStatus.done) {
      return FilledButton.icon(
        style: compact,
        onPressed: _acting ? null : _check,
        icon: const Icon(LucideIcons.check, size: 18),
        label: const Text('Проверено'),
      );
    }

    // Отправленную повторно не отправляем — второй черновик кабинету не нужен.
    // Вместо этого зовём туда, где она теперь лежит.
    if (detail.umagSupplyId != null) {
      return FilledButton.icon(
        style: compact,
        onPressed: _openSupply,
        icon: const Icon(LucideIcons.external_link, size: 18),
        // В шапке места мало: рядом стоит заголовок с номером накладной, и
        // полная подпись выдавливала его в многоточие с середины слова.
        label: const Text('Черновик'),
      );
    }

    if (detail.item.status == DocumentStatus.checked) {
      return FilledButton.icon(
        style: compact,
        // Пока идёт загрузка, кнопка погашена: черновик в кабинете заводится
        // секунды, и за это время по ней успевали нажать второй раз.
        onPressed: _acting ? null : _sendToUmag,
        icon: _acting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.cloud_upload, size: 18),
        label: Text(_acting ? 'Загружаем…' : 'В UMAG'),
      );
    }

    return null;
  }

  Widget _body() {
    if (_error != null) {
      return Message(
        icon: LucideIcons.cloud_off,
        title: 'Не удалось загрузить',
        note: _error,
        onRetry: _load,
      );
    }

    final detail = _detail;

    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        if (detail.error.isNotEmpty) _Failure(text: detail.error),
        _SectionToggle(
          title: 'Информация',
          open: _infoOpen,
          onTap: () => setState(() => _infoOpen = !_infoOpen),
        ),
        // Свёрнутую часть убираем целиком, а не прячем: список позиций длинный,
        // и чем меньше над ним лишнего, тем меньше до него листать.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_infoOpen
              // Высоту задаём явно: `SizedBox` без неё занимает всё, что ему
              // дают, и на месте свёрнутой части оставалась пустая дыра.
              ? const SizedBox(width: double.infinity, height: 0)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Поставщик',
                      children: [
                        _Field(
                          label: 'Название',
                          value: detail.item.supplier,
                          maxLines: null,
                          onChanged: (next) => _editSupplier('supplier', next),
                        ),
                        _Field(
                          label: 'БИН',
                          value: detail.supplierBin,
                          hint: '12 цифр',
                          keyboardType: TextInputType.number,
                          note: detail.supplierBinAuto
                              ? 'подставил ИИ по прошлым накладным'
                              : null,
                          onChanged: (next) =>
                              _editSupplier('supplier_bin', next),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Документ',
                      children: [
                        // Номер правится руками: он уходит в комментарий
                        // приёмки, по нему её и ищут в кабинете, а с бумаги
                        // читается через раз — печать бледная, а рядом стоят
                        // номера счёта и договора.
                        _Field(
                          label: 'Номер',
                          value: detail.item.number,
                          hint: 'как в накладной',
                          onChanged: (next) => _editSupplier('number', next),
                        ),
                        // Дата — не справка, а правимое значение, поэтому
                        // выглядит полем, как название поставщика рядом.
                        // Клавиатуры при этом нет: дату выбирают в календаре,
                        // а не набирают цифрами с точками.
                        _DateField(
                          label: 'Дата накладной',
                          value: detail.item.issuedAt == null
                              ? ''
                              : formatDate(detail.item.issuedAt!),
                          onTap: _saving ? null : _editDate,
                        ),
                        _Row('Позиций', '${detail.lines.length}'),
                        // Итог переехал сюда из нижней панели: там он занимал
                        // целую строку экрана ради числа, которое сверяют с
                        // бумагой один раз, а рядом с номером и датой он и по
                        // смыслу на своём месте.
                        _Row('Сумма', formatMoney(detail.item.total)),
                      ],
                    ),
                    _Section(
                      title: 'Обработка',
                      children: [
                        _Row(
                          'Статус',
                          detail.item.status.label,
                          color: detail.item.status.color,
                        ),
                        _Row(
                          'Загружено',
                          detail.item.createdAt == null
                              ? '—'
                              : formatDateTime(detail.item.createdAt!),
                        ),
                        if (detail.checkedByEmail != null)
                          _Row('Проверил', detail.checkedByEmail!),
                        if (detail.umagSupplyId != null)
                          _Row(
                            'Приёмка в UMAG',
                            '№${detail.umagSupplyId}',
                            note: detail.umagStoreName.isEmpty
                                ? null
                                : detail.umagStoreName,
                            onTap: _openSupply,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        _SectionToggle(
          title: 'Позиции',
          open: _linesOpen,
          onTap: () => setState(() => _linesOpen = !_linesOpen),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_linesOpen
              ? const SizedBox(width: double.infinity, height: 0)
              : _Lines(
                  lines: detail.lines,
                  onTap: _openLine,
                  onDelete: _deleteLine,
                  onConfirmDelete: _confirmDelete,
                  onAdd: _saving ? null : _addLine,
                ),
        ),
        // Место под плавающую полосу: без него последняя позиция и кнопка
        // «Добавить позицию» прятались бы под ней.
        const SizedBox(height: 96),
      ],
    );
  }
}

/// Переключатель раздела карточки.
///
/// Серой полосой во всю ширину — как заголовки дней в списке: так видно, что
/// это не подпись к разделу, а по ней можно нажать. Слов «свернуть» и
/// «развернуть» нет: стрелка говорит то же самое и не спорит с заголовком.
class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.title,
    required this.open,
    required this.onTap,
  });

  final String title;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F0F0),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  // Не капсом: разрядка и прописные нужны были друг другу —
                  // вплотную набранный капс слипается, — а строчным они только
                  // мешают, и заголовок читается как обычное слово.
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF737373),
                  ),
                ),
              ),
              // Стрелка поворачивается, а не подменяется другой иконкой: так
              // видно, что это одна и та же кнопка в двух состояниях.
              AnimatedRotation(
                duration: const Duration(milliseconds: 180),
                turns: open ? 0.5 : 0,
                child: const Icon(
                  LucideIcons.chevron_down,
                  size: 22,
                  color: Color(0xFF525252),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавающая полоса действий над списком.
///
/// Пилюля с иконками, а не панель во всю ширину: она висит поверх документов,
/// не отрезая от них полосу экрана, и по виду отличается от кнопки действия в
/// шапке — там следующий шаг накладной, здесь работа с самой бумагой.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onRetry,
    required this.onPhoto,
    required this.onTotal,
  });

  /// Пусто — прямо сейчас с накладной уже что-то делают.
  final VoidCallback? onRetry;

  /// Пусто — снимка нет: у накладных, залитых до того, как мы стали хранить
  /// оригинал, открывать нечего.
  final VoidCallback? onPhoto;

  /// Пусто — накладная ещё едет с сервера, показывать нечего.
  final VoidCallback? onTotal;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        // Ряд, а не `Center`: тот занимает всё, что ему дают, — а даёт
        // `Scaffold` нижней панели целый экран, и панель накрывала список
        // невидимым слоем, перехватывая нажатия по нему.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Material(
              color: accentPale,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolbarButton(
                      icon: LucideIcons.scan_text,
                      tooltip: 'Распознать заново',
                      onPressed: onRetry,
                    ),
                    _ToolbarButton(
                      icon: LucideIcons.image,
                      tooltip: 'Открыть снимок',
                      onPressed: onPhoto,
                    ),
                    _ToolbarButton(
                      icon: LucideIcons.info,
                      tooltip: 'Итог накладной',
                      onPressed: onTotal,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка полосы: круглая область нажатия под иконкой.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: SizedBox(
          // По ним бьют пальцем на ходу, с накладной в другой руке: мелкая цель
          // заставляет целиться.
          width: 60,
          height: 56,
          child: Icon(
            icon,
            size: 24,
            color: onPressed == null ? const Color(0xFFA3A3A3) : accentDark,
          ),
        ),
      ),
    );
  }
}

/// Итог накладной: сколько всего и из скольких строк.
class _TotalSheet extends StatelessWidget {
  const _TotalSheet({required this.total, required this.lines});

  final double? total;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Итог накладной',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Сумма', style: TextStyle(color: Color(0xFF737373))),
                Text(
                  formatMoney(total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Позиций',
                  style: TextStyle(color: Color(0xFF737373)),
                ),
                Text('$lines', style: const TextStyle(fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Причина, по которой разбор не удался.
class _Failure extends StatelessWidget {
  const _Failure({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.all(16),
      child: Text(text, style: const TextStyle(color: Color(0xFFB91C1C))),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            // Тоже не капсом — как и заголовки разделов выше: иначе на одном
            // экране половина подписей кричит, а половина нет.
            style: const TextStyle(fontSize: 13, color: Color(0xFFA3A3A3)),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// Строка «подпись — значение». Подпись слева фиксированной ширины, чтобы
/// значения выстроились в один столбец и читались как таблица.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.note, this.color, this.onTap});

  final String label;
  final String value;
  final String? note;
  final Color? color;

  /// Задано — строка ведёт наружу, в чужой кабинет. Значение тогда рисуем
  /// ссылкой: серый текст с иконкой сбоку выглядел бы как обычная справка.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF737373)),
              ),
            ),
            // Значения по левому краю — ровно на той же вертикали, что и текст
            // внутри полей ввода рядом: у поля свой внутренний отступ, и без
            // такого же справка стояла бы на десять точек левее полей.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: onTap == null ? color : const Color(0xFF0284C7),
                        decoration: onTap == null
                            ? null
                            : TextDecoration.underline,
                        decorationColor: const Color(0xFF0284C7),
                      ),
                    ),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note!,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  LucideIcons.external_link,
                  size: 16,
                  color: Color(0xFF0284C7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Строка с датой: выглядит полем, а открывает календарь.
///
/// Полем — чтобы её не принимали за справку вроде номера или числа позиций.
/// Календарём — потому что дата с клавиатуры набирается медленнее и с
/// опечатками вроде «18.13.2026».
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;

  /// Пусто — прямо сейчас с накладной что-то делают, и правка подождёт.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF737373)),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  // Та же серая заливка без рамки, что у правимых полей рядом.
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.isEmpty ? 'дд.мм.гггг' : value,
                        style: TextStyle(
                          fontSize: 15,
                          color: value.isEmpty ? const Color(0xFFA3A3A3) : null,
                        ),
                      ),
                    ),
                    const Icon(
                      LucideIcons.calendar,
                      size: 18,
                      color: Color(0xFF737373),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Та же строка, но значение правится прямо на месте.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.note,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final Future<void> Function(String) onChanged;
  final String? hint;
  final String? note;
  final TextInputType? keyboardType;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: SizedBox(
              width: 140,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF737373)),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InlineField(
                  value: value,
                  hint: hint,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  onChanged: onChanged,
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Распознанные позиции.
class _Lines extends StatelessWidget {
  const _Lines({
    required this.lines,
    required this.onTap,
    required this.onDelete,
    required this.onConfirmDelete,
    required this.onAdd,
  });

  final List<DocumentLine> lines;
  final void Function(DocumentLine) onTap;
  final void Function(DocumentLine) onDelete;
  final Future<bool> Function(DocumentLine) onConfirmDelete;

  /// Пусто — прямо сейчас с накладной уже что-то делают, и второй запрос ей ни
  /// к чему.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lines.isEmpty)
          const Padding(
            // Сверху воздух: без него строка липнет к серой полосе раздела и
            // читается как часть её, а не как ответ на вопрос «что внутри».
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'Позиции не распознаны',
              style: TextStyle(color: Color(0xFF737373)),
            ),
          ),

        for (final (index, line) in lines.indexed)
          // Ключ по id строки, а не по номеру: после удаления сервер
          // перенумеровывает оставшиеся, и по номеру Flutter принял бы
          // соседнюю строку за только что убранную.
          Slidable(
            key: ValueKey(line.id),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              // Кнопка занимает четверть ширины: строку при этом видно, и
              // понятно, к чему относится «Удалить».
              extentRatio: 0.28,
              children: [
                SlidableAction(
                  onPressed: (_) async {
                    if (await onConfirmDelete(line)) {
                      onDelete(line);
                    }
                  },
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  icon: LucideIcons.trash_2,
                  label: 'Удалить',
                ),
              ],
            ),
            child: _LineTile(
              line: line,
              // Черта отделяет строки друг от друга. Первой отделяться не от
              // чего: над ней и так серая полоса раздела, и две линии подряд
              // читались как пустая рамка.
              divider: index > 0,
              onTap: () => onTap(line),
            ),
          ),

        // Модель иногда пропускает строку целиком — дописать её нужно руками.
        // Кнопка внизу списка, а не в шапке раздела: дописывают после того,
        // как сверили остальные, и палец в этот момент уже здесь.
        _AddLineButton(onPressed: onAdd),
      ],
    );
  }
}

/// Кнопка «Добавить позицию» под списком.
class _AddLineButton extends StatelessWidget {
  const _AddLineButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Добавить позицию'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: const BorderSide(color: Color(0xFFD4D4D4)),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.divider,
    required this.onTap,
  });

  final DocumentLine line;

  /// Рисовать ли черту сверху. У первой строки её нет.
  final bool divider;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          // Свой фон обязателен: под строкой лежит красная подложка удаления, и
          // сквозь прозрачную она просвечивала бы всегда, а не только на свайпе.
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: divider ? const Color(0xFFF5F5F5) : Colors.transparent,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${line.position}.',
                style: const TextStyle(color: Color(0xFFA3A3A3)),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name),
                  if (line.umagProductName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'UMAG: ${line.umagProductName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFA3A3A3),
                        ),
                      ),
                    ),
                  if (line.barcode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        line.barcode,
                        style: TextStyle(
                          fontSize: 12,
                          // Подобранный выделяем цветом: его не было на
                          // бумаге, и глазами по строке он не проверяется.
                          color: line.barcodeAuto
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF737373),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatQuantity(line.quantity)} ${line.unit}'.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF737373),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(line.total),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                LucideIcons.chevron_right,
                size: 20,
                color: Color(0xFFA3A3A3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
