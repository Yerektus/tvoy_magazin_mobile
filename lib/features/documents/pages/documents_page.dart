import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/message.dart';
import '../../auth/services/auth.dart';
import '../../umag/services/umag_store.dart';
import '../models/document.dart';
import '../models/shot.dart';
import '../services/documents_store.dart';
import 'capture_page.dart';
import 'document_details_page.dart';

/// Список накладных организации: их видит вся смена, а не только тот, кто
/// загрузил.
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({
    super.key,
    required this.auth,
    required this.store,
    required this.umag,
  });

  final Auth auth;
  final DocumentsStore store;
  final UmagAccountStore umag;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  /// Гуляет отдельно от `store.isLoading`: тот про список, а не про то, что
  /// прямо сейчас грузится фото из галереи.
  bool _uploading = false;

  /// Раскрыт ли FAB. Живёт здесь, а не в самом FAB: тап по затемнению фона
  /// должен его закрывать, а затемнение рисует эта страница, не кнопка.
  bool _dialOpen = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    widget.store.load();
    // Список магазинов UMAG нужен не меню, а ссылке на черновик приёмки: в её
    // адресе стоит порядковый номер магазина. Раньше он читался только при
    // открытии бокового меню — кто его не открывал, получал ссылку на первый
    // магазин вместо своего.
    widget.umag.load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleDial() => setState(() => _dialOpen = !_dialOpen);

  void _closeDial() => setState(() => _dialOpen = false);

  /// Выбрали действие в раскрытом FAB — сворачиваем его и запускаем то, что
  /// выбрали.
  void _choose(VoidCallback action) {
    _closeDial();
    action();
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

  /// Список обновляет сам `DocumentsStore` после загрузки, поэтому здесь
  /// остаётся только сказать, что снимок принят.
  Future<void> _openCamera() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CapturePage(store: widget.store)),
    );

    if (added == true && mounted) {
      _announceUploaded();
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);

    // Открыли галерею и передумали — не ошибка, а обычный отказ.
    if (file == null) {
      return;
    }

    setState(() => _uploading = true);

    try {
      await widget.store.upload([
        Shot(
          bytes: await file.readAsBytes(),
          filename: file.name,
          contentType: _contentTypeOf(file),
        ),
      ]);

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
      // Выход переехал в боковое меню: в шапке ему было слишком легко попасть
      // под палец, а рядом с ним теперь стоит и выбор магазина.
      drawer: AppDrawer(auth: widget.auth, umag: widget.umag),
      appBar: AppBar(title: const Text('Документы')),
      body: Stack(
        children: [
          Column(
            children: [
              _Tabs(store: store),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: store.load,
                  child: _body(store),
                ),
              ),
            ],
          ),
          // Открыли FAB — гасим список, чтобы он не отвлекал и не откликался
          // на тапы мимо кнопок. Тап по самому затемнению закрывает FAB же.
          // Барьер стоит в дереве всегда — так `AnimatedOpacity` есть от чего
          // отталкиваться и в появлении, и в исчезновении, а не выскакивает
          // сразу непрозрачным.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_dialOpen,
              child: GestureDetector(
                onTap: _closeDial,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _dialOpen ? 1 : 0,
                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _AddFab(
        open: _dialOpen,
        busy: _uploading,
        onToggle: _toggleDial,
        onCamera: () => _choose(_openCamera),
        onGallery: () => _choose(_pickFromGallery),
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
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить',
          note: store.error,
          onRetry: store.load,
        ),
      );
    }

    if (store.items.isEmpty) {
      return _scrollable(
        const Message(
          icon: Icons.description_outlined,
          title: 'Накладных пока нет',
        ),
      );
    }

    final rows = _groupByDay(store.items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows.length,
      itemBuilder: (_, index) {
        final row = rows[index];

        return row is DateTime
            ? _DayHeader(day: row)
            : _DocumentTile(
                document: row as DocumentItem,
                onTap: () => _openDetails(row),
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
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
          color: Color(0xFF737373),
        ),
      ),
    );
  }
}

/// Полоса вкладок под панелью.
///
/// Прокручивается вбок: вкладок три, но названия длинные, и на узком экране
/// они не помещаются в ряд.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.store});

  final DocumentsStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        // Полоса вкладок и список одинаково белые и без черты сливаются —
        // непонятно, где кончается управление и начинаются документы. Эта же
        // черта служит дорожкой, по которой едет подчёркивание выбранной.
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      // Вкладки делят ширину поровну: подчёркивание тогда показывает не только
      // выбранную вкладку, но и какую долю списка она отбирает. Прокрутки нет —
      // вкладок три, и все подписи короткие.
      child: Row(
        children: [
          for (final tab in DocumentsTab.values)
            Expanded(
              child: _Tab(
                label: tab.label,
                selected: store.tab == tab,
                onSelected: () => store.select(tab),
              ),
            ),
        ],
      ),
    );
  }
}

/// Вкладка списка.
///
/// Подчёркивание, а не пилюля — как в веб-кабинете. У пилюль каждая вкладка
/// была обведена рамкой, и три обведённых овала спорили с карточками
/// документов под ними: глаз считал их за одинаковые по важности. Подчёркнута
/// только выбранная, остальные — просто текст.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              // Прозрачная полоса у невыбранных, а не отсутствие полосы: иначе
              // высота вкладок отличалась бы на два пикселя и текст дёргался
              // при переключении.
              color: selected ? turquoiseDark : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        // На узких экранах треть ширины короче слова «Проверенные», и подпись
        // обрезалась бы. Уменьшить её лучше, чем показать половину.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: selected ? turquoiseDark : const Color(0xFF737373),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
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
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
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
                Icon(
                  document.status.icon,
                  size: 14,
                  color: document.status.color,
                ),
                const SizedBox(width: 4),
                Text(
                  document.status.label,
                  style: TextStyle(fontSize: 12, color: document.status.color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка добавления накладной с раскрывающимся списком.
///
/// Состояние «раскрыт» приходит снаружи, а не живёт здесь: затемнение фона
/// рисует страница, и тап по нему должен сворачивать список — значит знать про
/// него обязаны оба.
class _AddFab extends StatelessWidget {
  const _AddFab({
    required this.open,
    required this.busy,
    required this.onToggle,
    required this.onCamera,
    required this.onGallery,
  });

  final bool open;

  /// Идёт загрузка снимка из галереи — второй раз нажимать нельзя.
  final bool busy;

  final VoidCallback onToggle;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Список появляется и исчезает вместе с высотой: без `AnimatedSize`
        // кнопка прыгала бы вниз рывком.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: open
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _DialAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Сделать снимок',
                      onTap: onCamera,
                    ),
                    const SizedBox(height: 12),
                    _DialAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Выбрать из галереи',
                      onTap: onGallery,
                    ),
                    const SizedBox(height: 16),
                  ],
                )
              : const SizedBox(width: 0, height: 0),
        ),
        FloatingActionButton(
          heroTag: 'add',
          onPressed: busy ? null : onToggle,
          tooltip: 'Добавить накладную',
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              // Плюс поворачивается в крестик: одна и та же кнопка и открывает
              // список, и закрывает его.
              : AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: open ? 0.125 : 0,
                  child: const Icon(Icons.add),
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
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
