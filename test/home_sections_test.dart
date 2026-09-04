import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvoy_magazin_mobile/features/assistant/services/assistant_store.dart';
import 'package:tvoy_magazin_mobile/features/auth/services/auth.dart';
import 'package:tvoy_magazin_mobile/features/documents/services/documents_store.dart';
import 'package:tvoy_magazin_mobile/features/home_page.dart';
import 'package:tvoy_magazin_mobile/features/purchases/services/plan_store.dart';
import 'package:tvoy_magazin_mobile/features/umag/services/umag_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_theme.dart';

/// Подменяет сеть: отдаёт человека с заданными доступами и пустые списки.
class _FakeApi extends ApiClient {
  _FakeApi({required this.purchases, required this.assistant});

  final bool purchases;
  final bool assistant;

  /// Сервер считает не мгновенно — иначе состояния «идёт расчёт» не застать.
  @override
  Future<dynamic> post(String path, Object body) async {
    await Future<void>.delayed(const Duration(seconds: 1));

    return <String, dynamic>{
      'id': 1,
      'status': 'building',
      'error': '',
      'store_id': 17795,
      'store_name': 'Каратал',
      'days': 30,
      'horizon': 14,
      'use_stock': true,
      'items_total': 0,
      'total_cost': '0.00',
      'created_at': '2026-08-28T10:00:00Z',
      'built_at': null,
      'items': <dynamic>[],
    };
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/auth/me/') {
      return <String, dynamic>{
        'id': 1,
        'email': 'shop@tvoymagazin.kz',
        'name': 'Ержан',
        'role': purchases ? 'owner' : 'manager',
        'organization': {'id': 1, 'name': 'ТОО «Твой магазин»'},
        'manages_organization': purchases,
        'uses_purchases': purchases,
        'uses_assistant': assistant,
      };
    }

    if (path == '/purchases/access/') {
      return <String, dynamic>{'connected': true};
    }

    // Плана ещё нет — сервер отвечает пустотой.
    if (path == '/purchases/plan/') {
      return null;
    }

    return <String, dynamic>{'results': <dynamic>[], 'messages': <dynamic>[]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    required bool purchases,
    required bool assistant,
  }) async {
    final api = _FakeApi(purchases: purchases, assistant: assistant);
    final auth = Auth(api: api);
    await auth.reload();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: HomePage(
          auth: auth,
          documents: DocumentsStore(api: api),
          plans: PlanStore(api: api),
          chat: AssistantStore(api: api),
          umag: UmagAccountStore(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('менеджеру без доступа видны только документы и настройки', (
    tester,
  ) async {
    await pump(tester, purchases: false, assistant: false);

    expect(find.text('Закупки'), findsNothing);
    expect(find.text('Помощник'), findsNothing);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('расчёт закупа не бросают на полпути', (tester) async {
    await pump(tester, purchases: true, assistant: true);

    await tester.tap(find.text('Закупки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Посчитать'));
    await tester.pump();

    // Уходим, пока считается: расчёт идёт минуту и обрывается вместе с
    // уходом — об этом и предупреждаем.
    //
    // Не `pumpAndSettle`: пока идёт счёт, в шапке крутится полоса, и ждать её
    // остановки — значит ждать вечно.
    await tester.tap(find.text('Документы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Прервать расчёт?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Остались в закупках: расчёт не прерван.
    expect(find.text('Закупки'), findsWidgets);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('открытый доступ возвращает разделы в панель', (tester) async {
    await pump(tester, purchases: true, assistant: true);

    expect(find.text('Закупки'), findsOneWidget);
    expect(find.text('Помощник'), findsOneWidget);
  });
}
