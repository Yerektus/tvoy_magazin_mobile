import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/widgets/app_theme.dart';
import '../../documents/models/document.dart' show formatDateTime;

/// Что считать: за какой период смотрим продажи, на сколько закупаемся и брать
/// ли в расчёт то, что уже лежит на полке.
class PlanSettings {
  const PlanSettings({
    required this.days,
    required this.horizon,
    required this.useStock,
  });

  final int days;
  final int horizon;
  final bool useStock;
}

/// Условия анализа — с них начинается раздел закупок.
///
/// Не окно поверх списка и не отдельный экран: пересчёт ходит в кабинет за
/// товарным отчётом, стирает прежний план и считается небыстро, так что это и
/// есть первый шаг работы. Человек видит все три условия сразу и только потом
/// получает отчёт.
class PlanSettingsForm extends StatefulWidget {
  const PlanSettingsForm({
    super.key,
    required this.days,
    required this.horizon,
    required this.useStock,
    required this.onCount,
    this.onOpenLast,
    this.lastCountedAt,
  });

  final int days;
  final int horizon;
  final bool useStock;

  /// Условия заданы — считаем.
  final ValueChanged<PlanSettings> onCount;

  /// Открыть прошлый отчёт, не считая заново. Пусто — считать ещё не начинали.
  final VoidCallback? onOpenLast;

  /// Когда посчитали в прошлый раз.
  final DateTime? lastCountedAt;

  @override
  State<PlanSettingsForm> createState() => _PlanSettingsFormState();
}

class _PlanSettingsFormState extends State<PlanSettingsForm> {
  late double _days = widget.days.toDouble();
  late double _horizon = widget.horizon.toDouble();
  late bool _useStock = widget.useStock;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Slider(
          label: 'Смотрим продажи за',
          value: _days,
          // Границы те же, что у сервера: дольше трёх месяцев смотреть
          // бессмысленно — ассортимент за это время меняется.
          min: 7,
          max: 90,
          note:
              'Чем длиннее период, тем ровнее средний расход. Короткий '
              'быстрее замечает новинки и сезон.',
          onChanged: (value) => setState(() => _days = value),
        ),
        const SizedBox(height: 24),
        _Slider(
          label: 'Закупаемся на',
          value: _horizon,
          min: 1,
          max: 60,
          note: 'На сколько дней вперёд должно хватить заказа.',
          onChanged: (value) => setState(() => _horizon = value),
        ),
        const SizedBox(height: 8),
        _Stock(
          value: _useStock,
          onChanged: (value) => setState(() => _useStock = value),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => widget.onCount(
            PlanSettings(
              days: _days.round(),
              horizon: _horizon.round(),
              useStock: _useStock,
            ),
          ),
          icon: const Icon(LucideIcons.calculator, size: 18),
          label: const Text('Посчитать'),
        ),

        // Прошлый отчёт никуда не делся: считать заново ради того, чтобы его
        // перечитать, — это лишняя ходка в кабинет и минута ожидания.
        if (widget.onOpenLast != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onOpenLast,
            icon: const Icon(LucideIcons.file_text, size: 18),
            label: Text(
              widget.lastCountedAt == null
                  ? 'Открыть прошлый отчёт'
                  : 'Прошлый отчёт от ${formatDateTime(widget.lastCountedAt!)}',
            ),
          ),
        ],
      ],
    );
  }
}

/// Срок в днях: подпись, число и сам ползунок.
class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.note,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String note;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${value.round()} дн.',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: accentDark,
              ),
            ),
          ],
        ),
        Slider(
          // Новый вид ползунка: толстая дорожка, зазор у бегунка и засечка на
          // конце. Старый рисовал тонкую линию с кружком — на неё труднее
          // попасть пальцем, а разница между «30» и «60» читалась хуже.
          // ignore: deprecated_member_use — флаг и нужен, чтобы отключить вид 2023 года
          year2023: false,
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: onChanged,
        ),
        Text(
          note,
          style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
        ),
      ],
    );
  }
}

/// Брать ли в расчёт остаток на полке.
class _Stock extends StatelessWidget {
  const _Stock({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Учитывать остаток',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        value
            ? 'Из потребности вычтем то, что уже лежит на полке.'
            : 'Закажем весь запас заново, не глядя на полку.',
        style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
      ),
    );
  }
}
