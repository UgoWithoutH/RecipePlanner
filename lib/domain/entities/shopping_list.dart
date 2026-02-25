import 'package:cloud_firestore/cloud_firestore.dart';

class ShoppingItem {
  final String name;
  final double quantity;
  final String unit;
  final String? typeId; // Changed from category
  final bool isChecked;

  const ShoppingItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.typeId,
    this.isChecked = false,
  });

  ShoppingItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? typeId,
    bool? isChecked,
  }) {
    return ShoppingItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      typeId: typeId ?? this.typeId,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'typeId': typeId,
      'isChecked': isChecked,
    };
  }

  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    return ShoppingItem(
      name: map['name'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? '',
      typeId: map['typeId'] as String? ?? map['category'] as String?, // Fallback for old data
      isChecked: map['isChecked'] ?? false,
    );
  }
}

class ShoppingList {
  final String id;
  final String mealPlanId;
  final DateTime createdAt;
  final List<ShoppingItem> items;

  const ShoppingList({
    required this.id,
    required this.mealPlanId,
    required this.createdAt,
    required this.items,
  });

  ShoppingList copyWith({
    String? id,
    String? mealPlanId,
    DateTime? createdAt,
    List<ShoppingItem>? items,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      mealPlanId: mealPlanId ?? this.mealPlanId,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mealPlanId': mealPlanId,
      'createdAt': Timestamp.fromDate(createdAt),
      'items': items.map((x) => x.toMap()).toList(),
    };
  }

  factory ShoppingList.fromMap(String id, Map<String, dynamic> map) {
    return ShoppingList(
      id: id,
      mealPlanId: map['mealPlanId'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      items: List<ShoppingItem>.from(
        (map['items'] as List<dynamic>? ?? []).map<ShoppingItem>(
          (x) => ShoppingItem.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }
}
