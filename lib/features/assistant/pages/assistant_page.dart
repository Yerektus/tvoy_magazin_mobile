import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../models/chat_message.dart';
import '../services/assistant_store.dart';
import 'chat_history_page.dart';

/// Разговор с помощником: вопросы про накладные, поставщиков и закупки.
///
/// Помощник смотрит только данные своей организации, и смотрит их сам —
/// спрашивать его можно как человека, а не выбирать отчёт из списка.
///
/// Разговоров у человека много, и открыт всегда один: прошлые лежат в истории
/// и оттуда же продолжаются.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.store});

  final AssistantStore store;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    widget.store.load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(_toBottom);
    }
  }

  /// Прокручиваем к последней реплике после отрисовки: до неё высота списка
  /// ещё старая, и прокрутка встанет на середину новой.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _ask() async {
    final text = _input.text;

    if (text.trim().isEmpty) {
      return;
    }

    _input.clear();

    try {
      await widget.store.ask(text);
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Аналитик не ответил',
          message: error.message,
        );
      }
    }
  }

  /// Начинает новый разговор. Спрашивать согласия больше не за что: прежний
  /// не стирается, а уходит в историю, и вернуться в него — два нажатия.
  void _startNew() {
    if (widget.store.messages.isNotEmpty) {
      widget.store.startNew();
    }
  }

  /// Открывает историю и, если оттуда что-то выбрали, — саму переписку.
  Future<void> _openHistory() async {
    final chosen = await ChatHistoryPage.open(context, widget.store);

    if (chosen == null || !mounted || chosen == widget.store.chatId) {
      return;
    }

    await widget.store.openChat(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Помощник'),
        actions: [
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(LucideIcons.list, size: 20),
            tooltip: 'История разговоров',
          ),
          IconButton(
            onPressed: store.messages.isEmpty ? null : _startNew,
            icon: const Icon(LucideIcons.square_pen, size: 20),
            tooltip: 'Новый разговор',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _Input(controller: _input, busy: store.isThinking, onSend: _ask),
        ],
      ),
    );
  }

  Widget _body() {
    final store = widget.store;

    if (store.error != null) {
      return Message(
        icon: LucideIcons.cloud_off,
        title: 'Не удалось загрузить',
        note: store.error,
        onRetry: store.load,
      );
    }

    if (store.isLoading && store.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (store.messages.isEmpty) {
      return const _Empty();
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: store.messages.length + (store.isThinking ? 1 : 0),
      itemBuilder: (_, index) => index < store.messages.length
          ? _Bubble(message: store.messages[index])
          : const _Thinking(),
    );
  }
}

/// Пустая переписка.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bot, size: 40, color: Color(0xFFA3A3A3)),
            SizedBox(height: 12),
            Text(
              'Спросите про магазин',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Реплика: свой вопрос справа в синем пузыре, ответ аналитика — во всю
/// ширину без подложки.
///
/// Пузырь у ответа убран не для красоты. Аналитик отвечает таблицами, и в
/// пузыре шириной в четыре пятых экрана колонки сжимались так, что «Товар»
/// переносился по слогам. Своя реплика короткая, ей пузырь идёт; ответ —
/// это текст страницы, а не записка.
///
/// Свою реплику показываем как есть: человек пишет вопрос словами, а не
/// разметкой. Ответ аналитика разбираем как markdown — жирным он выделяет
/// заголовки разделов и важные числа, тире начинает списки.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return message.mine ? _mine(context) : _theirs(context);
  }

  Widget _mine(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              decoration: const BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  // Угол под хвостиком почти не скруглён: при полном радиусе
                  // между ним и хвостиком остаётся светлая щель.
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SelectableText(
                    message.text,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                  ),
                  if (message.createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatSentAt(message.createdAt!),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Хвостик: показывает, от кого реплика, даже когда она одна на
          // экране и сравнить её не с чем. Не у самого дна: висящий на нижнем
          // краю уголок читается как обрыв пузыря, а не как его хвост.
          const Padding(padding: EdgeInsets.only(bottom: 6), child: _Tail()),
        ],
      ),
    );
  }

  Widget _theirs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: message.text,
            selectable: true,
            styleSheet: _markdown(context),
          ),
          if (message.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                formatSentAt(message.createdAt!),
                style: const TextStyle(fontSize: 11, color: Color(0xFFA3A3A3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Хвостик синего пузыря — уголок у его правого нижнего края.
class _Tail extends StatelessWidget {
  const _Tail();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 7,
      height: 12,
      child: CustomPaint(painter: _TailPainter()),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Треугольник от нижнего угла пузыря вбок и вниз — тот же цвет, что и
    // пузырь, поэтому шва между ними не видно.
    final tail = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(tail, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}

/// Как выглядит разметка в ответе аналитика.
///
/// Больше жирного, списков и абзацев в ответах и не бывает — так просит
/// инструкция аналитика. Но если он всё же поставит заголовок или таблицу,
/// пузырь не должен из-за этого разъехаться: заголовки оставляем размером с
/// обычную строку, только жирнее.
MarkdownStyleSheet _markdown(BuildContext context) {
  const text = TextStyle(color: Color(0xFF171717), height: 1.4);
  final bold = text.copyWith(fontWeight: FontWeight.w600);

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: text,
    strong: bold,
    em: text.copyWith(fontStyle: FontStyle.italic),
    listBullet: text,
    a: text.copyWith(color: accent, decoration: TextDecoration.underline),
    h1: bold,
    h2: bold,
    h3: bold,
    h4: bold,
    h5: bold,
    h6: bold,
    // Колонки по содержимому, а не поровну: при равных долях «Выручка» и
    // «Продано» переносились по слогам, а сумма в две строки не читается.
    // На такой ширине пакет сам даёт таблице прокрутку вбок.
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tableBorder: TableBorder.all(color: const Color(0xFFE5E5E5), width: 1),
    tableHead: bold,
    tableBody: text,
    // Отступ между абзацами меньше пустой строки: разделов в ответе бывает
    // много, а пустая строка между ними разгоняет ответ на два экрана.
    blockSpacing: 8,
    listIndent: 16,
    h1Padding: EdgeInsets.zero,
    h2Padding: EdgeInsets.zero,
    h3Padding: EdgeInsets.zero,
    h4Padding: EdgeInsets.zero,
    h5Padding: EdgeInsets.zero,
    h6Padding: EdgeInsets.zero,
  );
}

/// Аналитик думает.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 16, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Смотрю данные…', style: TextStyle(color: Color(0xFF737373))),
          ],
        ),
      ),
    );
  }
}

/// Поле вопроса внизу экрана.
///
/// Без черты сверху и без своего фона: полоса под перепиской того же цвета,
/// что и она сама, — делить экран там нечего. Отделяет поле только его
/// собственная рамка.
///
/// Кнопка стоит внутри поля и мельче его: она относится к тому, что написано,
/// а не спорит с ним за внимание.
class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: TextField(
            controller: controller,
            // Вопрос бывает длинным, но поле не должно занимать пол-экрана.
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Спросите про магазин',
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
              // Кнопка не должна растягивать поле по высоте: у неё своя
              // область нажатия, и без ограничения строка становится выше.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 36,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  onPressed: busy ? null : onSend,
                  iconSize: 15,
                  icon: const Icon(LucideIcons.arrow_up, size: 15),
                  tooltip: 'Спросить',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: busy ? const Color(0xFFE5E5E5) : accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
