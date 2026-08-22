import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Спрашивает разрешение на то, что потом не отменить.
///
/// Возвращает `true`, только если человек выбрал согласие: закрытие окна мимо
/// кнопок — это отказ, а не молчаливое «да».
///
/// Оформление берём у платформы тем же способом, что и [showErrorDialog].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool dangerous = false,
}) async {
  final answer = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        _Action(
          label: 'Отмена',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        _Action(
          label: action,
          dangerous: dangerous,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );

  return answer ?? false;
}

/// Кнопка окна: на iOS это `CupertinoDialogAction`, иначе обычная.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.dangerous = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool dangerous;

  @override
  Widget build(BuildContext context) {
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => CupertinoDialogAction(
          onPressed: onPressed,
          isDestructiveAction: dangerous,
          child: Text(label),
        ),
      _ => TextButton(
          onPressed: onPressed,
          child: Text(
            label,
            style: dangerous ? const TextStyle(color: Color(0xFFDC2626)) : null,
          ),
        ),
    };
  }
}
