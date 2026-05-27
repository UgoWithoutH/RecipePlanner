import 'package:cloud_firestore/cloud_firestore.dart';

class RecipeContribution {
  final String recipeId;
  final String recipeName;
  final double quantity; // qty needed from this recipe (in recipe's display unit)
  final String unit;

  const RecipeContribution({
    required this.recipeId,
    required this.recipeName,
    required this.quantity,
    required this.unit,
  });

  Map<String, dynamic> toMap() => {
        'recipeId': recipeId,
        'recipeName': recipeName,
        'quantity': quantity,
        'unit': unit,
      };

  factory RecipeContribution.fromMap(Map<String, dynamic> m) =>
      RecipeContribution(
        recipeId: m['recipeId'] as String? ?? '',
        recipeName: m['recipeName'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0.0,
        unit: m['unit'] as String? ?? '',
      );
}

class ShoppingItem {
  final String name;
  final double quantity;
  final String unit;
  final String? typeId;
  final bool isChecked;
  final List<RecipeContribution> contributions;
  final double totalRequiredBase; // total before pantry deduction, in base units (ml/g/piece)

  const ShoppingItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.typeId,
    this.isChecked = false,
    this.contributions = const [],
    this.totalRequiredBase = 0,
  });

  ShoppingItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? typeId,
    bool? isChecked,
    List<RecipeContribution>? contributions,
    double? totalRequiredBase,
  }) {
    return ShoppingItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      typeId: typeId ?? this.typeId,
      isChecked: isChecked ?? this.isChecked,
      contributions: contributions ?? this.contributions,
      totalRequiredBase: totalRequiredBase ?? this.totalRequiredBase,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'typeId': typeId,
      'isChecked': isChecked,
      'contributions': contributions.map((c) => c.toMap()).toList(),
      'totalRequiredBase': totalRequiredBase,
    };
  }

  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    // Backward compat: old data had 'recipeNames' (List<String>)
    List<RecipeContribution> parsedContribs;
    if (map['contributions'] != null) {
      parsedContribs = (map['contributions'] as List<dynamic>)
          .map((e) => RecipeContribution.fromMap(e as Map<String, dynamic>))
          .toList();
    } else {
      parsedContribs = ((map['recipeNames'] as List<dynamic>?) ?? [])
          .map((n) => RecipeContribution(
                recipeId: '',
                recipeName: n as String,
                quantity: 0,
                unit: map['unit'] as String? ?? '',
              ))
          .toList();
    }
    return ShoppingItem(
      name: map['name'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? '',
      typeId: map['typeId'] as String? ?? map['category'] as String?,
      isChecked: map['isChecked'] ?? false,
      contributions: parsedContribs,
      totalRequiredBase: (map['totalRequiredBase'] as num?)?.toDouble() ?? 0.0,
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
