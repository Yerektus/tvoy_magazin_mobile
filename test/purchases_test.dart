import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/purchases/pages/purchases_page.dart';
import 'package:tvoy_magazin_mobile/features/purchases/services/plan_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_theme.dart';

/// Подменяет сеть: отдаёт состояние расширения и план.
class _FakeApi extends ApiClient {
  _FakeApi({this.connected = true, this.plan});

  final bool connected;
  final Map<String, dynamic>? plan;
  final List<Object> posts = [];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/purchases/access/') {
      return <String, dynamic>{'connected': connected, 'umag': true};
    }

    // Плана ещё нет — сервер отвечает пустотой (204), и клиент видит null.
    return plan;
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    posts.add(body);
    return plan ?? _ready();
  }
}

Map<String, dynamic> _ready({List<dynamic>? items}) => <String, dynamic>{
  'id': 1,
  'status': 'ready',
  'error': '',
  'store_name': 'Каратал',
  'days': 30,
  'horizon': 14,
  'items_total': 2,
  'total_cost': '15400.00',
  'built_at': '2026-08-22T09:00:00Z',
  'items':
      items ??
      [
        {
          'position': 1,
          'name': 'Напиток PEPSI-COLA ПЭТ 1.0',
          'measure': 'шт',
          'supplier': 'ТОО ЖЕТЫСУ-ТРЕЙД',
          'sold': '60.000',
          'stock': '4.000',
          'per_day': '2.000',
          'cover_days': '2.0',
          'suggested': '24.000',
          'price': '535.50',
          'cost': '12852.00',
        },
        {
          'position': 2,
          'name': 'Лаваш',
          'measure': 'шт',
          'supplier': 'ИП СУЛТАН',
          'sold': '30.000',
          'stock': '20.000',
          'per_day': '1.000',
          'cover_days': '20.0',
          'suggested': '10.000',
          'price': '254.80',
          'cost': '2548.00',
        },
      ],
};

void main() {
  Future<_FakeApi> pump(
    WidgetTester tester,
    _FakeApi api, {
    TargetPlatform? platform,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: platform == null
            ? buildTheme()
            : buildTheme().copyWith(platform: platform),
        home: PurchasesPage(
          store: PlanStore(api: api),
          drawer: const Drawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('готовый план показывает позиции и итог', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()));

    expect(find.text('Напиток PEPSI-COLA ПЭТ 1.0'), findsOneWidget);
    expect(find.text('Лаваш'), findsOneWidget);

    // Главное число строки — сколько заказать, а не сколько продано.
    expect(find.text('24 шт'), findsOneWidget);
    expect(find.text('Позиций: 2'), findsOneWidget);
    expect(find.text('15 400 ₸'), findsOneWidget);
  });

  testWidgets('в шапке видно, за какой период посчитано', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()));

    expect(find.text('ПРОДАЖИ ЗА 30 ДН. · ЗАКУП НА 14 ДН.'), findsOneWidget);
  });

  testWidgets('на сколько хватит остатка написано у каждой строки', (
    tester,
  ) async {
    await pump(tester, _FakeApi(plan: _ready()));

    // Окончание по числу: «2 дня», но «20 дней».
    expect(find.textContaining('хватит на 2 дня'), findsOneWidget);
    expect(find.textContaining('хватит на 20 дней'), findsOneWidget);
  });

  testWidgets('плана ещё нет — предлагаем посчитать', (tester) async {
    await pump(tester, _FakeApi());

    expect(find.text('Плана ещё нет'), findsOneWidget);
    expect(find.text('Посчитать'), findsOneWidget);
  });

  testWidgets('расширение не подключено — считать не предлагаем', (
    tester,
  ) async {
    await pump(tester, _FakeApi(connected: false));

    expect(find.text('Планирование не подключено'), findsOneWidget);
    // Подключают его в веб-кабинете, кнопка тут всё равно бы отказала.
    expect(find.text('Посчитать'), findsNothing);
  });

  testWidgets('пересчёт спрашивает период и шлёт его на сервер', (
    tester,
  ) async {
    final api = await pump(tester, _FakeApi(plan: _ready()));

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    expect(find.text('Что посчитать'), findsOneWidget);

    await tester.tap(find.text('7 дн.').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Посчитать'));
    await tester.pumpAndSettle();

    expect(api.posts, [
      {'days': 7, 'horizon': 14},
    ]);
  });

  testWidgets('отказ от пересчёта ничего не отправляет', (tester) async {
    final api = await pump(tester, _FakeApi(plan: _ready()));

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.posts, isEmpty);
  });

  testWidgets('закупать нечего — говорим об этом, а не показываем пустоту', (
    tester,
  ) async {
    final empty = _ready(items: [])
      ..['items_total'] = 0
      ..['total_cost'] = '0.00';

    await pump(tester, _FakeApi(plan: empty));

    expect(find.text('Закупать нечего'), findsOneWidget);
  });

  testWidgets('некруглый срок из плана всё равно отмечен', (tester) async {
    // План могли посчитать с другого клиента: горизонт 3 дня в готовые
    // варианты не входит, но терять его нельзя.
    final odd = _ready()..['horizon'] = 3;

    await pump(tester, _FakeApi(plan: odd));

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    expect(find.text('3 дн.'), findsOneWidget);
  });

  testWidgets('несменённый срок уходит на сервер как есть', (tester) async {
    final odd = _ready()..['horizon'] = 3;
    final api = await pump(tester, _FakeApi(plan: odd));

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Посчитать'));
    await tester.pumpAndSettle();

    expect(api.posts, [
      {'days': 30, 'horizon': 3}
    ]);
  });

  testWidgets('на iOS окно периода родное для системы', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()), platform: TargetPlatform.iOS);

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    // Кнопки тоже: адаптивным бывает само окно, а содержимое ему безразлично.
    expect(find.widgetWithText(CupertinoDialogAction, 'Посчитать'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Посчитать'), findsNothing);
  });

  testWidgets('на Android окно периода материальное', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()), platform: TargetPlatform.android);

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.widgetWithText(TextButton, 'Посчитать'), findsOneWidget);
  });

  testWidgets('на iOS сроки внутри окна не падают', (tester) async {
    // `CupertinoAlertDialog` не даёт `Material`, и «таблетки» внутри него
    // валятся с «No Material widget found». Проверка сторожит обёртку.
    await pump(tester, _FakeApi(plan: _ready()), platform: TargetPlatform.iOS);

    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('30 дн.'), findsWidgets);
  });
}
