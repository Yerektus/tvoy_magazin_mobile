import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../models/chat_message.dart';
import '../services/assistant_store.dart';

/// Разговор с аналитиком: вопросы про накладные, поставщиков и закупки.
///
/// Аналитик смотрит только данные своей организации, и смотрит их сам —
/// спрашивать его можно как человека, а не выбирать отчёт из списка.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.store, required this.drawer});

  final AssistantStore store;
  final Widget drawer;

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

  Future<void> _clear() async {
    final agreed = await confirm(
      context,
      title: 'Начать заново?',
      message: 'Переписка сотрётся.',
      action: 'Начать',
      dangerous: true,
    );

    if (agreed && mounted) {
      await widget.store.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: const Text('Аналитик'),
        actions: [
          if (store.messages.isNotEmpty)
            IconButton(
              onPressed: _clear,
              icon: const Icon(LucideIcons.trash_2, size: 20),
              tooltip: 'Начать заново',
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
            Icon(LucideIcons.message_square, size: 40, color: Color(0xFFA3A3A3)),
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

/// Реплика: своя справа на синем, ответ аналитика слева на сером.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: message.mine ? accent : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: message.mine ? Colors.white : const Color(0xFF171717),
            height: 1.4,
          ),
        ),
      ),
    );
  }
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
