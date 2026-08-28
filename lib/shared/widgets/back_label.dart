import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Кнопка возврата с подписью: «‹ Документы».
///
/// Одна стрелка не говорит, куда именно вернёт, — а экранов, с которых можно
/// уйти в разные места, у нас хватает: позицию открывают из накладной, а
/// накладную из списка. Подпись снимает этот вопрос заранее.
///
/// Ставится в `title` шапки, а не в `leading`: ширина у неё своя на каждом
/// экране, а `leading` — фиксированный квадрат, в который подпись не влезает.
class BackLabel extends StatelessWidget {
  const BackLabel(this.label, {super.key});

  /// Куда вернётся человек: название того экрана, а не действие.
  final String label;

  @override
  Widget build(BuildContext context) {
    // Без `Flexible` снаружи: виджет ставят и в `Row` шапки, и одиночным
    // заголовком — а `Flexible` вне ряда роняет раскладку.
    return InkWell(
      onTap: () => Navigator.of(context).maybePop(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.chevron_left, size: 32),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
