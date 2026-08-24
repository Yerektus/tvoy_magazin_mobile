import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvoy_magazin_mobile/features/documents/models/document.dart';
import 'package:tvoy_magazin_mobile/features/documents/pages/documents_page.dart';
import 'package:tvoy_magazin_mobile/features/documents/services/documents_store.dart';
import 'package:tvoy_magazin_mobile/features/umag/services/umag_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_theme.dart';

/// Помнит, с каким отбором просили список, и отдаёт заданные строки.
class _FakeApi extends ApiClient {
  final List<String?> asked = [];

  List<dynamic> results = <dynamic>[];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/invoices/') {
      asked.add(query?['tab']);
    }

    return <String, dynamic>{'results': results, 'connected': false};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeApi> pump(WidgetTester tester) async {
    final api = _FakeApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: DocumentsPage(
          store: DocumentsStore(api: api),
          umag: UmagAccountStore(api: api),
          drawer: const Drawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('вкладки делят ширину поровну', (tester) async {
    await pump(tester);

    final widths = [
      for (final label in ['Все', 'Ожидают', 'Проверенные'])
        tester
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .width,
    ];

    expect(widths[0], closeTo(widths[1], 0.5));
    expect(widths[1], closeTo(widths[2], 0.5));

    // И вместе занимают всю ширину экрана, а не жмутся слева.
    final screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(widths.reduce((a, b) => a + b), closeTo(screen, 1));
  });

  testWidgets('подписи не обрезаются на узком экране', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester);

    // Три подписи целиком видны — самая длинная в том числе.
    for (final label in ['Все', 'Ожидают', 'Проверенные']) {
      expect(find.text(label), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('нажатие на вкладку меняет отбор списка', (tester) async {
    final api = await pump(tester);

    expect(api.asked, [null]);

    await tester.tap(find.text('Ожидают'));
    await tester.pumpAndSettle();

    expect(api.asked, [null, 'pending']);

    await tester.tap(find.text('Проверенные'));
    await tester.pumpAndSettle();

    expect(api.asked, [null, 'pending', 'checked']);
  });

  testWidgets('в строке списка заголовок — поставщик, под ним сумма', (
    tester,
  ) async {
    final api = _FakeApi()
      ..results = [
        {
          'id': 1,
          'status': 'checked',
          'supplier': 'ИП СУЛТАН',
          'number': '64481',
          'total': '4560.00',
          'created_at': '2026-08-21T16:46:00Z',
        },
      ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: DocumentsPage(
          store: DocumentsStore(api: api),
          umag: UmagAccountStore(api: api),
          drawer: const Drawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ИП СУЛТАН'), findsOneWidget);
    // Названия накладной в строке больше нет: у половины строк оно одинаковое.
    expect(find.textContaining('Накладная'), findsNothing);

    final supplier = tester.getTopLeft(find.text('ИП СУЛТАН'));
    final money = tester.getTopLeft(find.text('4\u00a0560\u00a0₸'));

    expect(
      money.dy,
      greaterThan(supplier.dy),
      reason: 'сумма должна быть под заголовком',
    );
    expect(
      money.dx,
      supplier.dx,
      reason: 'сумма должна стоять под заголовком, а не справа',
    );
  });

  Map<String, dynamic> row({
    required int id,
    required String supplier,
    required String at,
    String total = '1000.00',
  }) => {
    'id': id,
    'status': 'checked',
    'supplier': supplier,
    'total': total,
    'created_at': at,
  };

  Future<void> open(WidgetTester tester, _FakeApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: DocumentsPage(
          store: DocumentsStore(api: api),
          umag: UmagAccountStore(api: api),
          drawer: const Drawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('накладные разделены по дням, в строках только время', (
    tester,
  ) async {
    final api = _FakeApi()
      ..results = [
        row(id: 1, supplier: 'ИП СУЛТАН', at: '2026-08-21T16:46:00'),
        row(id: 2, supplier: 'ZOR', at: '2026-08-21T09:05:00'),
        row(id: 3, supplier: 'Рахат', at: '2026-08-19T11:35:00'),
      ];

    await open(tester, api);

    // Заголовок дня на каждый день, а не на каждую строку.
    expect(find.text(formatDayHeader(DateTime(2026, 8, 21))), findsOneWidget);
    expect(find.text(formatDayHeader(DateTime(2026, 8, 19))), findsOneWidget);

    // В строках — время без даты.
    expect(find.text('16:46'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(find.textContaining('21.08.2026'), findsNothing);
  });

  testWidgets('длинное название поставщика не рвёт вёрстку', (tester) async {
    // Тот самый случай: имя на четыре строки на узком экране. Раньше внизу
    // строки вылезала полосатая лента «BOTTOM OVERFLOWED BY 1.00 PIXELS».
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = _FakeApi()
      ..results = [
        row(
          id: 1,
          supplier:
              'Товарищество с ограниченной ответственностью "KARAVAN (КАРАВАН)"',
          at: '2026-08-20T12:26:00',
          total: '17086.00',
        ),
      ];

    await open(tester, api);

    expect(tester.takeException(), isNull, reason: 'вёрстка переполнилась');
  });

  testWidgets('полоса вкладок не занимает лишней высоты', (tester) async {
    await pump(tester);

    final tabs = tester.getSize(
      find
          .ancestor(
            of: find.text('Все'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    // Вкладки — это управление, а не содержимое: чем меньше они откусывают у
    // списка, тем лучше. Сорок точек хватает, чтобы попасть пальцем.
    expect(tabs.height, lessThanOrEqualTo(42));
    expect(
      tabs.height,
      greaterThanOrEqualTo(36),
      reason: 'по такой не попасть',
    );
  });

  testWidgets('статус в списке стоит на своей подложке', (tester) async {
    final api = _FakeApi()
      ..results = [
        row(id: 1, supplier: 'ИП СУЛТАН', at: '2026-08-21T16:46:00'),
      ];

    await open(tester, api);

    final chip = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Проверено'),
            matching: find.byType(Container),
          )
          .first,
    );

    expect(
      (chip.decoration! as BoxDecoration).color,
      DocumentStatus.checked.background,
    );
  });

  test('у каждого статуса своя подложка, и она не белая', () {
    for (final status in DocumentStatus.values) {
      expect(status.background, isNot(Colors.white), reason: status.name);
      // Буквы на подложке должны быть темнее её самой, иначе не прочитать.
      expect(
        status.color.computeLuminance(),
        lessThan(status.background.computeLuminance()),
        reason: 'у ${status.name} текст светлее подложки',
      );
    }
  });
}
