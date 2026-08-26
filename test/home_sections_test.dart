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

  testWidgets('открытый доступ возвращает разделы в панель', (tester) async {
    await pump(tester, purchases: true, assistant: true);

    expect(find.text('Закупки'), findsOneWidget);
    expect(find.text('Помощник'), findsOneWidget);
  });
}
