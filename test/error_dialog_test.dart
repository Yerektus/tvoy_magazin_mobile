import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/error_dialog.dart';

/// Открывает диалог на заданной платформе и отдаёт управление тесту.
Future<void> _open(WidgetTester tester, TargetPlatform platform) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showErrorDialog(context, message: 'Сервер недоступен'),
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('на iOS окно родное для системы', (tester) async {
    await _open(tester, TargetPlatform.iOS);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    // Кнопка тоже должна быть купертиновской: адаптивным бывает само окно, а
    // содержимое ему безразлично.
    expect(
      find.widgetWithText(CupertinoDialogAction, 'Понятно'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Понятно'), findsNothing);
    expect(find.text('Сервер недоступен'), findsOneWidget);
  });

  testWidgets('на Android окно материальное', (tester) async {
    await _open(tester, TargetPlatform.android);

    // `AlertDialog.adaptive` рисует приватный `_AdaptiveAlertDialog`, поэтому
    // сверяемся не с ним, а с тем, что видно: материальное окно и своя кнопка.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.widgetWithText(TextButton, 'Понятно'), findsOneWidget);
    expect(find.text('Сервер недоступен'), findsOneWidget);
  });

  testWidgets('кнопка закрывает окно', (tester) async {
    await _open(tester, TargetPlatform.android);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Сервер недоступен'), findsNothing);
  });
}
