import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/documents/pages/capture_page.dart';

/// Ту же раскладку, что и на экране камеры, можно проверить без самой камеры:
/// `DocumentFrame` и `CaptureControls` рисуются поверх кадра и от него не
/// зависят. Настоящий предпросмотр в тестах не поднять — там нужен телефон.
void main() {
  Future<Rect> pumpAndReadWindow(
    WidgetTester tester,
    double height, {
    int pages = 0,
  }) async {
    tester.view.physicalSize = Size(1080, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Снимок накладной')),
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const DocumentFrame(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CaptureControls(
                  busy: false,
                  pages: pages,
                  onPressed: () {},
                  onSend: () {},
                  onUndo: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // `_FramePainter.window` — публичное поле приватного класса: имя класса
    // недоступно снаружи файла, но само поле — обычное, и dynamic до него
    // достаёт. Это единственный способ проверить то, что реально нарисовано,
    // не читая приватные детали через дублирующую логику в тесте.
    //
    // `CustomPaint` в дереве не один — Material рисует им тени и подсветку
    // нажатий, — поэтому берём именно тот, чей painter и есть наш `_FramePainter`.
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_FramePainter',
      ),
    );
    // ignore: avoid_dynamic_calls
    return (paint.painter as dynamic).window as Rect;
  }

  // Короткие экраны и воспроизводили баг: окно рамки забирало себе почти всю
  // высоту, и кнопка спуска оказывалась под ним, у самого края.
  for (final height in [1920.0, 1200.0, 812.0, 667.0, 600.0]) {
    testWidgets('на высоте ${height}px окно не заходит под кнопку спуска', (
      tester,
    ) async {
      final window = await pumpAndReadWindow(tester, height);
      final controlsTop = tester.getTopLeft(find.byType(CaptureControls)).dy;

      expect(
        window.bottom,
        lessThanOrEqualTo(controlsTop),
        reason: 'окно рамки залезло в зону кнопки спуска',
      );
      expect(window.height, greaterThanOrEqualTo(0));
      expect(window.width, greaterThan(0));
    });
  }

  // Снятые листы добавляют высоты нижнему блоку — окно рамки должно уступать
  // ей место так же, как уступает самой кнопке спуска.
  for (final height in [1920.0, 812.0, 600.0]) {
    testWidgets(
      'со снятыми листами на ${height}px окно тоже не заходит под кнопки',
      (tester) async {
        final window = await pumpAndReadWindow(tester, height, pages: 2);
        final controlsTop = tester.getTopLeft(find.byType(CaptureControls)).dy;

        expect(window.bottom, lessThanOrEqualTo(controlsTop));
      },
    );
  }

  testWidgets('пока ничего не снято, кнопок отправки и отмены нет', (
    tester,
  ) async {
    await pumpAndReadWindow(tester, 812);

    expect(find.text('Готово'), findsNothing);
    expect(find.text('Убрать'), findsNothing);
  });

  testWidgets('после первого кадра появляются счётчик и отправка', (
    tester,
  ) async {
    await pumpAndReadWindow(tester, 812, pages: 1);

    expect(find.text('Снят 1 лист'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Убрать'), findsOneWidget);
  });

  testWidgets('счётчик считает листы, а не кадры', (tester) async {
    await pumpAndReadWindow(tester, 812, pages: 3);

    expect(find.text('Снято листов: 3'), findsOneWidget);
  });
}
