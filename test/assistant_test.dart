import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
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
    this.suggestions = const [],
    this.file,
    this.fileName,
    this.delay = Duration.zero,
  });

  /// Реплики открытой переписки — той, что отдаёт `/assistant/chat/`.
  final List<Map<String, dynamic>> history;

  final String answer;

  /// Следующие вопросы, которые сервер приложил к ответу.
  final List<String> suggestions;

  /// Excel к ответу — как после «сформируй отчёт».
  final String? file;
  final String? fileName;

  /// Насколько сервер задумывается. Ноль — мгновенно, и тогда состояния
  /// «аналитик думает» на экране просто не бывает: проверять в нём нечего.
  final Duration delay;

  final List<Object> asked = [];
  final List<String> deleted = [];

  /// Прошлые разговоры и реплики того, который открывают из истории.
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> archive = const [];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/assistant/chats/') {
      return <String, dynamic>{'chats': chats};
    }

    if (path.startsWith('/assistant/chats/')) {
      return <String, dynamic>{
        'chat': {'id': 42, 'title': 'Старый разговор'},
        'messages': archive,
      };
    }

    return <String, dynamic>{
      'chat': history.isEmpty ? null : {'id': 7, 'title': 'Открытый разговор'},
      'messages': history,
    };
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    asked.add(body);
    await Future<void>.delayed(delay);
    final text = (body as Map)['text'];

    return <String, dynamic>{
      'chat': {'id': 7, 'title': text},
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
          'suggestions': suggestions,
          'file': file,
          'file_name': fileName,
          'created_at': '2026-08-23T10:00:05Z',
        },
      ],
    };
  }

  @override
  Future<dynamic> delete(String path) async {
    deleted.add(path);
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
        home: AssistantPage(store: AssistantStore(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('пустая переписка предлагает с чего начать', (tester) async {
    await pump(tester, _FakeApi());

    expect(find.text('Спросите про магазин'), findsOneWidget);
    expect(find.text('Введите свой вопрос...'), findsOneWidget);
    expect(find.text('Что заканчивается на полке?'), findsOneWidget);
    expect(find.text('Что продаётся лучше всего?'), findsOneWidget);
    expect(find.text('Сколько накладных за месяц?'), findsOneWidget);
  });

  testWidgets('предложенный вопрос уходит как обычный', (tester) async {
    final api = await pump(tester, _FakeApi());

    await tester.tap(find.text('Что заканчивается на полке?'));
    await tester.pumpAndSettle();

    expect(api.asked, [
      {'text': 'Что заканчивается на полке?'},
    ]);
    expect(find.text('Что заканчивается на полке?'), findsOneWidget);
  });

  testWidgets('после ответа предлагают следующие вопросы', (tester) async {
    await pump(tester, _FakeApi(suggestions: ['Сколько заказать?']));

    await tester.enterText(find.byType(TextField), 'Молоко');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(find.text('Сколько заказать?'), findsOneWidget);
    expect(find.text('Что заканчивается на полке?'), findsNothing);
  });

  testWidgets('к ответу с отчётом рисуют карточку файла', (tester) async {
    await pump(
      tester,
      _FakeApi(
        answer: 'Продажи за 30 дней — 3 000 позиций.',
        file: 'https://example.test/media/sales.xlsx',
        fileName: 'Продажи за 30 дн.xlsx',
      ),
    );

    await tester.enterText(find.byType(TextField), 'Сформируй отчёт');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(find.text('Продажи за 30 дн.xlsx'), findsOneWidget);
    expect(find.byIcon(LucideIcons.file_spreadsheet), findsOneWidget);
  });

  testWidgets('вопрос уходит на сервер, ответ появляется в переписке', (
    tester,
  ) async {
    final api = await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Что по закупкам?');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(api.asked, [
      {'text': 'Что по закупкам?'},
    ]);
    expect(find.text('Что по закупкам?'), findsOneWidget);
    expect(find.text('За месяц 60 накладных.'), findsOneWidget);
    // Подпись ответа — чтобы его не спутать со следующим вопросом.
    expect(find.text('Помощник'), findsNWidgets(2));
    expect(find.text('Вы'), findsOneWidget);
    expect(find.text('В'), findsOneWidget);
  });

  testWidgets('свой вопрос подписывают именем из профиля', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AssistantPage(
          store: AssistantStore(api: _FakeApi()),
          sender: 'Ержан',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Что по закупкам?');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(find.text('Ержан'), findsOneWidget);
    expect(find.text('Е'), findsOneWidget);
    expect(find.text('Вы'), findsNothing);
  });

  testWidgets('разметку в ответе разбирают, а не показывают значками', (
    tester,
  ) async {
    const report = '**Накладные**\n\n- пришло 60\n- на сумму 1 094 930 ₸';
    await pump(tester, _FakeApi(answer: report));

    await tester.enterText(find.byType(TextField), 'Отчёт');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    // Человек пишет вопрос словами: звёздочки в нём — часть названия, а не
    // просьба выделить его жирным.
    expect(find.text('Что с **Pepsi**?'), findsOneWidget);
  });

  testWidgets('вопрос видно сразу, не дожидаясь ответа', (tester) async {
    await pump(tester, _FakeApi(delay: const Duration(seconds: 1)));

    await tester.enterText(find.byType(TextField), 'Долгий вопрос');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    // Смотрим на середине: ответа ещё нет.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Долгий вопрос'), findsOneWidget);
    expect(find.text('Помощник пишет ответ...'), findsOneWidget);

    // Полоса «пишет ответ» закреплена над полем, точки сами играют.
    // Таймер сервера всё равно нужно докрутить: анимация кадров не двигает.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('пустой вопрос никуда не отправляется', (tester) async {
    final api = await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(api.asked, isEmpty);
  });

  testWidgets('поле очищается после отправки', (tester) async {
    await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Вопрос');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('новый разговор не стирает прежний, а откладывает его', (
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

    await tester.tap(find.byTooltip('Новый разговор'));
    await tester.pumpAndSettle();

    // Экран пуст, но на сервере ничего не удалено: прежний разговор ушёл в
    // историю и оттуда же продолжается.
    expect(find.text('Старый вопрос'), findsNothing);
    expect(api.deleted, isEmpty);

    await tester.enterText(find.byType(TextField), 'Новый вопрос');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    // Вопрос уходит с пометкой «в новую», иначе сервер дописал бы его в
    // прежнюю переписку.
    expect(api.asked, [
      {'text': 'Новый вопрос', 'fresh': true},
    ]);
  });

  testWidgets('следующий вопрос продолжает ту же переписку', (tester) async {
    final api = await pump(tester, _FakeApi());

    await tester.enterText(find.byType(TextField), 'Первый');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Второй');
    await tester.tap(find.widgetWithText(FilledButton, 'Спросить'));
    await tester.pumpAndSettle();

    // У второго вопроса уже есть, к чему привязаться: переписка заведена
    // первым, и сервер должен дописать в неё, а не начать третью.
    expect(api.asked.last, {'text': 'Второй', 'chat': 7});
  });

  testWidgets('пока разговора нет, начинать нечего', (tester) async {
    await pump(tester, _FakeApi());

    // Подсказку кнопка рисует внутри себя, поэтому от найденной подсказки
    // поднимаемся к самой кнопке.
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Новый разговор'),
        matching: find.byType(IconButton),
      ),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('разговор из истории открывается со своими репликами', (
    tester,
  ) async {
    final api = _FakeApi(
      history: [
        {
          'id': 1,
          'role': 'user',
          'text': 'Сегодняшний вопрос',
          'created_at': '2026-08-23T09:00:00Z',
        },
      ],
    );
    api.chats = [
      {
        'id': 42,
        'title': 'Старый разговор',
        'created_at': '2026-08-20T09:00:00Z',
        'updated_at': '2026-08-20T09:05:00Z',
      },
    ];
    api.archive = [
      {
        'id': 5,
        'role': 'user',
        'text': 'Вопрос из прошлого',
        'created_at': '2026-08-20T09:00:00Z',
      },
    ];

    await pump(tester, api);

    await tester.tap(find.byTooltip('История разговоров'));
    await tester.pumpAndSettle();

    expect(find.text('Старый разговор'), findsOneWidget);

    await tester.tap(find.text('Старый разговор'));
    await tester.pumpAndSettle();

    expect(find.text('Вопрос из прошлого'), findsOneWidget);
    expect(find.text('Сегодняшний вопрос'), findsNothing);
  });

  testWidgets('переписку удаляют из истории, и только с согласия', (
    tester,
  ) async {
    final api = _FakeApi();
    api.chats = [
      {
        'id': 42,
        'title': 'Старый разговор',
        'created_at': '2026-08-20T09:00:00Z',
        'updated_at': '2026-08-20T09:05:00Z',
      },
    ];

    await pump(tester, api);

    await tester.tap(find.byTooltip('История разговоров'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Удалить переписку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.deleted, isEmpty);

    await tester.tap(find.byTooltip('Удалить переписку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(api.deleted, ['/assistant/chats/42/']);
    expect(find.text('Старый разговор'), findsNothing);
  });
}
