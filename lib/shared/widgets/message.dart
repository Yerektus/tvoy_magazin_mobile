import 'package:flutter/material.dart';

/// Экран вместо содержимого: пусто, ошибка, «ещё не загрузили».
class Message extends StatelessWidget {
  const Message({
    super.key,
    required this.icon,
    required this.title,
    this.note,
    this.onRetry,
    this.retryLabel = 'Повторить',
  });

  final IconData icon;
  final String title;
  final String? note;
  final VoidCallback? onRetry;

  /// Подпись на кнопке. По умолчанию «Повторить» — но не всякое действие
  /// повтор: с пустой страницы закупов план считают в первый раз.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFA3A3A3)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(
                note!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF737373)),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
