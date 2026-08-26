import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvoy_magazin_mobile/features/auth/services/auth.dart';
import 'package:tvoy_magazin_mobile/features/settings/pages/settings_page.dart';
import 'package:tvoy_magazin_mobile/features/umag/services/umag_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';

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
  // Без заглушки `SharedPreferences` уходит спрашивать платформу, которой в
  // тестах нет, и ожидание не заканчивается никогда.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(_FakeApi, Auth)> pump(WidgetTester tester, {int stores = 2}) async {
    final api = _FakeApi(stores: stores);
    final auth = Auth(api: api);
    await auth.reload();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          auth: auth,
          umag: UmagAccountStore(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return (api, auth);
  }

  testWidgets('вверху только почта — по ней и входят', (tester) async {
    await pump(tester);

    expect(find.text('shop@tvoymagazin.kz'), findsOneWidget);

    // Ни имени, ни организации: своё имя человек знает и так, а организация у
    // всех в смене одна.
    expect(find.text('Ержан'), findsNothing);
    expect(find.text('ТОО «Твой магазин»'), findsNothing);
  });

  testWidgets('выбор магазина уходит на сервер', (tester) async {
    final (api, _) = await pump(tester);

    await tester.tap(find.text('Магазин 17798'));
    await tester.pumpAndSettle();

    expect(api.patches, [
      {'store_id': 17798},
    ]);
  });

  testWidgets('магазин один — выбирать нечего, но видно какой', (tester) async {
    await pump(tester, stores: 1);

    expect(find.text('Магазин 17797'), findsOneWidget);
    expect(find.text('Магазин 17798'), findsNothing);
  });

  testWidgets('выход спрашивает согласия', (tester) async {
    final (_, auth) = await pump(tester);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();

    // Передумали — остаёмся внутри: выход стоит повторного входа с паролем.
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(auth.user, isNotNull);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти').last);
    await tester.pumpAndSettle();

    expect(auth.user, isNull);
  });
}
