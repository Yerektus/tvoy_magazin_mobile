import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../../umag/services/umag_store.dart';
import '../models/document.dart';
import '../models/shot.dart';
import '../services/document_scanner.dart';
import '../services/documents_store.dart';
import 'capture_page.dart';
import 'document_details_page.dart';

/// Список накладных организации: их видит вся смена, а не только тот, кто
/// загрузил.
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key, required this.store, required this.umag});

  final DocumentsStore store;
  final UmagAccountStore umag;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage>
    with SingleTickerProviderStateMixin {
  /// Вкладки ведёт `TabController`: он плавно возит подчёркивание и держит
  /// выбранную, а самодельная полоса делала это руками и хуже.
  late final TabController _tabs = TabController(
    length: DocumentsTab.values.length,
    initialIndex: DocumentsTab.values.indexOf(widget.store.tab),
    vsync: this,
  )..addListener(_onTabChanged);

  /// Гуляет отдельно от `store.isLoading`: тот про список, а не про то, что
  /// прямо сейчас грузится фото из галереи.
  bool _uploading = false;

  /// Кнопка добавления. Ключ нужен, чтобы измерить, где она стоит: раскрытый
  /// список рисуется отдельным слоем поверх всего экрана и своего места сам не
  /// знает.
  final GlobalKey _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    widget.store.load();
    // Список магазинов UMAG нужен не настройкам, а ссылке на черновик
    // приёмки: в её адресе стоит порядковый номер магазина. Раньше он читался
    // только при открытии бокового меню — кто его не открывал, получал ссылку
    // на первый магазин вместо своего.
    widget.umag.load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  /// Список перечитываем один раз — когда вкладка доехала. Во время
  /// переключения `index` меняется дважды, и запросов ушло бы столько же.
  void _onTabChanged() {
    if (_tabs.indexIsChanging) {
      return;
    }

    widget.store.select(DocumentsTab.values[_tabs.index]);
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Раскрывает список: снять накладную или взять готовое фото.
  ///
  /// Список живёт в отдельном слое поверх всего экрана, а не в `Stack` внутри
  /// страницы. Затемнение должно гасить и шапку с вкладками, и нижнюю панель
  /// разделов: иначе они остаются светлыми и нажимаемыми, и раскрытый список
  /// выглядит не как выбор, который нужно сделать, а как всплывшая мелочь.
  Future<void> _openDial() async {
    final box = _fabKey.currentContext?.findRenderObject() as RenderBox?;

    if (box == null || _uploading) {
      return;
    }

    // Слой знает только размеры экрана, поэтому положение кнопки переводим в
    // отступы от правого и нижнего краёв — так копия кнопки встаёт ровно на
    // настоящую, где бы та ни оказалась.
    final screen = MediaQuery.sizeOf(context);
    final corner = box.localToGlobal(Offset.zero);
    final inset = EdgeInsets.only(
      right: screen.width - corner.dx - box.size.width,
      bottom: screen.height - corner.dy - box.size.height,
    );

    final chosen = await showGeneralDialog<_AddSource>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, animation, _) => Padding(
        padding: inset,
        child: Align(
          alignment: Alignment.bottomRight,
          child: _Dial(animation: animation, size: box.size),
        ),
      ),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

    if (!mounted || chosen == null) {
      return;
    }

    switch (chosen) {
      case _AddSource.camera:
        await _openCamera();
      case _AddSource.gallery:
        await _pickFromGallery();
    }
  }

  /// Открывает карточку накладной. По возвращении список перечитываем: за
  /// это время разбор мог закончиться, и статус в строке успел устареть.
  Future<void> _openDetails(DocumentItem document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailsPage(
          store: widget.store,
          item: document,
          umag: widget.umag,
        ),
      ),
    );

    if (mounted) {
      await widget.store.load();
    }
  }

  /// Снимает накладную.
  ///
  /// Сперва системным сканером документов: он сам ловит края листа и
  /// выпрямляет перспективу, а модель читает такой снимок заметно лучше. На
  /// телефоне без него — своей камерой, как раньше.
  Future<void> _openCamera() async {
    final scanner = DocumentScanner();
    List<Shot> shots;

    try {
      shots = await scanner.scan();
    } on ScannerUnavailable catch (error) {
      debugPrint('Сканер документов недоступен: ${error.message}');
      await _openOwnCamera();
      return;
    }

    // Сканер закрыли, ничего не сняв, — это отказ, а не ошибка.
    if (shots.isEmpty || !mounted) {
      return;
    }

    // Своего экрана проверки тут нет намеренно: системный сканер уже показал
    // снятое, дал повернуть, обрезать и переснять. Второй такой же экран —
    // лишнее нажатие на пути, который человек проходит по десять раз за приём.
    await _send(shots);
  }

  /// Своя камера — запасной путь для телефонов без сканера документов.
  Future<void> _openOwnCamera() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CapturePage(store: widget.store)),
    );

    if (added == true && mounted) {
      _announceUploaded();
    }
  }

  /// Отправляет снятые листы одной накладной.
  Future<void> _send(List<Shot> shots) async {
    setState(() => _uploading = true);

    try {
      await widget.store.upload(shots);

      if (mounted) {
        _announceUploaded();
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось отправить',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);

    // Открыли галерею и передумали — не ошибка, а обычный отказ.
    if (file == null) {
      return;
    }

    await _send([
      Shot(
        bytes: await file.readAsBytes(),
        filename: file.name,
        contentType: _contentTypeOf(file),
      ),
    ]);
  }

  /// Выкинуть накладную из списка.
  ///
  /// Спрашиваем: снимок вместе с ней уходит из выдачи, и повторить его можно
  /// только с той же бумагой в руках, а её к вечеру уже увезли.
  Future<void> _delete(DocumentItem document) async {
    final agreed = await confirm(
      context,
      title: 'Удалить накладную?',
      message: document.supplier.isEmpty
          ? document.title
          : '${document.supplier} · ${document.title}',
      action: 'Удалить',
      dangerous: true,
    );

    if (!agreed || !mounted) {
      return;
    }

    try {
      await widget.store.deleteDocument(document.id);
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось удалить',
          message: error.message,
        );
      }
    }
  }

  /// Формат снимка из галереи заранее не известен — он может быть JPEG, PNG
  /// или HEIC с айфона. Спрашиваем `image_picker`, а не гадаем по расширению
  /// имени, которое телефон иногда не пишет вовсе.
  String _contentTypeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) {
      return mime;
    }

    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    if (name.endsWith('.heif')) return 'image/heif';

    return 'image/jpeg';
  }

  void _announceUploaded() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Накладная загружена — идёт распознавание')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return Scaffold(
      appBar: AppBar(
        // Без черты снизу: под шапкой стоят вкладки, они белые и своей чертой
        // отделены от списка. Две линии подряд читались как рамка вокруг
        // пустой полосы.
        title: const Text('Документы'),
        shape: const Border(),
        bottom: _Tabs(controller: _tabs),
      ),
      body: RefreshIndicator(onRefresh: store.load, child: _body(store)),
      floatingActionButton: FloatingActionButton(
        key: _fabKey,
        heroTag: 'add',
        onPressed: _uploading ? null : _openDial,
        tooltip: 'Добавить накладную',
        child: _uploading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(LucideIcons.plus),
      ),
    );
  }

  Widget _body(DocumentsStore store) {
    if (store.isLoading && store.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (store.error != null) {
      return _scrollable(
        Message(
          icon: LucideIcons.cloud_off,
          title: 'Не удалось загрузить',
          note: store.error,
          onRetry: store.load,
        ),
      );
    }

    if (store.items.isEmpty) {
      return _scrollable(
        const Message(icon: LucideIcons.file_text, title: 'Накладных пока нет'),
      );
    }

    final rows = _groupByDay(store.items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows.length,
      itemBuilder: (_, index) {
        final row = rows[index];

        if (row is DateTime) {
          return _DayHeader(day: row);
        }

        final document = row as DocumentItem;

        return Slidable(
          key: ValueKey(document.id),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            // Кнопка занимает четверть ширины: строку при этом видно, и
            // понятно, какую именно накладную удаляют.
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => _delete(document),
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                icon: LucideIcons.trash_2,
                label: 'Удалить',
              ),
            ],
          ),
          child: _DocumentTile(
            document: document,
            onTap: () => _openDetails(document),
          ),
        );
      },
    );
  }

  /// Плоский список из заголовков дней и накладных под ними.
  ///
  /// Список приходит с сервера уже по убыванию времени, поэтому достаточно
  /// заметить смену дня — сортировать заново не нужно.
  List<Object> _groupByDay(List<DocumentItem> items) {
    final rows = <Object>[];
    DateTime? day;

    for (final item in items) {
      final created = item.createdAt;

      // Без времени загрузки строку девать некуда — оставляем в текущем дне,
      // а если дня ещё нет, она просто идёт первой.
      if (created != null) {
        final its = DateTime(created.year, created.month, created.day);

        if (its != day) {
          day = its;
          rows.add(its);
        }
      }

      rows.add(item);
    }

    return rows;
  }

  /// Пустому экрану тоже нужна прокрутка — иначе «потяните, чтобы обновить»
  /// не работает там, где оно нужнее всего.
  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (_, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: constraints.maxHeight, child: child),
    ),
  );
}

/// Заголовок дня между накладными.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        formatDayHeader(day),
        // Разрядки нет: её ставили ради прописных — вплотную набранный капс
        // слипается. Строчным она только рвёт слово на буквы.
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF737373),
        ),
      ),
    );
  }
}

/// Полоса вкладок под шапкой.
///
/// Обычный `TabBar`: плавное подчёркивание, правильные размеры нажатия и
/// поведение, к которому человек привык в других приложениях, — самодельная
/// полоса всё это повторяла руками и хуже. Настройками приводим его к нашему
/// виду: наш синий, серые невыбранные, подчёркивание во всю ширину вкладки.
///
/// Смахивания между вкладками нет намеренно: под ними не три готовых списка, а
/// один, который перечитывается с сервера с новым отбором. Тянуть пальцем то,
/// что появится через полсекунды, — обман.
class _Tabs extends StatelessWidget implements PreferredSizeWidget {
  const _Tabs({required this.controller});

  final TabController controller;

  /// Высота полосы. Вкладки — это управление, а не содержимое: чем меньше они
  /// откусывают у списка, тем лучше. Сорока двух точек хватает, чтобы попасть
  /// пальцем.
  static const double height = 42;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: TabBar(
        controller: controller,
        // Вкладки делят ширину поровну: подчёркивание тогда показывает не
        // только выбранную, но и какую долю списка она отбирает.
        labelColor: accentDark,
        unselectedLabelColor: const Color(0xFF737373),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        indicatorColor: accentDark,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.tab,
        // Черта под полосой: она белая, и без неё непонятно, где кончается
        // управление и начинаются документы. Эта же черта служит дорожкой, по
        // которой едет подчёркивание.
        dividerColor: const Color(0xFFE5E5E5),
        dividerHeight: 1,
        splashBorderRadius: BorderRadius.circular(6),
        tabs: [
          for (final tab in DocumentsTab.values)
            Tab(
              // Черта под полосой прибавляется к высоте вкладки — вычитаем её,
              // чтобы полоса целиком осталась той, что обещает `preferredSize`.
              height: height - 2,
              // На узких экранах треть ширины короче слова «Проверенные», и
              // подпись обрезалась бы. Уменьшить её лучше, чем показать
              // половину.
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(tab.label)),
            ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document, required this.onTap});

  final DocumentItem document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          // Свой фон обязателен: под строкой лежит красная кнопка удаления, и
          // сквозь прозрачную она просвечивала бы всегда, а не только на
          // свайпе.
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        // Две строки, а не две колонки. Колонки выравнивались `IntrinsicHeight`,
        // а он меряет высоту текста до переноса — у поставщиков с названием на
        // четыре строки мерка выходила на пиксель короче нужного, и внизу
        // вылезала полосатая лента переполнения. Здесь переполниться нечему:
        // каждая строка сама занимает столько, сколько просит.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Длинные названия («Товарищество с ограниченной
                // ответственностью …») переносим, а не обрезаем многоточием:
                // обрезанное имя не отличить от соседнего такого же.
                Expanded(
                  child: Text(
                    document.supplierOrDash,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      // Поставщика не прочитали — заголовок не имя, а сообщение
                      // об этом, и выделять его незачем.
                      color: document.supplier.isEmpty
                          ? const Color(0xFF737373)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Только время: дату несёт заголовок дня выше.
                Text(
                  document.createdAt == null
                      ? '—'
                      : formatTime(document.createdAt!),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF737373),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatMoney(document.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Плашкой, а не просто цветным текстом: строк в списке много,
                // и глаз ищет статус по форме быстрее, чем по оттенку букв.
                Container(
                  decoration: BoxDecoration(
                    color: document.status.background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        document.status.icon,
                        size: 13,
                        color: document.status.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        document.status.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: document.status.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Откуда взять снимок накладной.
enum _AddSource { camera, gallery }

/// Раскрытый список источников поверх затемнённого экрана.
///
/// Внизу — копия кнопки добавления: она стоит ровно на настоящей, чтобы плюс
/// на глазах повернулся в крестик, а не подменился другой кнопкой в стороне.
class _Dial extends StatelessWidget {
  const _Dial({required this.animation, required this.size});

  final Animation<double> animation;

  /// Размер настоящей кнопки — копия должна закрыть её целиком, иначе из-под
  /// края выглядывает затемнённый плюс.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _DialAction(
          icon: LucideIcons.camera,
          label: 'Сделать снимок',
          onTap: () => Navigator.of(context).pop(_AddSource.camera),
        ),
        const SizedBox(height: 12),
        _DialAction(
          icon: LucideIcons.images,
          label: 'Выбрать из галереи',
          onTap: () => Navigator.of(context).pop(_AddSource.gallery),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: size.width,
          height: size.height,
          child: FloatingActionButton(
            // Своей метки нет: с меткой настоящей кнопки Hero попытался бы
            // перелететь из неё в эту, хотя они стоят на одном месте.
            heroTag: null,
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Закрыть',
            child: RotationTransition(
              turns: Tween<double>(begin: 0, end: 0.125).animate(animation),
              child: const Icon(LucideIcons.plus),
            ),
          ),
        ),
      ],
    );
  }
}

/// Пункт раскрытого списка: подпись слева, круглая кнопка справа.
class _DialAction extends StatelessWidget {
  const _DialAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Подпись на своей плашке: список раскрывается поверх затемнённого
        // экрана, и белые буквы на нём читались бы, а тёмные — нет.
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          elevation: 2,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: null,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
