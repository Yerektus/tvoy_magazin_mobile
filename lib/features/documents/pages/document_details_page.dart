import 'package:flutter/material.dart';

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../shared/services/api_exception.dart';
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
    // Итог берём из свежих данных, а пока они едут — из строки списка.
    final total = _detail?.item.total ?? widget.item.total;

    final photos = _detail?.photos ?? const <String>[];
    final action = _action;

    return Scaffold(
      appBar: AppBar(
        // Номера накладных длинные, и полноразмерный заголовок обрезается
        // многоточием уже на середине — мельче он помещается целиком.
        title: Text(widget.item.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _saving ? null : _retry,
            icon: const Icon(LucideIcons.scan_text),
            tooltip: 'Распознать заново',
          ),
          // Снимок — в шапке: смотреть бумагу нужно на любом шаге, а внизу
          // кнопка делила место с главным действием и была вдвое уже него,
          // хотя нажимают её не реже.
          //
          // Кнопки нет вовсе, когда нет снимка: у накладных, залитых до того,
          // как мы стали хранить оригинал, открывать нечего.
          if (photos.isNotEmpty)
            IconButton(
              onPressed: _openPhoto,
              icon: const Icon(LucideIcons.image),
              tooltip: 'Открыть снимок',
            ),
          const SizedBox(width: 4),
        ],
        // Место под полоску работы держим всегда. Раньше она появлялась и
        // исчезала вместе с высотой шапки, и всё под ней — вместе с кнопкой
        // действия — дёргалось вниз-вверх на два пикселя.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _saving
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          // Следующий шаг — сразу под шапкой и не прокручивается: список
          // позиций длинный, и до кнопки внизу приходилось долистывать.
          if (action != null) _ActionBar(child: action),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _body()),
          ),
        ],
      ),
      // Итог внизу, всегда на виду: сумму сверяют с бумагой чаще прочего, а
      // прокрутив длинный список позиций, человек потерял бы её.
      bottomNavigationBar: _BottomBar(total: total),
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

    // Гаснет кнопка только от своей работы (`_acting`). На чужую — удаление
    // позиции, правку поставщика — не смотрим: раньше она пропадала на время
    // любой, ряд дёргался, и снимок прыгал вправо и обратно.

    // Порядок важен: уже отправленная накладная перебивает всё остальное — её
    // могли перераспознать, и статус снова стал «Готово», но черновик в
    // кабинете от этого никуда не делся.
    if (detail.umagSupplyId == null &&
        detail.item.status == DocumentStatus.done) {
      return FilledButton.icon(
        onPressed: _acting ? null : _check,
        icon: const Icon(LucideIcons.check, size: 18),
        label: const Text('Проверено'),
      );
    }

    // Отправленную повторно не отправляем — второй черновик кабинету не нужен.
    // Вместо этого зовём туда, где она теперь лежит.
    if (detail.umagSupplyId != null) {
      return FilledButton.icon(
        onPressed: _openSupply,
        icon: const Icon(LucideIcons.external_link, size: 18),
        label: const Text('Черновик в UMAG'),
      );
    }

    if (detail.item.status == DocumentStatus.checked) {
      return FilledButton.icon(
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
        label: Text(_acting ? 'Загружаем…' : 'Загрузить в UMAG'),
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
                        _Row(
                          'Номер',
                          detail.item.number.isEmpty ? '—' : detail.item.number,
                        ),
                        _Row(
                          'Дата накладной',
                          detail.item.issuedAt == null
                              ? '—'
                              : formatDate(detail.item.issuedAt!),
                          onTap: _saving ? null : _editDate,
                          // Иначе дата выглядит такой же справкой, как номер и
                          // количество позиций, — и никто не догадается, что
                          // её можно поправить.
                          editable: true,
                        ),
                        _Row('Позиций', '${detail.lines.length}'),
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
        const SizedBox(height: 16),
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

/// Полоса под шапкой с тем, что с накладной делают дальше.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: child,
    );
  }
}

/// Нижняя панель: сколько всего по накладной.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.total});

  final double? total;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Итого', style: TextStyle(color: Color(0xFF737373))),
              Text(
                formatMoney(total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
  const _Row(
    this.label,
    this.value, {
    this.note,
    this.color,
    this.onTap,
    this.editable = false,
  });

  final String label;
  final String value;
  final String? note;
  final Color? color;

  /// Задано — по строке можно нажать: она либо ведёт наружу, в чужой кабинет,
  /// либо открывает правку. Значение тогда рисуем не серой справкой.
  final VoidCallback? onTap;

  /// Нажатие правит значение, а не уводит из приложения: вместо подчёркивания
  /// ставим карандаш — так видно, что менять будут здесь же.
  final bool editable;

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
            // Значения по правому краю: подписи слева разной длины, и при
            // выравнивании по левому значения вставали лесенкой. У правого
            // края они выстраиваются в столбец, а числа — ещё и разрядами друг
            // под другом.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: onTap == null
                                ? color
                                : const Color(0xFF0284C7),
                            decoration: onTap == null || editable
                                ? null
                                : TextDecoration.underline,
                            decorationColor: const Color(0xFF0284C7),
                          ),
                        ),
                      ),
                      if (editable) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          LucideIcons.pencil,
                          size: 14,
                          color: Color(0xFF0284C7),
                        ),
                      ],
                    ],
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note!,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Стрелка «наружу» — только у строк, уводящих в чужой кабинет.
            // У правимых на её месте карандаш, он стоит рядом со значением.
            if (onTap != null && !editable)
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
