import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/confirm_dialog.dart';

/// Куда падает ответ: `confirm` отдаёт его в замыкание кнопки, а не тесту.
class _Answer {
  bool? value;
}

/// Открывает вопрос на заданной платформе и отдаёт управление тесту.
Future<_Answer> _ask(
  WidgetTester tester,
  TargetPlatform platform, {
  bool dangerous = false,
}) async {
  final answer = _Answer();

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              answer.value = await confirm(
                context,
                title: 'Удалить позицию?',
                message: 'Лаваш',
                action: 'Удалить',
                dangerous: dangerous,
              );
            },
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();

  return answer;
}

void main() {
  testWidgets('на iOS окно родное для системы', (tester) async {
    await _ask(tester, TargetPlatform.iOS);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    // Кнопки тоже должны быть купертиновскими: адаптивным бывает само окно, а
    // содержимое ему безразлично.
    expect(find.widgetWithText(CupertinoDialogAction, 'Удалить'), findsOneWidget);
    expect(find.widgetWithText(CupertinoDialogAction, 'Отмена'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Удалить'), findsNothing);
  });

  testWidgets('на Android окно материальное', (tester) async {
    await _ask(tester, TargetPlatform.android);

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.widgetWithText(TextButton, 'Удалить'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Отмена'), findsOneWidget);
  });

  testWidgets('на iOS опасное действие помечает система, а не мы', (tester) async {
    await _ask(tester, TargetPlatform.iOS, dangerous: true);

    final button = tester.widget<CupertinoDialogAction>(
      find.widgetWithText(CupertinoDialogAction, 'Удалить'),
    );

    expect(button.isDestructiveAction, isTrue);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('на $platform согласие и отказ отвечают по-разному', (tester) async {
      final yes = await _ask(tester, platform);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(yes.value, isTrue);

      final no = await _ask(tester, platform);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(no.value, isFalse);
    });
  }

  testWidgets('закрытие мимо кнопок — отказ, а не молчаливое согласие', (tester) async {
    final answer = await _ask(tester, TargetPlatform.android);

    // Тап по затемнению вокруг окна.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(answer.value, isFalse);
  });
}
