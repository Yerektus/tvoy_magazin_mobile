import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../auth/services/auth.dart';
import '../../umag/services/umag_store.dart';

/// Настройки: кто вошёл, в какой магазин уходят приёмки и как выйти.
///
/// Отдельным разделом, а не кружком в шапке. Кружок с буквой почты был
/// единственным входом в эти три вещи, и найти их там можно было только
/// случайно: он не подписан и на кнопку не похож.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.auth, required this.umag});

  final Auth auth;
  final UmagAccountStore umag;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.umag.addListener(_onChanged);
    widget.umag.load();
  }

  @override
  void dispose() {
    widget.umag.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _select(int storeId) async {
    try {
      await widget.umag.select(storeId);
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось сменить магазин',
          message: error.message,
        );
      }
    }
  }

  Future<void> _signOut() async {
    final agreed = await confirm(
      context,
      title: 'Выйти?',
      message: 'Придётся входить заново.',
      action: 'Выйти',
      dangerous: true,
    );

    if (agreed) {
      widget.umag.forget();
      widget.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user;
    final account = widget.umag.account;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Account(email: user?.email ?? ''),

          if (account.connected) ...[
            const _Caption('Магазин'),
            if (account.canSwitch)
              // Списком, а не выпадашкой: магазинов у компании единицы, и
              // выбор в один тап короче, чем «открыть список, выбрать».
              for (final store in account.stores)
                _StoreRow(
                  name: store.name,
                  selected: store.id == account.storeId,
                  enabled: !widget.umag.isBusy,
                  onTap: () => _select(store.id),
                )
            else
              // Магазин один — выбирать нечего, но знать, в какой уходят
              // приёмки, всё равно нужно.
              ListTile(
                leading: const Icon(
                  LucideIcons.store,
                  size: 20,
                  color: Color(0xFF737373),
                ),
                title: Text(account.storeName),
              ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE5E5E5)),
          ListTile(
            onTap: _signOut,
            leading: const Icon(
              LucideIcons.log_out,
              size: 20,
              color: Color(0xFFDC2626),
            ),
            title: const Text(
              'Выйти',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кто вошёл.
///
/// Только почта: по ней и входят. Имя под ней ничего не добавляло — своё имя
/// человек и так знает, а строку оно занимало.
class _Account extends StatelessWidget {
  const _Account({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final letter = email.isEmpty ? '?' : email.characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 18,
                color: accentDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подпись над группой настроек.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0xFFE5E5E5)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
          ),
        ),
      ],
    );
  }
}

/// Магазин, в который уходят приёмки.
class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final bool selected;

  /// Смена магазина уже идёт — второй раз нажимать нельзя, иначе два запроса
  /// разойдутся и в кабинете окажется не тот магазин.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: enabled && !selected ? onTap : null,
      title: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? accentDark : const Color(0xFF404040),
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? const Icon(LucideIcons.check, size: 18, color: accentDark)
          : null,
    );
  }
}
