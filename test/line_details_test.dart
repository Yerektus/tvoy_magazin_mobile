import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/documents/models/document.dart';
import 'package:tvoy_magazin_mobile/features/documents/pages/line_details_page.dart';
import 'package:tvoy_magazin_mobile/features/documents/services/documents_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';

/// Подменяет сеть: помнит, что и куда ушло.
class _FakeApi extends ApiClient {
  final List<({String path, Object body})> patches = [];

  double quantity = 1;
  double price = 380;

  @override
  Future<dynamic> patch(String path, Object body) async {
    patches.add((path: path, body: body));

    // Сервер после правки количества или цены пересчитывает сумму строки.
    final patch = body as Map;
    quantity = double.tryParse('${patch['quantity'] ?? quantity}') ?? quantity;
    price = double.tryParse('${patch['price'] ?? price}') ?? price;

    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    // Ответ на перечитывание накладной после правки.
    if (path == '/invoices/87/') {
      return <String, dynamic>{
        'id': 87,
        'status': 'checked',
        'lines': [
          {
            'id': 765,
            'position': 1,
            'name': 'Новое название',
            'barcode': '4607014822657',
            'quantity': quantity.toStringAsFixed(3),
            'unit': 'шт',
            'price': price.toStringAsFixed(2),
            'total': (quantity * price).toStringAsFixed(2),
            'umag_product_name': '',
            'umag_confidence': null,
          },
        ],
      };
    }

    return <String, dynamic>{'results': <dynamic>[]};
  }
}

const _line = DocumentLine(
  id: 765,
  position: 1,
  name: 'БС-Коктейль мол. чудо 0.2л 2% ваниль БШ',
  barcode: '4607014822657',
  quantity: 1,
  unit: 'шт',
  price: 380,
  total: 380,
  umagProductName: 'МОЛ.КОКТЕЛЬ ВАНИЛЬ',
  umagConfidence: 1,
);

void main() {
  Future<_FakeApi> pump(WidgetTester tester) async {
    final api = _FakeApi();

    await tester.pumpWidget(
      MaterialApp(
        home: LineDetailsPage(
          store: DocumentsStore(api: api),
          invoiceId: 87,
          line: _line,
        ),
      ),
    );

    return api;
  }

  /// Поле напротив подписи. Искать по значению нельзя: у количества и цены оно
  /// со временем совпадает, а подпись у каждой строки своя.
  Finder fieldNextTo(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(TextField),
  );

  /// Печатает в поле и жмёт «Готово» на клавиатуре — так же, как человек.
  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(fieldNextTo(label), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('показывает все поля позиции', (tester) async {
    await pump(tester);

    expect(find.text('Позиция 1'), findsOneWidget);
    expect(
      find.text('БС-Коктейль мол. чудо 0.2л 2% ваниль БШ'),
      findsOneWidget,
    );
    expect(find.text('4607014822657'), findsOneWidget);
    expect(find.text('шт'), findsOneWidget);
    // Товар UMAG показываем, но править его у нас нельзя: у него поля нет.
    expect(find.text('МОЛ.КОКТЕЛЬ ВАНИЛЬ'), findsOneWidget);
    expect(fieldNextTo('Товар в UMAG'), findsNothing);
  });

  testWidgets('правка количества уходит на сервер', (tester) async {
    final api = await pump(tester);

    await type(tester, 'Количество', '2');

    expect(api.patches.length, 1);
    expect(api.patches.first.path, '/invoices/87/lines/765/');
    expect(api.patches.first.body, {'quantity': '2'});
  });

  testWidgets('запятую с телефонной клавиатуры переводим в точку', (
    tester,
  ) async {
    final api = await pump(tester);

    await type(tester, 'Цена', '8,29');

    expect(api.patches.first.body, {'price': '8.29'});
  });

  testWidgets('на не-число ругаемся, на сервер не идём и возвращаем прежнее', (
    tester,
  ) async {
    final api = await pump(tester);

    await type(tester, 'Количество', 'много');

    expect(find.text('Тут нужно число'), findsOneWidget);
    expect(api.patches, isEmpty);

    // Закрываем ругань — в поле должно вернуться то, что на сервере, иначе на
    // экране останется значение, которого нигде нет.
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(fieldNextTo('Количество')).controller?.text,
      '1',
    );
  });

  testWidgets('без изменений запросов не шлём', (tester) async {
    final api = await pump(tester);

    await type(tester, 'Единица', 'шт');

    expect(api.patches, isEmpty);
  });

  testWidgets('поправили количество — сумма пересчиталась', (tester) async {
    await pump(tester);

    expect(
      tester.widget<TextField>(fieldNextTo('Сумма')).controller?.text,
      '380',
    );

    await type(tester, 'Количество', '10');

    // Сервер вернул 10 × 380; поле суммы должно показать это, а не прежние 380.
    expect(
      tester.widget<TextField>(fieldNextTo('Сумма')).controller?.text,
      '3800',
    );
  });
}
