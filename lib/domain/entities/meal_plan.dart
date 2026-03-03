import 'recipe.dart';
import 'recipe_ingredient.dart';

/// Represents a single meal in the plan (lunch or dinner)
class Meal {
    Meal copyWith({
      Recipe? recipe,
      DateTime? date,
      MealType? type,
      int? totalServings,
      Map<String, int>? userServings,
      int? recipeMultiplier,
      bool? isLeftoverMeal,
      bool? userSelected,
    }) {
      return Meal(
        recipe: recipe ?? this.recipe,
        date: date ?? this.date,
        type: type ?? this.type,
        totalServings: totalServings ?? this.totalServings,
        userServings: userServings ?? this.userServings,
        recipeMultiplier: recipeMultiplier ?? this.recipeMultiplier,
        isLeftoverMeal: isLeftoverMeal ?? this.isLeftoverMeal,
        userSelected: userSelected ?? this.userSelected,
      );
    }
  final Recipe recipe;
  final DateTime date;
  final MealType type; // lunch or dinner
  final int totalServings; // total servings prepared for all users
  final Map<String, int> userServings; // userId -> servings count
  final int recipeMultiplier; // how many times the recipe must be prepared (batch cooking)
  final bool isLeftoverMeal; // true if this meal is a leftover from addExtraMeal (second meal)
  final bool userSelected; // true si choisi manuellement par l'utilisateur

  const Meal({
    required this.recipe,
    required this.date,
    required this.type,
    required this.totalServings,
    required this.userServings,
    this.recipeMultiplier = 1,
    this.isLeftoverMeal = false,
    this.userSelected = false,
  });
}

enum MealType { lunch, dinner }

/// Represents a complete meal plan over a period
class MealPlan {
  final String id;
  final DateTime startDate;
  final int durationDays;
  final List<Meal> meals;
  final DateTime createdAt;
  final List<RecipeIngredient> pantryItems;
  final List<String> selectedCategories;

  const MealPlan({
    required this.id,
    required this.startDate,
    required this.durationDays,
    required this.meals,
    required this.createdAt,
    this.pantryItems = const [],
    this.selectedCategories = const [],
  });

  MealPlan copyWith({
    String? id,
    DateTime? startDate,
    int? durationDays,
    List<Meal>? meals,
    DateTime? createdAt,
    List<RecipeIngredient>? pantryItems,
    List<String>? selectedCategories,
  }) {
    return MealPlan(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      durationDays: durationDays ?? this.durationDays,
      meals: meals ?? this.meals,
      createdAt: createdAt ?? this.createdAt,
      pantryItems: pantryItems ?? this.pantryItems,
      selectedCategories: selectedCategories ?? this.selectedCategories,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'startDate': '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
      'durationDays': durationDays,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'selectedCategories': selectedCategories,
      'pantryItems': pantryItems.map((item) => {
        'name': item.ingredient.name,
        'quantity': item.quantity,
        'unit': item.unit.name,
      }).toList(),
      'meals': meals
          .map((m) => {
                'recipeId': m.recipe.id,
                'recipeName': m.recipe.title,
                'recipeDescription': m.recipe.description,
                'recipeCategory': m.recipe.categoryIds.isNotEmpty ? m.recipe.categoryIds.first: '',
                'recipeCategoryIds': m.recipe.categoryIds,
                'recipeServings': m.recipe.servings,
                'recipeRating': m.recipe.rating,
                'recipeAddExtraMeal': m.recipe.addExtraMeal,
                'preparationTime': m.recipe.preparationTime,
                'cookingTime': m.recipe.cookingTime,
                'date': '${m.date.year}-${m.date.month.toString().padLeft(2, '0')}-${m.date.day.toString().padLeft(2, '0')}',
                'type': m.type.toString().split('.').last,
                'totalServings': m.totalServings,
                'userServings': m.userServings,
                'recipeMultiplier': m.recipeMultiplier,
                'isLeftoverMeal': m.isLeftoverMeal,
                'userSelected': m.userSelected,
              })
          .toList(),
    };
  }
}
