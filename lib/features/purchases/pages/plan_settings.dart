import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// За какой период смотрим продажи и на сколько дней закупаемся.
class PlanSettings {
  const PlanSettings({required this.days, required this.horizon});

  final int days;
  final int horizon;
}

/// Спрашивает период перед пересчётом.
///
/// Окно и кнопки берут оформление у платформы, как и остальные окна
/// приложения. Сами сроки остаются материальными «таблетками»: у Cupertino
/// такого элемента нет, а городить под iOS барабан ради двух чисел — менять
/// понятное на непривычное.
///
/// Спрашиваем каждый раз, а не считаем молча по прошлым числам: пересчёт ходит
/// в кабинет и удаляет прежний план, так что это не то действие, которое стоит
/// делать по одному нажатию.
///
/// Границы те же, что у сервера: дольше трёх месяцев смотреть бессмысленно —
/// ассортимент за это время меняется.
Future<PlanSettings?> askPlanSettings(
  BuildContext context, {
  required int days,
  required int horizon,
}) {
  return showAdaptiveDialog<PlanSettings>(
    context: context,
    builder: (context) => _SettingsDialog(days: days, horizon: horizon),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.days, required this.horizon});

  final int days;
  final int horizon;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late int _days = widget.days;
  late int _horizon = widget.horizon;

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text('Что посчитать'),
      // Обёртка обязательна: на iOS окно рисует `CupertinoAlertDialog`, а он
      // не даёт `Material` — и «таблетки» внутри падают с «No Material widget
      // found». Прозрачный `Material` их чинит, ничего не закрашивая.
      content: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Choice(
              label: 'Смотрим продажи за',
              value: _days,
              options: const [7, 14, 30, 60, 90],
              onChanged: (value) => setState(() => _days = value),
            ),
            const SizedBox(height: 16),
            _Choice(
              label: 'Закупаемся на',
              value: _horizon,
              options: const [7, 14, 21, 30, 60],
              onChanged: (value) => setState(() => _horizon = value),
            ),
          ],
        ),
      ),
      actions: [
        _Action(label: 'Отмена', onPressed: () => Navigator.of(context).pop()),
        _Action(
          label: 'Посчитать',
          onPressed: () => Navigator.of(
            context,
          ).pop(PlanSettings(days: _days, horizon: _horizon)),
        ),
      ],
    );
  }
}

/// Кнопка окна: на iOS это `CupertinoDialogAction`, иначе обычная.
///
/// `AlertDialog.adaptive` подменяет само окно, но не то, что внутри: положи
/// сюда `TextButton` — на iOS он и останется, с чужими отступами и без
/// разделителей между кнопками.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);

    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => CupertinoDialogAction(
        onPressed: onPressed,
        child: text,
      ),
      _ => TextButton(onPressed: onPressed, child: text),
    };
  }
}

/// Выбор из нескольких сроков. Готовые варианты вместо поля ввода: числа тут
/// круглые, а клавиатура на телефоне закрывает пол-окна.
///
/// Нынешнее значение добавляется к вариантам, даже если оно не круглое: план
/// могли посчитать с другого клиента, и без этого текущий срок просто не был
/// бы отмечен — а нажав «Посчитать», человек молча сменил бы его.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF737373))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final option in {...options, value}.toList()..sort())
              ChoiceChip(
                label: Text('$option дн.'),
                selected: option == value,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}
