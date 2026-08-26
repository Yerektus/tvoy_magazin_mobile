import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'app_theme.dart';

/// Разделы приложения. Порядок тот же, что в веб-кабинете, настройки — в
/// конце: туда заходят раз в месяц, а не каждую смену.
enum Section {
  documents('Документы', LucideIcons.file_text),
  purchases('Закупки', LucideIcons.shopping_cart),
  assistant('Помощник', LucideIcons.bot),
  settings('Настройки', LucideIcons.settings);

  const Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Нижняя панель разделов.
///
/// Раньше разделы жили в боковой шторке — как в веб-кабинете, где слева есть
/// свободная колонка. На телефоне её нет: до шторки нужно дотянуться до
/// верхнего угла и сперва догадаться, что она вообще есть. Разделы
/// равноправны, и внизу они видны всегда — и как список, и как указание,
/// где ты сейчас.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.sections,
    required this.current,
    required this.onSelect,
  });

  /// Какие разделы показывать. Не всегда все: закупки и помощник менеджеру
  /// закрыты, пока доступ не выдали, и панель у него короче.
  final List<Section> sections;

  /// Какой раздел открыт сейчас.
  final Section current;

  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Панель белая, как и список над ней, — без черты граница теряется.
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      child: NavigationBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: accentPale,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: sections.indexOf(current),
        onDestinationSelected: (index) {
          final section = sections[index];

          // Тап по открытому разделу ничего не меняет: перезапускать страницу
          // и терять набранное в ней незачем.
          if (section != current) {
            onSelect(section);
          }
        },
        destinations: [
          for (final section in sections)
            NavigationDestination(
              icon: Icon(
                section.icon,
                size: 22,
                color: const Color(0xFF737373),
              ),
              selectedIcon: Icon(section.icon, size: 22, color: accentDark),
              label: section.label,
            ),
        ],
      ),
    );
  }
}
