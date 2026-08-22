import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Показывает ошибку окном поверх экрана — родным для системы.
///
/// Строкой под полем такое сообщение легко пропустить: оно появляется ниже
/// сгиба, а на телефоне его вдобавок закрывает клавиатура. Окно требует
/// закрыть себя — значит, его прочитали.
///
/// `showAdaptiveDialog` и `AlertDialog.adaptive` берут оформление у платформы:
/// на iOS выходит `CupertinoAlertDialog` со своим затемнением и анимацией, на
/// остальных — материальный. Своей вёрстки под каждую систему не пишем.
Future<void> showErrorDialog(
  BuildContext context, {
  required String message,
  String title = 'Не удалось войти',
}) {
  return showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      // Иконку рисует только материальная версия: у Cupertino в шапке окна
      // ничего, кроме заголовка, не предусмотрено — она её просто не берёт.
      icon: const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 32),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actions: [_CloseAction(onPressed: () => Navigator.of(context).pop())],
    ),
  );
}

/// Кнопка окна: на iOS это `CupertinoDialogAction`, иначе обычная.
///
/// `AlertDialog.adaptive` подменяет само окно, но не то, что внутри: положи
/// сюда `TextButton` — на iOS он и останется, с чужими отступами и без
/// разделителей между кнопками.
///
/// Платформу спрашиваем у темы, а не у `dart:io`. Тем же источником пользуется
/// `AlertDialog.adaptive`, и брать разные значило бы однажды получить
/// материальную кнопку внутри купертиновского окна. Заодно это работает на
/// вебе, где `Platform` недоступен.
class _CloseAction extends StatelessWidget {
  const _CloseAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const label = Text('Понятно');

    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS =>
        CupertinoDialogAction(onPressed: onPressed, child: label),
      _ => TextButton(onPressed: onPressed, child: label),
    };
  }
}
