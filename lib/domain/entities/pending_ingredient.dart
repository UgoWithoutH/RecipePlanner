import '../../core/constants/unit.dart';

/// Classe pour stocker les nouveaux ingrédients à créer lors de la sauvegarde d'une recette
class PendingIngredient {
  final String name;
  final String? typeId;
  final double quantity;
  final Unit unit;
  final String? notes;

  PendingIngredient({
    required this.name,
    required this.typeId,
    required this.quantity,
    required this.unit,
    this.notes,
  });
}
