import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_nav.dart';

void main() {
  /// Раздел, выбранный в панели, — за ним и следим.
  Section? chosen;

  setUp(() => chosen = null);

  Future<void> pump(WidgetTester tester, {List<Section>? sections}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Документы')),
          bottomNavigationBar: AppBottomBar(
            sections: sections ?? Section.values,
            current: Section.documents,
            onSelect: (section) => chosen = section,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('разделы видны внизу без единого нажатия', (tester) async {
    await pump(tester);

    // Ради этого панель и заводили: раньше названия разделов лежали в шторке,
    // и о них нужно было знать заранее.
    expect(find.text('Документы'), findsWidgets);
    expect(find.text('Закупки'), findsOneWidget);
    expect(find.text('Помощник'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('выбор раздела уходит наверх', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Закупки'));
    await tester.pumpAndSettle();

    expect(chosen, Section.purchases);
  });

  testWidgets('тап по открытому разделу ничего не переоткрывает', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Документы').last);
    await tester.pumpAndSettle();

    expect(chosen, isNull);
  });

  testWidgets('закрытых разделов в панели нет вовсе', (tester) async {
    // Так панель выглядит у менеджера, пока доступ к закупкам и помощнику ему
    // не выдали: не серые пункты, по которым нельзя нажать, а два раздела.
    await pump(tester, sections: [Section.documents, Section.settings]);

    expect(find.text('Документы'), findsWidgets);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Закупки'), findsNothing);
    expect(find.text('Помощник'), findsNothing);
  });
}
