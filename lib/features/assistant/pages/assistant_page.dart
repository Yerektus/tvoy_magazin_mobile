import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../models/chat_message.dart';
import '../services/assistant_store.dart';
import 'chat_history_page.dart';

/// Вопросы, с которых начинают, пока аналитик ещё ничего не ответил.
const _starters = [
  'Что заканчивается на полке?',
  'Что продаётся лучше всего?',
  'Сколько накладных за месяц?',
];

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

  /// Пока аналитик думал, ответ ещё не на экране. Когда думание кончилось —
  /// эту реплику показываем с появлением, прошлые при открытии истории нет.
  /// Свой вопрос — в момент отправки, по той же анимации.
  bool _wasThinking = false;
  int? _sendingId;
  int? _arrivingId;

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
    final thinking = widget.store.isThinking;
    var sending = _sendingId;
    var arriving = _arrivingId;
    final messages = widget.store.messages;
    final last = messages.isEmpty ? null : messages.last;

    if (thinking && !_wasThinking) {
      sending = last != null && last.mine ? last.id : null;
      arriving = null;
    } else if (!thinking && _wasThinking) {
      arriving = last != null && !last.mine ? last.id : null;
      sending = null;
    }

    _wasThinking = thinking;
    _sendingId = sending;
    _arrivingId = arriving;

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

  Future<void> _askPrompt(String text) async {
    _input.text = text;
    await _ask();
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
        // Черты под шапкой нет: от переписки её отделяют сами реплики, а не
        // линия. Действия собраны в группу с рамкой — как в кабинете.
        shape: const Border(),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Color(0xFFE5E5E5)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _openHistory,
                    icon: const Icon(LucideIcons.list, size: 20),
                    tooltip: 'История разговоров',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const ColoredBox(
                    color: Color(0xFFE5E5E5),
                    child: SizedBox(width: 1, height: 20),
                  ),
                  IconButton(
                    onPressed: store.messages.isEmpty ? null : _startNew,
                    icon: const Icon(LucideIcons.square_pen, size: 20),
                    tooltip: 'Новый разговор',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          if (store.isThinking) const _Thinking(),
          if (store.messages.isEmpty &&
              !store.isThinking &&
              !store.isLoading &&
              store.error == null)
            _Prompts(questions: _starters, onPick: _askPrompt),
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
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: store.messages.length,
      itemBuilder: (_, index) {
        final message = store.messages[index];
        final last = index == store.messages.length - 1;

        return _Bubble(
          key: ValueKey(message.id),
          message: message,
          arrive: message.id == _sendingId || message.id == _arrivingId,
          onPick: last && !message.mine && !store.isThinking
              ? _askPrompt
              : null,
        );
      },
    );
  }
}

/// Пустая переписка.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.bot, size: 40, color: Color(0xFFA3A3A3)),
            const SizedBox(height: 12),
            Text(
              'Спросите про магазин',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Реплика: свой вопрос без пузыря и без аватара; ответ помощника — на серой
/// подложке с искрой и подписью, во всю ширину.
///
/// Пузырь у ответа убран не для красоты. Аналитик отвечает таблицами, и в
/// узкой колонке колонки сжимались так, что «Товар» переносился по слогам.
/// Своя реплика короткая и без подложки читается как в обычном чате с ИИ;
/// ответ — это текст страницы, а не записка.
///
/// Свою реплику показываем как есть: человек пишет вопрос словами, а не
/// разметкой. Ответ аналитика разбираем как markdown — жирным он выделяет
/// заголовки разделов и важные числа, тире начинает списки.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    this.onPick,
    this.arrive = false,
  });

  final ChatMessage message;

  /// Есть — это последний ответ, и предложенные вопросы можно нажать.
  final ValueChanged<String>? onPick;

  /// Только что отправленный вопрос или только что пришедший ответ.
  final bool arrive;

  @override
  Widget build(BuildContext context) {
    return _arrive(message.mine ? _mine() : _theirs(context));
  }

  Widget _arrive(Widget child) {
    return _Arrive(play: arrive, child: child);
  }

  Widget _mine() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SelectableText(
        message.text,
        style: const TextStyle(
          color: Color(0xFF171717),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _theirs(BuildContext context) {
    final questions = onPick == null ? const <String>[] : message.suggestions;

    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AssistantLabel(),
            const SizedBox(height: 10),
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: _markdown(context),
            ),
            if (message.file != null) ...[
              const SizedBox(height: 12),
              _FileCard(url: message.file!, name: message.fileName ?? 'Отчёт.xlsx'),
            ],
            if (questions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Prompts(questions: questions, onPick: onPick!, padded: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Карточка Excel: нажатие открывает файл снаружи, как ссылку на кабинет.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              const Icon(
                LucideIcons.file_spreadsheet,
                size: 18,
                color: Color(0xFF047857),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF171717),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      await showErrorDialog(
        context,
        title: 'Не удалось открыть файл',
        message: 'Откройте вручную: $url',
      );
    }
  }
}

/// Появление ответа: снизу и из прозрачности — как подписи в кабинете.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!play || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Искра и имя — чтобы ответ не сливался со следующим вопросом.
class _AssistantLabel extends StatelessWidget {
  const _AssistantLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(LucideIcons.sparkles, size: 14, color: assistantAccent),
        SizedBox(width: 6),
        Text(
          'Помощник',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF171717),
          ),
        ),
      ],
    );
  }
}

/// Как выглядит разметка в ответе аналитика.
///
/// Больше жирного, списков и абзацев в ответах и не бывает — так просит
/// инструкция аналитика. Но если он всё же поставит заголовок или таблицу,
/// ответ не должен из-за этого разъехаться: заголовки оставляем размером с
/// обычную строку, только жирнее.
MarkdownStyleSheet _markdown(BuildContext context) {
  const text = TextStyle(color: Color(0xFF171717), fontSize: 14, height: 1.4);
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

/// Помощник печатает ответ — полоса над полем, не уезжает со скроллом.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ColoredBox(
        color: const Color(0xFFE5E5E5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              _Dots(animation: _beat),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Помощник пишет ответ...',
                  style: TextStyle(fontSize: 14, color: Color(0xFF737373)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Три точки по очереди вспыхивают — как в обычном чате.
class _Dots extends StatelessWidget {
  const _Dots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(lift: _lift(0)),
          const SizedBox(width: 3),
          _Dot(lift: _lift(0.15)),
          const SizedBox(width: 3),
          _Dot(lift: _lift(0.3)),
        ],
      ),
    );
  }

  /// 0 — точка внизу и тусклая, 1 — поднялась и ярче.
  double _lift(double delay) {
    final t = (animation.value + 1 - delay) % 1;
    if (t < 0.4) {
      return t / 0.4;
    }
    if (t < 0.8) {
      return 1 - (t - 0.4) / 0.4;
    }
    return 0;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.lift});

  final double lift;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.3 + 0.7 * lift,
      child: Transform.translate(
        offset: Offset(0, -3 * lift),
        child: const SizedBox(
          width: 6,
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF737373),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Предложенные вопросы: нажал — ушло как обычный вопрос.
class _Prompts extends StatelessWidget {
  const _Prompts({
    required this.questions,
    required this.onPick,
    this.padded = true,
  });

  final List<String> questions;
  final ValueChanged<String> onPick;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final buttons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _Prompt(question: questions[i], onPick: onPick),
        ],
      ],
    );

    if (!padded) {
      return buttons;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: buttons,
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.question, required this.onPick});

  final String question;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      child: InkWell(
        onTap: () => onPick(question),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF171717),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.arrow_right,
                size: 16,
                color: Color(0xFFA3A3A3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Поле вопроса внизу экрана. Кнопка стоит внутри него — относится к тому,
/// что написано, а не живёт отдельной колонкой справа.
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
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: TextField(
            controller: controller,
            enabled: !busy,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Введите свой вопрос...',
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              // Иначе кнопка растягивает поле по высоте: минимум у суффикса
              // считается по теме кнопки (48), а не по строке текста.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilledButton(
                  onPressed: busy ? null : onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Спросить'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
