import '../../core/constants/unit.dart';
import 'ingredient.dart';
import 'recipe_ingredient.dart';

class PantryItem {
  final String id;
  final String name;
  final String ingredientId;
  final String typeId;
  final String typeName;
  final double quantity;
  final Unit unit;
  final bool isUrgent;
  final DateTime updatedAt;

  const PantryItem({
    required this.id,
    required this.name,
    this.ingredientId = '',
    this.typeId = '',
    this.typeName = '',
    required this.quantity,
    required this.unit,
    this.isUrgent = false,
    required this.updatedAt,
  });

  PantryItem copyWith({
    String? id,
    String? name,
    String? ingredientId,
    String? typeId,
    String? typeName,
    double? quantity,
    Unit? unit,
    bool? isUrgent,
    DateTime? updatedAt,
  }) {
    return PantryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      ingredientId: ingredientId ?? this.ingredientId,
      typeId: typeId ?? this.typeId,
      typeName: typeName ?? this.typeName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      isUrgent: isUrgent ?? this.isUrgent,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore(String groupId) => {
        'groupId': groupId,
        'name': name,
        'ingredientId': ingredientId,
        'typeId': typeId,
        'typeName': typeName,
        'quantity': quantity,
        'unit': unit.name,
        'isUrgent': isUrgent,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory PantryItem.fromFirestore(String id, Map<String, dynamic> data) {
    return PantryItem(
      id: id,
      name: data['name'] as String? ?? '',
      ingredientId: data['ingredientId'] as String? ?? '',
      typeId: data['typeId'] as String? ?? '',
      typeName: data['typeName'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: Unit.values.firstWhere(
        (u) => u.name == data['unit'],
        orElse: () => Unit.piece,
      ),
      isUrgent: data['isUrgent'] as bool? ?? false,
      updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Converts to a RecipeIngredient for use in the meal planning algorithm.
  RecipeIngredient toRecipeIngredient() => RecipeIngredient(
        ingredient: Ingredient(id: ingredientId, name: name),
        quantity: quantity,
        unit: unit,
      );
}
