import 'package:flutter/material.dart';

import '../../features/auth/services/auth.dart';
import '../../features/umag/models/umag_account.dart';
import '../../features/umag/services/umag_store.dart';
import '../services/api_exception.dart';
import 'app_theme.dart';
import 'error_dialog.dart';

/// Боковое меню — то же, что колонка слева в веб-кабинете.
///
/// Разделов пока один. Держать ради него целое меню кажется лишним, но выбор
/// магазина и выход должны где-то жить, а в шапке им тесно: там уже стоит
/// название страницы. Появятся закупки и остатки — им сюда же.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, required this.auth, required this.umag});

  final Auth auth;
  final UmagAccountStore umag;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
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

  Future<void> _select(int? storeId) async {
    if (storeId == null) {
      return;
    }

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

  void _signOut() {
    // Меню закрываем до выхода: иначе оно уезжает вместе со всем экраном и
    // на месте списка на мгновение показывается пустая шторка.
    Navigator.of(context).pop();
    widget.umag.forget();
    widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user;
    final account = widget.umag.account;

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onClose: () => Navigator.of(context).pop()),
            const SizedBox(height: 8),

            // Раздел пока один, и он же открыт — поэтому никуда не ведёт, а
            // только показывает, где мы находимся.
            _NavItem(
              icon: Icons.description_outlined,
              label: 'Документы',
              selected: true,
              onTap: () => Navigator.of(context).pop(),
            ),

            const Spacer(),

            if (account.canSwitch)
              _StorePicker(
                stores: account.stores,
                value: account.storeId,
                enabled: !widget.umag.isBusy,
                onChanged: _select,
              ),

            const Divider(height: 1, color: Color(0xFFE5E5E5)),
            _AccountRow(email: user?.email ?? '', onSignOut: _signOut),
          ],
        ),
      ),
    );
  }
}

/// Название приложения и организация, в которую вошли.
class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Твой магазин',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          // Закрыть меню можно и тапом по затемнению, и свайпом, но об этом
          // нужно догадаться. Кнопка догадки не требует.
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 22),
            color: const Color(0xFF737373),
            tooltip: 'Закрыть меню',
          ),
        ],
      ),
    );
  }
}

/// Пункт навигации.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: selected ? const Color(0xFFF0FDFA) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? turquoiseDark : const Color(0xFF737373),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? turquoiseDark : const Color(0xFF404040),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Выбор магазина, в который уходят приёмки.
class _StorePicker extends StatelessWidget {
  const _StorePicker({
    required this.stores,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<UmagStore> stores;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              'МАГАЗИН',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                color: Color(0xFFA3A3A3),
              ),
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
              ),
            ),
            items: [
              for (final store in stores)
                DropdownMenuItem<int>(
                  value: store.id,
                  child: Text(
                    store.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// Кто вошёл. Нажатие открывает меню с выходом.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.email, required this.onSignOut});

  final String email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Меню профиля',
      position: PopupMenuPosition.over,
      onSelected: (_) => onSignOut(),
      itemBuilder: (context) => [
        const PopupMenuItem<void>(
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Text('Выйти', style: TextStyle(color: Color(0xFFDC2626))),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            _Avatar(label: email),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFF737373)),
              ),
            ),
            const Icon(Icons.more_vert, size: 20, color: Color(0xFFA3A3A3)),
          ],
        ),
      ),
    );
  }
}

/// Кружок с первой буквой почты — вместо картинки, которой у нас нет.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final letter = label.isEmpty ? '?' : label.characters.first.toUpperCase();

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFCCFBF1),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: turquoiseDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
