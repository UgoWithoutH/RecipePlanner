import 'recipe.dart';

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
    }) {
      return Meal(
        recipe: recipe ?? this.recipe,
        date: date ?? this.date,
        type: type ?? this.type,
        totalServings: totalServings ?? this.totalServings,
        userServings: userServings ?? this.userServings,
        recipeMultiplier: recipeMultiplier ?? this.recipeMultiplier,
        isLeftoverMeal: isLeftoverMeal ?? this.isLeftoverMeal,
      );
    }
  final Recipe recipe;
  final DateTime date;
  final MealType type; // lunch or dinner
  final int totalServings; // total servings prepared for all users
  final Map<String, int> userServings; // userId -> servings count
  final int recipeMultiplier; // how many times the recipe must be prepared (batch cooking)
  final bool isLeftoverMeal; // true if this meal is a leftover from addExtraMeal (second meal)

  const Meal({
    required this.recipe,
    required this.date,
    required this.type,
    required this.totalServings,
    required this.userServings,
    this.recipeMultiplier = 1,
    this.isLeftoverMeal = false,
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

  const MealPlan({
    required this.id,
    required this.startDate,
    required this.durationDays,
    required this.meals,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'startDate': '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
      'durationDays': durationDays,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'meals': meals
          .map((m) => {
                'recipeId': m.recipe.id,
                'preparationTime': m.recipe.preparationTime,
                'cookingTime': m.recipe.cookingTime,
                'recipeName': m.recipe.title,
                'date': '${m.date.year}-${m.date.month.toString().padLeft(2, '0')}-${m.date.day.toString().padLeft(2, '0')}',
                'type': m.type.toString().split('.').last,
                'totalServings': m.totalServings,
                'userServings': m.userServings,
                'recipeMultiplier': m.recipeMultiplier,
                'isLeftoverMeal': m.isLeftoverMeal,
              })
          .toList(),
    };
  }
}
