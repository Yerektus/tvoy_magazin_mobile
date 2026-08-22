import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/auth/models/auth_user.dart';
import 'package:tvoy_magazin_mobile/features/documents/models/document.dart';

void main() {
  test('деньги разделяем неразрывным пробелом, чтобы число не разорвалось', () {
    expect(formatMoney(1140), '1\u00a0140\u00a0\u20b8');
    expect(formatMoney(18484.16), '18\u00a0484\u00a0\u20b8');
    expect(formatMoney(null), '\u2014');
  });

  test('без номера накладную называем по дате', () {
    final withNumber = DocumentItem.fromJson({
      'id': 1,
      'status': 'done',
      'number': 'KBH0425981',
      'issued_at': '2026-08-08',
      'lines_count': 3,
    });
    expect(withNumber.title, 'Накладная \u2116KBH0425981');

    final withoutNumber = DocumentItem.fromJson({
      'id': 2,
      'status': 'pending',
      'issued_at': '2026-08-08',
      'lines_count': 0,
    });
    expect(withoutNumber.title, 'Накладная от 08.08.2026');
  });

  test('незнакомую роль считаем менеджером — прав у неё меньше всего', () {
    final user = AuthUser.fromJson({
      'id': 1,
      'email': 'shop@tvoymagazin.kz',
      'name': '',
      'role': 'chto-to-novoe',
      'organization': {'id': 1, 'name': 'Магазин'},
      'manages_organization': false,
    });

    expect(user.role, Role.manager);
    expect(user.organization.name, 'Магазин');
  });

  testWidgets('статус накладной виден в списке', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Text(DocumentStatus.parse('checked').label)),
      ),
    );

    expect(find.text('Проверено'), findsOneWidget);
  });
}
