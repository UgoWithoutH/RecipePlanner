import 'ingredient.dart';
import '../../core/constants/unit.dart';

class RecipeIngredient {
  final Ingredient ingredient;
  final double quantity;
  final Unit unit; // <- on utilise l'enum Unit
  final String? notes;

  RecipeIngredient({
    required this.ingredient,
    required this.quantity,
    required this.unit,
    this.notes,
  });

  // Copy with modifications
  RecipeIngredient copyWith({
    Ingredient? ingredient,
    double? quantity,
    Unit? unit,
    String? notes,
  }) {
    return RecipeIngredient(
      ingredient: ingredient ?? this.ingredient,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() => '$quantity ${unit.label} of ${ingredient.name}';
}