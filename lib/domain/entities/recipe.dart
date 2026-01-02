import 'recipe_ingredient.dart' show RecipeIngredient;

class Recipe {
  final String id;
  final String title;
  final String description;
  final int preparationTime; // in minutes
  final int cookingTime; // in minutes
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final String category;
  final double rating; // 0 to 5
  final DateTime createdAt;
  final bool isFavorite;

  Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.preparationTime,
    required this.cookingTime,
    required this.ingredients,
    required this.instructions,
    required this.category,
    this.rating = 0.0,
    required this.createdAt,
    this.isFavorite = false,
  });

  // Getter for total time
  int get totalTime => preparationTime + cookingTime;

  // Copy with modifications
  Recipe copyWith({
    String? id,
    String? title,
    String? description,
    int? preparationTime,
    int? cookingTime,
    List<RecipeIngredient>? ingredients,
    List<String>? instructions,
    String? category,
    double? rating,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      preparationTime: preparationTime ?? this.preparationTime,
      cookingTime: cookingTime ?? this.cookingTime,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
