import 'recipe_ingredient.dart' show RecipeIngredient;
import '../../core/constants/meal_time.dart';

class Recipe {
  final String id;
  final String title;
  final String description;
  final int preparationTime;
  final int cookingTime;
  final int servings;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final List<String> categoryIds;
  final double rating;
  final DateTime createdAt;
  final bool isFavorite;
  final String? url;
  final MealTime mealTime;

  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.preparationTime,
    required this.cookingTime,
    required this.servings,
    required this.ingredients,
    required this.instructions,
    required this.categoryIds,
    this.rating = 0.0,
    required this.createdAt,
    this.isFavorite = false,
    this.url,
    this.mealTime = MealTime.both,
  });

  int get totalTime => preparationTime + cookingTime;

  Recipe copyWith({
    String? id,
    String? title,
    String? description,
    int? preparationTime,
    int? cookingTime,
    int? servings,
    List<RecipeIngredient>? ingredients,
    List<String>? instructions,
    List<String>? categoryIds,
    double? rating,
    DateTime? createdAt,
    bool? isFavorite,
    String? url,
    MealTime? mealTime,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      preparationTime: preparationTime ?? this.preparationTime,
      cookingTime: cookingTime ?? this.cookingTime,
      servings: servings ?? this.servings,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      categoryIds: categoryIds ?? this.categoryIds,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      url: url ?? this.url,
      mealTime: mealTime ?? this.mealTime,
    );
  }
}