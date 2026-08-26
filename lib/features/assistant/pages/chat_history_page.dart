import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../models/chat_message.dart';
import '../services/assistant_store.dart';

/// Прошлые разговоры с помощником.
///
/// Возвращает id выбранной переписки — открывает её не сама: страница
/// помощника и так умеет открывать любую, а двум местам знать об этом незачем.
class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key, required this.store});

  final AssistantStore store;

  /// Открывает историю и отдаёт выбранную переписку.
  static Future<int?> open(BuildContext context, AssistantStore store) =>
      Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => ChatHistoryPage(store: store)),
      );

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    _load();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.store.loadHistory();
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _remove(ChatSummary chat) async {
    final agreed = await confirm(
      context,
      title: 'Удалить переписку?',
      message: '«${chat.name}» сотрётся насовсем.',
      action: 'Удалить',
      dangerous: true,
    );

    if (!agreed || !mounted) {
      return;
    }

    try {
      await widget.store.remove(chat.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final chats = widget.store.chats;

    if (_loading && chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Message(
        icon: LucideIcons.cloud_off,
        title: 'Не удалось загрузить',
        note: _error,
        onRetry: _load,
      );
    }

    if (chats.isEmpty) {
      return const Message(
        icon: LucideIcons.list,
        title: 'Прошлых разговоров нет',
        note: 'Здесь будут те, что вы уже начинали',
      );
    }

    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (_, index) {
        final chat = chats[index];

        return _ChatTile(
          chat: chat,
          open: chat.id == widget.store.chatId,
          onTap: () => Navigator.of(context).pop(chat.id),
          onRemove: () => _remove(chat),
        );
      },
    );
  }
}

/// Строка истории: о чём был разговор и когда в нём говорили последний раз.
class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.open,
    required this.onTap,
    required this.onRemove,
  });

  final ChatSummary chat;

  /// Эта переписка открыта сейчас — её отмечаем, чтобы тап по ней не выглядел
  /// переходом в никуда.
  final bool open;

  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        chat.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: open ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: chat.updatedAt == null
          ? null
          : Text(
              open
                  ? 'Открыта · ${formatSentAt(chat.updatedAt!)}'
                  : formatSentAt(chat.updatedAt!),
              style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
            ),
      trailing: IconButton(
        onPressed: onRemove,
        icon: const Icon(LucideIcons.trash_2, size: 18),
        color: const Color(0xFFA3A3A3),
        tooltip: 'Удалить переписку',
      ),
    );
  }
}
