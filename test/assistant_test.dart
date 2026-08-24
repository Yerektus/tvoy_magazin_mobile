import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/assistant/pages/assistant_page.dart';
import 'package:tvoy_magazin_mobile/features/assistant/services/assistant_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_theme.dart';

/// Подменяет сеть: помнит вопросы и отвечает заданным текстом.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.history = const [],
    this.answer = 'За месяц 60 накладных.',
    this.delay = Duration.zero,
  });

  final List<Map<String, dynamic>> history;
  final String answer;

  /// Насколько сервер задумывается. Ноль — мгновенно, и тогда состояния
  /// «аналитик думает» на экране просто не бывает: проверять в нём нечего.
  final Duration delay;
  final List<Object> asked = [];
  int deletes = 0;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    return <String, dynamic>{'messages': history};
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    asked.add(body);
    await Future<void>.delayed(delay);
    final text = (body as Map)['text'];

    return <String, dynamic>{
      'messages': [
        {
          'id': 1,
          'role': 'user',
          'text': text,
          'created_at': '2026-08-23T10:00:00Z',
        },
        {
          'id': 2,
          'role': 'assistant',
          'text': answer,
          'created_at': '2026-08-23T10:00:05Z',
        },
      ],
    };
  }

  @override
  Future<dynamic> delete(String path) async {
    deletes++;
    return null;
  }
}

/// Каким стилем отрисован кусок текста на экране.
///
/// Проверяем по нему, что разметку разобрали: жирный кусок отличается от
/// соседних не значками вокруг, а начертанием.
TextStyle? styleOf(WidgetTester tester, String part) {
  // Стиль куска собирается по дороге к нему: жирное начертание стоит на
  // спане-обёртке, а сам текст лежит в его ребёнке.
  TextStyle? search(InlineSpan span, TextStyle? outer) {
    final style = outer?.merge(span.style) ?? span.style;

    if (span is! TextSpan) {
      return null;
    }

    if ((span.text ?? '').contains(part)) {
      return style;
    }

    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = search(child, style);

      if (found != null) {
        return found;
      }
    }

    return null;
  }

  // Переписку можно выделять, поэтому реплики рисует не RichText, а поле
  // выделяемого текста: спаны с их стилями лежат в его контроллере.
  for (final element in find.byType(EditableText).evaluate()) {
    final field = element.widget as EditableText;
    final found = search(
      field.controller.buildTextSpan(
        context: element,
        style: field.style,
        withComposing: false,
      ),
      null,
    );

    if (found != null) {
      return found;
    }
  }

  return null;
}

void main() {
  Future<_FakeApi> pump(WidgetTester tester, _FakeApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AssistantPage(
          store: AssistantStore(api: api),
          drawer: const Drawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('пустая переписка не показывает ничего лишнего', (tester) async {
    await pump(tester, _FakeApi());

    // Заголовок и подсказка в поле — и всё: примеров вопросов тут нет.
    expect(find.text('Спросите про магазин'), findsNWidgets(2));
    expect(find.textContaining('Что заканчивается'), findsNothing);
  });

  testWidgets('вопрос уходит на сервер, ответ появляется в переписке', (
    tester,
  ) async {
    final api = await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Что по закупкам?');
    await tester.tap(find.byTooltip('Спросить'));
    await tester.pumpAndSettle();

    expect(api.asked, [
      {'text': 'Что по закупкам?'},
    ]);
    expect(find.text('Что по закупкам?'), findsOneWidget);
    expect(find.text('За месяц 60 накладных.'), findsOneWidget);
  });

  testWidgets('разметку в ответе разбирают, а не показывают значками', (
    tester,
  ) async {
    const report = '**Накладные**\n\n- пришло 60\n- на сумму 1 094 930 ₸';
    await pump(tester, _FakeApi(answer: report));

    await tester.enterText(find.byType(TextField), 'Отчёт');
    await tester.tap(find.byTooltip('Спросить'));
    await tester.pumpAndSettle();

    // Звёздочек и тире на экране быть не должно: это разметка, а не текст.
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('- пришло'), findsNothing);

    // Сам текст при этом на месте весь, до последней строки.
    expect(find.textContaining('Накладные'), findsOneWidget);
    expect(find.textContaining('пришло 60'), findsOneWidget);
    expect(find.textContaining('на сумму 1 094 930 ₸'), findsOneWidget);

    // И заголовок раздела правда жирный, а не просто строка сверху.
    expect(styleOf(tester, 'Накладные')?.fontWeight, FontWeight.w600);
  });

  testWidgets('свой вопрос показывают как есть, разметку в нём не ищут', (
    tester,
  ) async {
    await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Что с **Pepsi**?');
    await tester.tap(find.byTooltip('Спросить'));
    await tester.pumpAndSettle();

    // Человек пишет вопрос словами: звёздочки в нём — часть названия, а не
    // просьба выделить его жирным.
    expect(find.text('Что с **Pepsi**?'), findsOneWidget);
  });

  testWidgets('вопрос видно сразу, не дожидаясь ответа', (tester) async {
    await pump(tester, _FakeApi(delay: const Duration(seconds: 1)));

    await tester.enterText(find.byType(TextField), 'Долгий вопрос');
    await tester.tap(find.byTooltip('Спросить'));
    // Смотрим на середине: ответа ещё нет.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Долгий вопрос'), findsOneWidget);
    expect(find.text('Смотрю данные…'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('пустой вопрос никуда не отправляется', (tester) async {
    final api = await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Спросить'));
    await tester.pumpAndSettle();

    expect(api.asked, isEmpty);
  });

  testWidgets('поле очищается после отправки', (tester) async {
    await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Вопрос');
    await tester.tap(find.byTooltip('Спросить'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('переписку можно начать заново, но только с согласия', (
    tester,
  ) async {
    final api = await pump(
      tester,
      _FakeApi(
        history: [
          {
            'id': 1,
            'role': 'user',
            'text': 'Старый вопрос',
            'created_at': '2026-08-23T09:00:00Z',
          },
        ],
      ),
    );

    await tester.tap(find.byTooltip('Начать заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.deletes, 0);
    expect(find.text('Старый вопрос'), findsOneWidget);

    await tester.tap(find.byTooltip('Начать заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать'));
    await tester.pumpAndSettle();

    expect(api.deletes, 1);
    expect(find.text('Старый вопрос'), findsNothing);
  });

  testWidgets('пока переписки нет, чистить нечего', (tester) async {
    await pump(tester, _FakeApi());

    expect(find.byTooltip('Начать заново'), findsNothing);
  });
}
