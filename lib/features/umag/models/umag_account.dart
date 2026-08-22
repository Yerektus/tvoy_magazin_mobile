/// Магазин в кабинете UMAG. Приёмка создаётся в одном конкретном.
class UmagStore {
  const UmagStore({required this.id, required this.name});

  factory UmagStore.fromJson(Map<String, dynamic> json) =>
      UmagStore(id: json['id'] as int, name: (json['name'] ?? '') as String);

  final int id;
  final String name;
}

/// Подключение сотрудника к своему кабинету UMAG.
///
/// Токена здесь нет и быть не может: сервер его наружу не отдаёт — это ключ от
/// чужого кабинета.
class UmagAccount {
  const UmagAccount({
    required this.connected,
    required this.storeId,
    required this.storeName,
    required this.stores,
  });

  factory UmagAccount.fromJson(Map<String, dynamic> json) => UmagAccount(
    connected: (json['connected'] ?? false) as bool,
    storeId: json['store_id'] as int?,
    storeName: (json['store_name'] ?? '') as String,
    stores: ((json['stores'] ?? const []) as List)
        .map((row) => UmagStore.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(),
  );

  static const empty = UmagAccount(
    connected: false,
    storeId: null,
    storeName: '',
    stores: [],
  );

  final bool connected;
  final int? storeId;
  final String storeName;
  final List<UmagStore> stores;

  /// Выбирать есть из чего, только когда кабинет подключён и магазинов больше
  /// одного: при единственном сервер ставит его сам, и список не нужен.
  bool get canSwitch => connected && stores.length > 1;
}

/// Ссылка на черновик приёмки в кабинете.
///
/// Две ловушки, обе стоили нам «У Вас нет доступа к этой приёмке».
///
/// Первая: в адресе стоит не номер магазина, а его **порядковый номер** в
/// списке магазинов кабинета. Маршрут объявлен как `store/:storeId`, но кладут
/// туда индекс, и у третьего магазина это `2`, а не `17797`.
///
/// Вторая: страница называется `edit-template`, а не `edit`.
String supplyUrl(int supplyId, int storeIndex) =>
    'https://web.umag.kz/store/$storeIndex/supplies/$supplyId/edit-template';

/// Порядковый номер магазина в кабинете — его и ждёт адрес приёмки.
int storeIndexOf(List<UmagStore> stores, int? storeId) {
  final index = stores.indexWhere((store) => store.id == storeId);

  // Не нашли — пусть откроется первый магазин: пустая страница хуже.
  return index >= 0 ? index : 0;
}
