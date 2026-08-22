import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/umag/models/umag_account.dart';

/// Адрес черновика приёмки дважды был неверным, и каждый раз это выглядело как
/// «У Вас нет доступа к этой приёмке» — ошибка не про адрес, а про права.
/// Поэтому обе ловушки закрыты тестами.
void main() {
  const stores = [
    UmagStore(id: 17795, name: 'Первый'),
    UmagStore(id: 17796, name: 'Второй'),
    UmagStore(id: 17797, name: 'Третий'),
  ];

  test('в адресе стоит порядковый номер магазина, а не его id', () {
    expect(storeIndexOf(stores, 17797), 2);
    expect(
      supplyUrl(123324020, storeIndexOf(stores, 17797)),
      'https://web.umag.kz/store/2/supplies/123324020/edit-template',
    );
  });

  test('страница называется edit-template, а не edit', () {
    expect(supplyUrl(1, 0), endsWith('/edit-template'));
    expect(supplyUrl(1, 0), isNot(endsWith('/edit')));
  });

  test('магазин не нашёлся — открываем первый, а не пустую страницу', () {
    expect(storeIndexOf(stores, 99999), 0);
    expect(storeIndexOf(stores, null), 0);
    expect(storeIndexOf(const [], 17797), 0);
  });
}
