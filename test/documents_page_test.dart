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
  final List<String> deletes = [];

  List<dynamic> results = <dynamic>[];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/invoices/') {
      asked.add(query?['tab']);
    }

    return <String, dynamic>{'results': results, 'connected': false};
  }

  /// Удалённая накладная уходит из выдачи — как и на сервере, где она не
  /// стирается, а перестаёт показываться.
  @override
  Future<dynamic> delete(String path) async {
    deletes.add(path);
    final id = int.parse(path.split('/')[2]);
    results = results.where((row) => (row as Map)['id'] != id).toList();

    return null;
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('вкладки делят ширину поровну', (tester) async {
    await pump(tester);

    final screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final centers = [
      for (final label in ['Все', 'Ожидают', 'Проверенные'])
        tester.getCenter(find.text(label)).dx,
    ];

    // Три равные доли — значит середины вкладок стоят на одной шестой, трёх
    // шестых и пяти шестых ширины. Так подчёркивание показывает не только
    // выбранную вкладку, но и какую долю списка она отбирает.
    expect(centers[0], closeTo(screen / 6, 1));
    expect(centers[1], closeTo(screen / 2, 1));
    expect(centers[2], closeTo(screen * 5 / 6, 1));
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

    final tabs = tester.getSize(find.byType(TabBar));

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

  testWidgets('раскрытый список гасит весь экран, а не только список', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Добавить накладную'));
    await tester.pumpAndSettle();

    expect(find.text('Сделать снимок'), findsOneWidget);
    expect(find.text('Выбрать из галереи'), findsOneWidget);

    // Раньше затемнение рисовалось внутри страницы и не доставало ни до шапки
    // с вкладками, ни до нижней панели разделов: половина экрана оставалась
    // светлой и нажимаемой.
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(
      tester.getRect(find.byType(ModalBarrier).last),
      Offset.zero & screen,
    );
  });

  testWidgets('крестик встаёт ровно на кнопку и закрывает список', (
    tester,
  ) async {
    await pump(tester);

    final was = tester.getRect(find.byTooltip('Добавить накладную'));

    await tester.tap(find.byTooltip('Добавить накладную'));
    await tester.pumpAndSettle();

    // Кнопка в слое — копия настоящей и стоит на её месте: плюс поворачивается
    // в крестик, а не подменяется другой кнопкой в стороне.
    expect(tester.getRect(find.byTooltip('Закрыть')), was);

    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    expect(find.text('Сделать снимок'), findsNothing);
  });

  testWidgets('свайп по накладной спрашивает и удаляет её', (tester) async {
    final api = _FakeApi()
      ..results = [
        row(id: 1, supplier: 'ИП СУЛТАН', at: '2026-08-21T16:46:00'),
        row(id: 2, supplier: 'ZOR', at: '2026-08-21T09:05:00'),
      ];

    await open(tester, api);

    // Свайп сам ничего не удаляет: он только показывает кнопку.
    await tester.drag(find.text('ИП СУЛТАН'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(api.deletes, isEmpty);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить накладную?'), findsOneWidget);

    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();

    expect(api.deletes, ['/invoices/1/']);
    expect(find.text('ИП СУЛТАН'), findsNothing);
    expect(find.text('ZOR'), findsOneWidget);
  });

  testWidgets('отказались — накладная остаётся в списке', (tester) async {
    final api = _FakeApi()
      ..results = [
        row(id: 1, supplier: 'ИП СУЛТАН', at: '2026-08-21T16:46:00'),
      ];

    await open(tester, api);

    await tester.drag(find.text('ИП СУЛТАН'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.deletes, isEmpty);
    expect(find.text('ИП СУЛТАН'), findsOneWidget);
  });
}
