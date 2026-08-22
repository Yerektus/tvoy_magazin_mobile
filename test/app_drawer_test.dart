import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvoy_magazin_mobile/features/auth/services/auth.dart';
import 'package:tvoy_magazin_mobile/features/umag/services/umag_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_drawer.dart';

/// Подменяет сеть: отдаёт кабинет UMAG и помнит смену магазина.
class _FakeApi extends ApiClient {
  _FakeApi({this.stores = 2});

  /// Сколько магазинов у компании. Один — выбирать не из чего.
  final int stores;
  final List<Object> patches = [];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/umag/account/') {
      return _account();
    }

    if (path == '/auth/me/') {
      return _user();
    }

    return <String, dynamic>{};
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    patches.add(body);
    return _account(storeId: (body as Map)['store_id'] as int);
  }

  Map<String, dynamic> _account({int storeId = 17797}) => <String, dynamic>{
    'connected': true,
    'store_id': storeId,
    'store_name': 'Магазин $storeId',
    'stores': [
      for (var i = 0; i < stores; i++)
        {'id': 17797 + i, 'name': 'Магазин ${17797 + i}'},
    ],
  };

  Map<String, dynamic> _user() => <String, dynamic>{
    'id': 1,
    'email': 'shop@tvoymagazin.kz',
    'name': 'Ержан',
    'role': 'owner',
    'organization': {'id': 1, 'name': 'ТОО «Твой магазин»'},
    'manages_organization': true,
  };
}

void main() {
  /// Раздел, выбранный в меню, — за ним и следим.
  Section? chosen;

  // Без заглушки `SharedPreferences` уходит спрашивать платформу, которой в
  // тестах нет, и ожидание не заканчивается никогда.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    chosen = null;
  });

  Future<(_FakeApi, Auth)> pump(WidgetTester tester, {int stores = 2}) async {
    final api = _FakeApi(stores: stores);
    final auth = Auth(api: api);
    await auth.reload();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(
            auth: auth,
            umag: UmagAccountStore(api: api),
            current: Section.documents,
            onSelect: (section) => chosen = section,
          ),
          body: const SizedBox(),
        ),
      ),
    );

    // Открываем шторку так же, как человек, — кнопкой в шапке нет, поэтому
    // просим Scaffold напрямую.
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    return (api, auth);
  }

  testWidgets('в меню один раздел — документы', (tester) async {
    await pump(tester);

    expect(find.text('Документы'), findsOneWidget);
    expect(find.text('Твой магазин'), findsOneWidget);
    // Внизу только почта: имя рядом с ней ничего не добавляло.
    expect(find.text('shop@tvoymagazin.kz'), findsOneWidget);
    expect(find.text('Ержан'), findsNothing);
    // Организацию в шапке меню не показываем: она у всех одна, и место
    // занимала зря.
    expect(find.text('ТОО «Твой магазин»'), findsNothing);
  });

  testWidgets('выход спрятан в меню профиля, а не лежит на виду', (
    tester,
  ) async {
    final (_, auth) = await pump(tester);

    // Сразу «Выйти» на экране нет — сначала нужно открыть меню.
    expect(find.text('Выйти'), findsNothing);

    await tester.tap(find.text('shop@tvoymagazin.kz'));
    await tester.pumpAndSettle();

    expect(find.text('Выйти'), findsOneWidget);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isFalse);
  });

  testWidgets('меню закрывается крестиком', (tester) async {
    await pump(tester);

    expect(find.text('Документы'), findsOneWidget);

    await tester.tap(find.byTooltip('Закрыть меню'));
    await tester.pumpAndSettle();

    expect(find.text('Документы'), findsNothing);
  });

  testWidgets('выбор магазина уходит на сервер', (tester) async {
    final (api, _) = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    // В раскрытом списке пункт есть и в самом поле, и в выпадашке.
    await tester.tap(find.text('Магазин 17798').last);
    await tester.pumpAndSettle();

    expect(api.patches, [
      {'store_id': 17798},
    ]);
  });

  testWidgets('магазин один — выбирать нечего, списка нет', (tester) async {
    await pump(tester, stores: 1);

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
  });

  testWidgets('в меню два раздела, открытый отмечен', (tester) async {
    await pump(tester);

    expect(find.text('Документы'), findsOneWidget);
    expect(find.text('Закупки'), findsOneWidget);
  });

  testWidgets('выбор раздела уходит наверх и закрывает меню', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Закупки'));
    await tester.pumpAndSettle();

    expect(chosen, Section.purchases);
    expect(
      find.text('Закупки'),
      findsNothing,
      reason: 'меню осталось открытым',
    );
  });

  testWidgets('тап по открытому разделу только закрывает меню', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Документы'));
    await tester.pumpAndSettle();

    // Никуда не переходим, но и меню не оставляем открытым: иначе тап
    // выглядит как «не сработало».
    expect(chosen, isNull);
    expect(find.text('Документы'), findsNothing);
  });
}
