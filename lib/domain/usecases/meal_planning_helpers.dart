part of 'meal_planning_service.dart';

/// Gère l'injection des userSelectedMeals dans le plan
void _handleUserSelectedMeals({
  required List<Meal>? userSelectedMeals,
  required List<Recipe> recipes,
  required List<Meal?> meals,
  required Map<int, List<Meal>> pendingLeftovers,
  required Map<String, int> recentRecipeDaysAgo,
  required DateTime startDate,
  required int durationDays,
  required int numMeals,
}) {
  if (userSelectedMeals == null || userSelectedMeals.isEmpty) return;

  // Passe 1 : placer tous les repas verrouillés dans meals[]
  // avant de calculer les cascades de restes, pour que les vérifications
  // meals[nextSlotUS] != null fonctionnent correctement.
  final slotsToProcess = <({int slot, Meal meal})>[];
  for (final meal in userSelectedMeals) {
    if (!meal.userSelected) continue;
    if (meal.date.isBefore(startDate) || meal.date.isAfter(startDate.add(Duration(days: durationDays - 1)))) continue;
    final slot = meal.date.difference(startDate).inDays * 2 + (meal.type == MealType.lunch ? 0 : 1);
    if (slot >= 0 && slot < numMeals) {
      if (meals[slot] != null) continue; // collision
      meals[slot] = meal.copyWith(userSelected: true);
      slotsToProcess.add((slot: slot, meal: meal));
    }
  }

  // Passe 2 : cascades de restes (tous les repas verrouillés sont déjà placés)
  for (final entry in slotsToProcess) {
    final slot = entry.slot;
    final meal = entry.meal;
    final cookedUS = meal.recipe.servings * meal.recipeMultiplier;
    var remainingLeftUS = cookedUS - meal.totalServings;
    int nextSlotUS = slot + 2;
    while (remainingLeftUS > 0 && nextSlotUS < numMeals) {
      // Slot occupé → arrêter la cascade (les restes ne sautent pas les jours occupés)
      if (meals[nextSlotUS] != null) { break; }
      final nextDateUS = startDate.add(Duration(days: nextSlotUS ~/ 2));
      if (!nextDateUS.isBefore(startDate) &&
          !nextDateUS.isAfter(startDate.add(Duration(days: durationDays - 1)))) {
        final leftoverUserServingsUS = <String, int>{};
        int leftoverTotalUS = 0;
        final sortedUSentries = meal.userServings.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
        for (int idx = 0; idx < sortedUSentries.length; idx++) {
          if (remainingLeftUS <= 0) break;
          final e = sortedUSentries[idx];
          final portionsNeeded = e.value;
          final usersLeftUS = sortedUSentries.length - idx;
          final fairShareUS = max(1, remainingLeftUS ~/ usersLeftUS);
          final toAssignUS = min(portionsNeeded, min(fairShareUS, remainingLeftUS));
          if (toAssignUS > 0) {
            leftoverUserServingsUS[e.key] = toAssignUS;
            leftoverTotalUS += toAssignUS;
            remainingLeftUS -= toAssignUS;
          }
        }
        if (leftoverTotalUS == 0) { break; } // slot couvert par d'autres restes
        final nextMealTypeUS = nextSlotUS % 2 == 0 ? MealType.lunch : MealType.dinner;
        pendingLeftovers.putIfAbsent(nextSlotUS, () => []).add(meal.copyWith(
          date: nextDateUS,
          type: nextMealTypeUS,
          isLeftoverMeal: true,
          userSelected: true,
          userServings: leftoverUserServingsUS,
          totalServings: leftoverTotalUS,
          recipeMultiplier: 1,
        ));
        recentRecipeDaysAgo[meal.recipe.id] = 0;
      }
      nextSlotUS += 2;
    }
  }
}

/// Gère la consommation des portions pour un slot userSelected
bool _handleUserSelectedSlot(
  int i,
  List<Meal?> meals,
  Map<String, int> usedRecipes,
  List<User> users,
  Map<String, Map<String, (int, int)>> recipeUserServingsMap,
  Map<String, Map<MealType, int>> remainingPortions,
  Map<String, (double, Unit)> pantryRemaining,
) {
  if (meals[i] != null && meals[i]!.userSelected == true) {
    usedRecipes[meals[i]!.recipe.id] = (usedRecipes[meals[i]!.recipe.id] ?? 0) + 1;
    final meal = meals[i]!;
    final servingsForRecipe = recipeUserServingsMap[meal.recipe.id] ?? {};
    for (final user in users) {
      final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
      final desired = meal.type == MealType.lunch ? lunch : dinner;
      final remaining = remainingPortions[user.id]![meal.type]!;
      int servingCount = 0;
      if (desired > 0 && remaining > 0) {
        servingCount = desired < remaining ? desired : remaining;
        remainingPortions[user.id]![meal.type] = remaining - servingCount;
      }
    }
    // Consomme les ingrédients du placard pour ce repas verrouillé
    if (!meal.isLeftoverMeal) {
      _consumePantryItems(
        recipe: meal.recipe,
        recipeMultiplier: meal.recipeMultiplier,
        pantryRemaining: pantryRemaining,
      );
    }
    return true;
  }
  return false;
}

/// Consomme les portions pour un slot généré normalement
(Map<String, int>, int) _consumePortions({
  required List<User> users,
  required Map<String, (int lunch, int dinner)> servingsForRecipe,
  required MealType mealType,
  required Map<String, Map<MealType, int>> remainingPortions,
  Set<String> excludedUsers = const {},
}) {
  final userServingsForMeal = <String, int>{};
  int totalConsumed = 0;
  for (final user in users) {
    if (excludedUsers.contains(user.id)) continue; // déjà couvert par un leftover ce slot
    final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
    final desired = mealType == MealType.lunch ? lunch : dinner;
    final remaining = remainingPortions[user.id]![mealType]!;
    int servingCount = 0;
    if (desired > 0 && remaining > 0) {
      servingCount = desired < remaining ? desired : remaining;
      remainingPortions[user.id]![mealType] = remaining - servingCount;
    }
    if (servingCount > 0) {
      userServingsForMeal[user.id] = servingCount;
      totalConsumed += servingCount;
    }
  }
  return (userServingsForMeal, totalConsumed);
}

/// Consomme les quantités du frigo/placard pour les ingrédients d'une recette sélectionnée
/// Ne consomme que si les unités sont compatibles (même famille)
void _consumePantryItems({
  required Recipe recipe,
  required int recipeMultiplier,
  required Map<String, (double, Unit)> pantryRemaining,
}) {
  if (pantryRemaining.isEmpty) return;
  for (final ingredient in recipe.ingredients) {
    final name = ingredient.ingredient.name.toLowerCase().trim();
    final pantryEntry = pantryRemaining[name];
    if (pantryEntry != null) {
      final (pantryQty, pantryBaseUnit) = pantryEntry;
      if (pantryBaseUnit == _baseUnit(ingredient.unit)) {
        final consumed = _toNormalized(ingredient.quantity * recipeMultiplier, ingredient.unit);
        pantryRemaining[name] = (max(0.0, pantryQty - consumed), pantryBaseUnit);
      }
    }
  }
}

/// Retourne l'unité de base de la famille de l'unité donnée
/// g/kg → g | ml/l → ml | c.à.s./tasse → c.à.t. | autres → inchangé
Unit _baseUnit(Unit unit) {
  switch (unit) {
    case Unit.kg:         return Unit.g;
    case Unit.l:          return Unit.ml;
    case Unit.tablespoon: return Unit.teaspoon;
    case Unit.cup:        return Unit.teaspoon;
    default:              return unit;
  }
}

/// Convertit une quantité vers l'unité de base de sa famille
double _toNormalized(double qty, Unit unit) {
  switch (unit) {
    case Unit.kg:         return qty * 1000.0; // kg → g
    case Unit.l:          return qty * 1000.0; // l → ml
    case Unit.tablespoon: return qty * 3.0;    // c.à.s. → c.à.t.
    case Unit.cup:        return qty * 48.0;   // tasse → c.à.t. (1 tasse = 16 c.à.s. = 48 c.à.t.)
    default:              return qty;
  }
}

/// Builds a cache of ingredient similarity between all recipe pairs
Map<String, Map<String, double>> _buildSimilarityCache(List<Recipe> recipes, Map<String, double> ingredientWeights) {
  final cache = <String, Map<String, double>>{};
  
  for (int i = 0; i < recipes.length; i++) {
    cache[recipes[i].id] = {};
    for (int j = 0; j < recipes.length; j++) {
      if (i != j) {
        cache[recipes[i].id]![recipes[j].id] = 
            _calculateIngredientSimilarity(recipes[i], recipes[j], ingredientWeights);
      }
    }
  }
  
  return cache;
}

/// Helper to calculate user servings for a meal
/// Returns (userServings map, totalConsumed)
(Map<String, int>, int) _calculateUserServings({
  required List<User> users,
  required Map<String, (int lunch, int dinner)> servingsForRecipe,
  required MealType mealType,
  required Map<String, Map<MealType, int>> remainingPortions,
  bool ignorePortions = false, // ignored, always false
}) {
  final userServingsForMeal = <String, int>{};
  int totalConsumed = 0;

  for (final user in users) {
    final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
    final desired = mealType == MealType.lunch ? lunch : dinner;
    final remaining = remainingPortions[user.id]![mealType]!;

    int servingCount = 0;
    // Always serve the minimum of desired and remaining (never more)
    if (desired > 0 && remaining > 0) {
      servingCount = desired < remaining ? desired : remaining;
      remainingPortions[user.id]![mealType] = remaining - servingCount;
    }

    if (servingCount > 0) {
      userServingsForMeal[user.id] = servingCount;
      totalConsumed += servingCount;
    }
  }

  return (userServingsForMeal, totalConsumed);
}

/// Calculates ingredient similarity between two recipes (0-1) using dynamic weighting
/// Weights each ingredient based on its rarity across all recipes
double _calculateIngredientSimilarity(Recipe r1, Recipe r2, Map<String, double> ingredientWeights) {
  if (r1.ingredients.isEmpty || r2.ingredients.isEmpty) return 0;

  final ing1Names = r1.ingredients.map((i) => i.ingredient.name.toLowerCase()).toSet();
  final ing2Names = r2.ingredients.map((i) => i.ingredient.name.toLowerCase()).toSet();
  if (ing1Names.isEmpty || ing2Names.isEmpty) return 0;

  double getWeight(String name) => ingredientWeights[name] ?? 1.0;

  // Weighted intersection
  double intersectionWeight = 0.0;
  for (final name in ing1Names.intersection(ing2Names)) {
    intersectionWeight += getWeight(name);
  }

  // Weighted union
  double unionWeight = 0.0;
  for (final name in ing1Names.union(ing2Names)) {
    unionWeight += getWeight(name);
  }

  if (unionWeight == 0.0) return 0.0;
  return intersectionWeight / unionWeight;
}
