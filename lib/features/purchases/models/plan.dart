import 'package:flutter/material.dart';

import '../../documents/models/document.dart';

/// Как считается план на сервере.
enum PlanStatus {
  building('Считается', Color(0xFF0284C7)),
  ready('Готов', Color(0xFF059669)),
  failed('Ошибка', Color(0xFFDC2626));

  const PlanStatus(this.label, this.color);

  final String label;
  final Color color;

  static PlanStatus parse(String? raw) => values.firstWhere(
    (status) => status.name == raw,
    orElse: () => PlanStatus.building,
  );
}

/// Позиция плана: что заканчивается и сколько этого дозаказать.
class PlanItem {
  const PlanItem({
    required this.position,
    required this.barcode,
    required this.name,
    required this.measure,
    required this.supplier,
    required this.sold,
    required this.stock,
    required this.perDay,
    required this.coverDays,
    required this.suggested,
    required this.price,
    required this.cost,
  });

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
    position: (json['position'] ?? 0) as int,
    barcode: (json['barcode'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    measure: (json['measure'] ?? '') as String,
    supplier: (json['supplier'] ?? '') as String,
    sold: _number(json['sold']),
    stock: _number(json['stock']),
    perDay: _number(json['per_day']),
    coverDays: _number(json['cover_days']),
    suggested: _number(json['suggested']),
    price: _number(json['price']),
    cost: _number(json['cost']),
  );

  final int position;
  final String barcode;
  final String name;
  final String measure;
  final String supplier;

  /// Продано за период анализа.
  final double? sold;

  /// Остаток на складе сейчас.
  final double? stock;

  /// Расход в день.
  final double? perDay;

  /// На сколько дней хватит остатка. Пусто — товар не продавался, и делить
  /// было не на что.
  final double? coverDays;

  /// Сколько заказать.
  final double? suggested;

  final double? price;
  final double? cost;
}

/// План закупа по одному магазину.
class Plan {
  const Plan({
    required this.id,
    required this.status,
    required this.error,
    required this.storeName,
    required this.days,
    required this.horizon,
    required this.itemsTotal,
    required this.totalCost,
    required this.builtAt,
    required this.items,
  });

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as int,
    status: PlanStatus.parse(json['status'] as String?),
    error: (json['error'] ?? '') as String,
    storeName: (json['store_name'] ?? '') as String,
    days: (json['days'] ?? 30) as int,
    horizon: (json['horizon'] ?? 14) as int,
    itemsTotal: (json['items_total'] ?? 0) as int,
    totalCost: _number(json['total_cost']),
    builtAt: json['built_at'] == null
        ? null
        : DateTime.tryParse(json['built_at'] as String)?.toLocal(),
    items: ((json['items'] ?? const []) as List)
        .map((row) => PlanItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(),
  );

  final int id;
  final PlanStatus status;
  final String error;
  final String storeName;

  /// За сколько дней смотрели продажи.
  final int days;

  /// На сколько дней вперёд закупаемся.
  final int horizon;

  final int itemsTotal;
  final double? totalCost;
  final DateTime? builtAt;
  final List<PlanItem> items;
}

/// Числа приходят строкой: у DecimalField нет точного двойника в JSON.
double? _number(dynamic value) => switch (value) {
  null => null,
  num it => it.toDouble(),
  String it => double.tryParse(it),
  _ => null,
};

/// «хватит на 3 дня» — с правильным окончанием.
String formatCover(double? days) {
  if (days == null) {
    return 'не продаётся';
  }

  final whole = days.round();
  final last = whole % 10;
  final teen = whole % 100 >= 11 && whole % 100 <= 14;

  final word = teen || last == 0 || last >= 5
      ? 'дней'
      : last == 1
      ? 'день'
      : 'дня';

  return 'хватит на ${formatQuantity(days)} $word';
}
