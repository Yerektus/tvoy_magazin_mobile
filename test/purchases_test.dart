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
        home: PurchasesPage(store: PlanStore(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  /// Раздел открывается условиями — до отчёта нужно дойти.
  Future<void> openReport(WidgetTester tester) async {
    await tester.tap(find.textContaining('Прошлый отчёт'));
    await tester.pumpAndSettle();
  }

  testWidgets('готовый план показывает позиции и итог', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()));
    await openReport(tester);

    expect(find.text('Напиток PEPSI-COLA ПЭТ 1.0'), findsOneWidget);
    expect(find.text('Лаваш'), findsOneWidget);

    // Главное число строки — сколько заказать, а не сколько продано.
    expect(find.text('24 шт'), findsOneWidget);
    expect(find.text('Позиций: 2'), findsOneWidget);
    expect(find.text('15 400 ₸'), findsOneWidget);
  });

  testWidgets('над списком не висит справка о периоде', (tester) async {
    await pump(tester, _FakeApi(plan: _ready()));
    await openReport(tester);

    // Период и время расчёта убраны: их спрашивают раз в кнопке пересчёта, а
    // над каждым открытием плана они висели постоянной полосой.
    expect(find.textContaining('ПРОДАЖИ ЗА'), findsNothing);
    expect(find.textContaining('Посчитан'), findsNothing);
  });

  testWidgets('на сколько хватит остатка написано у каждой строки', (
    tester,
  ) async {
    await pump(tester, _FakeApi(plan: _ready()));
    await openReport(tester);

    // Окончание по числу: «2 дня», но «20 дней».
    expect(find.textContaining('хватит на 2 дня'), findsOneWidget);
    expect(find.textContaining('хватит на 20 дней'), findsOneWidget);
  });

  testWidgets('раздел открывается условиями, а не пустотой', (tester) async {
    await pump(tester, _FakeApi());

    // Считать заново приходится каждый день: вчерашний отчёт врёт, потому что
    // остатки и ассортимент за сутки поменялись.
    expect(find.text('Смотрим продажи за'), findsOneWidget);
    expect(find.text('Закупаемся на'), findsOneWidget);
    expect(find.text('Посчитать'), findsOneWidget);
    // Считать ещё не начинали — открывать нечего.
    expect(find.textContaining('Прошлый отчёт'), findsNothing);
  });

  testWidgets('расширение не подключено — считать не предлагаем', (
    tester,
  ) async {
    await pump(tester, _FakeApi(connected: false));

    expect(find.text('Планирование не подключено'), findsOneWidget);
    // Подключают его в веб-кабинете: ползунки и кнопка тут всё равно бы
    // ничего не посчитали.
    expect(find.text('Посчитать'), findsNothing);
    expect(find.text('Смотрим продажи за'), findsNothing);
  });

  testWidgets('пересчёт спрашивает условия и шлёт их на сервер', (
    tester,
  ) async {
    final api = await pump(tester, _FakeApi(plan: _ready()));

    await openReport(tester);
    await tester.tap(find.text('Посчитать заново'));
    await tester.pumpAndSettle();

    // Сперва условия, и только потом счёт.
    expect(find.text('Смотрим продажи за'), findsOneWidget);
    expect(api.posts, isEmpty);

    await tester.tap(find.text('Посчитать'));
    await tester.pumpAndSettle();

    expect(api.posts, [
      {'days': 30, 'horizon': 14, 'use_stock': true},
    ]);
  });

  testWidgets('остаток можно не учитывать', (tester) async {
    // Перед праздником полку набивают заново, не глядя на то, что на ней есть.
    final api = await pump(tester, _FakeApi(plan: _ready()));

    await tester.tap(find.text('Учитывать остаток'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Посчитать'));
    await tester.pumpAndSettle();

    expect(api.posts.single, {'days': 30, 'horizon': 14, 'use_stock': false});
  });

  testWidgets('прошлый отчёт открывается без счёта', (tester) async {
    final api = await pump(tester, _FakeApi(plan: _ready()));

    await openReport(tester);

    // Перечитать вчерашний список — не повод ждать минуту и дёргать кабинет.
    expect(api.posts, isEmpty);
    expect(find.text('Лаваш'), findsOneWidget);
  });

  testWidgets('закупать нечего — говорим об этом, а не показываем пустоту', (
    tester,
  ) async {
    final empty = _ready(items: [])
      ..['items_total'] = 0
      ..['total_cost'] = '0.00';

    await pump(tester, _FakeApi(plan: empty));
    await openReport(tester);

    expect(find.text('Закупать нечего'), findsOneWidget);
  });

  testWidgets('срок из плана открывается тем же, что и был', (tester) async {
    // План могли посчитать с другого клиента — условия берём из него, а не с
    // потолка.
    final odd = _ready()..['horizon'] = 3;

    await pump(tester, _FakeApi(plan: odd));

    expect(find.text('3 дн.'), findsOneWidget);
  });

  testWidgets('несменённый срок уходит на сервер как есть', (tester) async {
    final odd = _ready()..['horizon'] = 3;
    final api = await pump(tester, _FakeApi(plan: odd));

    await tester.tap(find.text('Посчитать'));
    await tester.pumpAndSettle();

    expect(api.posts, [
      {'days': 30, 'horizon': 3, 'use_stock': true},
    ]);
  });

  testWidgets('условия открываются страницей, а не окном', (tester) async {
    // Пересчёт ходит в кабинет, удаляет прежний план и считается небыстро —
    // это не то действие, которое делают в окошке поверх списка.
    await pump(tester, _FakeApi(plan: _ready()), platform: TargetPlatform.iOS);

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Смотрим продажи за'), findsOneWidget);
    expect(find.text('Учитывать остаток'), findsOneWidget);
  });

  testWidgets('на iOS условия рисуются так же, как на андроиде', (
    tester,
  ) async {
    await pump(tester, _FakeApi(plan: _ready()), platform: TargetPlatform.iOS);

    expect(tester.takeException(), isNull);
    expect(find.text('30 дн.'), findsWidgets);
    expect(find.byType(Slider), findsNWidgets(2));
  });
}
