import '../entities/recipe.dart';
import '../entities/user_recipe_serving.dart';
import '../entities/user.dart';
import '../entities/meal_plan.dart';
import 'dart:math';
import '../entities/recipe_ingredient.dart';
import '../../core/constants/unit.dart';

/// Service for meal planning
/// 
/// This algorithm prioritizes:
/// 1. Coverage: ensures all users get their planned portions
/// 2. Diversity: tries to avoid repeating the same recipe too frequently
/// 3. Ingredient variety: penalizes repeating ingredients recently used
class MealPlanningService {
  /// Generates a meal plan for a given period
  /// 
  /// [recipes]: all available recipes
  /// [servings]: portions per user per recipe
  /// [users]: list of users
  /// [startDate]: starting date
  /// [durationDays]: number of days to plan
  /// [usagePenaltyWeight]: penalty multiplier for recipe reuse (default: 20)
  /// [recencyPenaltyWeight]: penalty for recently used recipes (default: 100)
  /// [similarityPenaltyWeight]: penalty for ingredient similarity (default: 30)
  /// [coverageBonusWeight]: bonus multiplier for portion coverage (default: 2)
  static MealPlan generateMealPlan({
    required List<Recipe> recipes,
    required List<UserRecipeServing> servings,
    required List<User> users,
    required DateTime startDate,
    required int durationDays,
    double usagePenaltyWeight = 20.0,
    double recencyPenaltyWeight = 100.0,
    double similarityPenaltyWeight = 30.0,
    double coverageBonusWeight = 2.0,
    double addExtraMealBonusWeight = 30.0,
    double endOfPlanCoverageBoost = 1.5,
    double endOfPlanThresholdRatio = 0.2,
    bool useMaxPossibleCoverageNormalization = false,
    double recencyDecayFactor = 0.9,
    bool useAbsoluteCoverageBonus = false,
    List<Meal>? recentMeals,
    List<Meal>? userSelectedMeals,
    List<RecipeIngredient> pantryItems = const [],
    List<String> selectedCategories = const [],
  }) {
    if (recipes.isEmpty || users.isEmpty) {
      throw Exception('Recipes and users are required');
    }

    final numMeals = durationDays * 2; // lunch + dinner per day
    final meals = List<Meal?>.filled(numMeals, null); // Pre-allocate slots
    final pendingLeftovers = <int, Meal>{}; // Track leftovers to insert

    print('[MPS] ===== generateMealPlan START =====');
    print('[MPS] durationDays=$durationDays numMeals=$numMeals startDate=$startDate');
    print('[MPS] recipes=${recipes.length} users=${users.length} servings=${servings.length}');
    print('[MPS] recentMeals=${recentMeals?.length ?? 0}');

    // Initialize recentRecipes and recentRecipeDaysAgo before userSelectedMeals loop
    // Note: recentRecipes is used for tracking recent selections for diversity,
    // but recency decay is calculated via recentRecipeDaysAgo for exponential decay
    var recentRecipeDaysAgo = <String, int>{}; // Utilisé pour la récence (historique + plan en cours)

    // --- INTEGRATION DES REPAS USER-SELECTED (verrouillage des slots) ---
    _handleUserSelectedMeals(
      userSelectedMeals: userSelectedMeals,
      recipes: recipes,
      meals: meals,
      pendingLeftovers: pendingLeftovers,
      recentRecipeDaysAgo: recentRecipeDaysAgo,
      startDate: startDate,
      durationDays: durationDays,
      numMeals: numMeals,
    );

    // Build recipe -> user servings map
    final recipeUserServingsMap = <String, Map<String, (int lunch, int dinner)>>{};
    for (final serving in servings) {
      recipeUserServingsMap.putIfAbsent(serving.recipeId, () => {});
      recipeUserServingsMap[serving.recipeId]![serving.userId] =
          (serving.lunchServings, serving.dinnerServings);
    }

    // Fallback: if no UserRecipeServing records exist at all, treat every user
    // as wanting 1 serving of every recipe for both lunch and dinner.
    final bool noServingsConfigured = servings.isEmpty;
    if (noServingsConfigured) {
      for (final recipe in recipes) {
        recipeUserServingsMap[recipe.id] = {};
        for (final user in users) {
          recipeUserServingsMap[recipe.id]![user.id] = (1, 1);
        }
      }
    }

    // Track remaining portions for each user and meal type.
    // If a user has no serving records, default to durationDays portions per
    // meal type (one per day) so the algorithm can fill all slots.
    final remainingPortions = <String, Map<MealType, int>>{};
    for (final user in users) {
      final lunchTotal = servings
          .where((s) => s.userId == user.id)
          .fold(0, (sum, s) => sum + s.lunchServings);
      final dinnerTotal = servings
          .where((s) => s.userId == user.id)
          .fold(0, (sum, s) => sum + s.dinnerServings);
      remainingPortions[user.id] = {
        MealType.lunch:  lunchTotal  > 0 ? lunchTotal  : durationDays,
        MealType.dinner: dinnerTotal > 0 ? dinnerTotal : durationDays,
      };
    }
    print('[MPS] remainingPortions (initial):');
    remainingPortions.forEach((uid, m) => print('[MPS]   user=$uid lunch=${m[MealType.lunch]} dinner=${m[MealType.dinner]}'));

    final usedRecipes = <String, int>{}; // track usage per recipe

    // Construit la map de suivi des ingrédients du frigo/placard
    // Clé : nom de l'ingrédient (minuscule), Valeur : (quantité normalisée, unité de base)
    // Les unités sont normalisées vers l'unité de base de leur famille :
    //   kg → g, l → ml, c.à.s./tasse → c.à.t.
    final pantryRemaining = <String, (double, Unit)>{};
    for (final item in pantryItems) {
      final name = item.ingredient.name.toLowerCase().trim();
      if (name.isNotEmpty) {
        final baseUnitPantry = _baseUnit(item.unit);
        final normalizedQty = _toNormalized(item.quantity, item.unit);
        final existing = pantryRemaining[name];
        if (existing != null && existing.$2 == baseUnitPantry) {
          pantryRemaining[name] = (existing.$1 + normalizedQty, baseUnitPantry);
        } else {
          pantryRemaining[name] = (normalizedQty, baseUnitPantry);
        }
      }
    }

    // Historique : recettes mangées récemment (toutes passées en paramètre)
    // Map recipeId -> daysAgo (plus petit daysAgo si plusieurs repas)
    final now = DateTime.now();
    if (recentMeals != null && recentMeals.isNotEmpty) {
      for (final meal in recentMeals) {
        final daysAgo = now.difference(meal.date).inDays;
        if (!recentRecipeDaysAgo.containsKey(meal.recipe.id) || daysAgo < recentRecipeDaysAgo[meal.recipe.id]!) {
          recentRecipeDaysAgo[meal.recipe.id] = daysAgo;
        }
      }
    }

    // Track full cycle: all recipes must be used once before reusing any
    // Only necessary when numMeals > recipes (otherwise no reuse needed)
    final requireFullCycle = numMeals > recipes.length;
    final usedInCurrentCycle = <String>{}; // recipes used in current cycle

    // Pre-compute ingredient similarity cache for performance
    final ingredientWeights = computeIngredientWeights(recipes);
    final similarityCache = _buildSimilarityCache(recipes, ingredientWeights);

    // --- GESTION DES LEFTOVERS HISTORIQUES (addExtraMeal sur J-1) ---
    print('[MPS] Checking historical leftovers for J-1 (${startDate.subtract(const Duration(days: 1))})');
    if (recentMeals != null && recentMeals.isNotEmpty) {
      final expectedDate = startDate.subtract(const Duration(days: 1));
      // Filtre tous les repas J-1 avec addExtraMeal
      final leftoversJ1 = recentMeals.where((m) =>
          m.date.year == expectedDate.year &&
          m.date.month == expectedDate.month &&
          m.date.day == expectedDate.day &&
          m.recipe.addExtraMeal
      ).toList();
      print('[MPS] leftoversJ1 count=${leftoversJ1.length}');
      for (final meal in leftoversJ1) {
        // Slot : lunch = 0, dinner = 1
        final slot = (meal.type == MealType.lunch) ? 0 : 1;
        if (slot < meals.length) {
          if (meals[slot] != null) {
            // Collision : slot déjà occupé (userSelected ou autre leftover)
            print('[MealPlanningService] Collision leftover historique sur slot $slot ($startDate, ${meal.type})');
            continue;
          }
          int recipeMultiplier = 1;
          if (meal.totalServings > 0 && meal.recipe.servings > 0) {
            recipeMultiplier = (meal.totalServings / meal.recipe.servings).ceil();
          }
          meals[slot] = Meal(
            recipe: meal.recipe,
            date: startDate,
            type: meal.type,
            totalServings: meal.totalServings,
            userServings: meal.userServings,
            recipeMultiplier: recipeMultiplier,
            isLeftoverMeal: true,
          );
          recentRecipeDaysAgo[meal.recipe.id] = 0;
        }
      }
    }

    print('[MPS] Starting slot loop (numMeals=$numMeals)...');
    for (int i = 0; i < numMeals; i++) {
      final _dbgDate = startDate.add(Duration(days: i ~/ 2));
      final _dbgType = i % 2 == 0 ? 'lunch' : 'dinner';
      print('[MPS] Slot $i ($_dbgDate $_dbgType) meals[i]=${meals[i]?.recipe.title ?? 'null'}');
      // 1. Gestion des leftovers (pendingLeftovers)
      if (_handleLeftover(i, pendingLeftovers, meals)) { print('[MPS]   -> pendingLeftover injected'); continue; }
      // 2. Gestion des userSelectedMeals
      if (_handleUserSelectedSlot(i, meals, usedRecipes, users, recipeUserServingsMap, remainingPortions)) { print('[MPS]   -> userSelected'); continue; }
      // 3. Skip slots already filled by historical leftover injection (J-1 addExtraMeal)
      //    These were set directly into meals[i] before the loop and must not be overwritten.
      if (meals[i] != null) { print('[MPS]   -> already filled (historical leftover)'); continue; }
      // 4. Génération normale du slot
      final mealDate = startDate.add(Duration(days: i ~/ 2));
      final mealType = i % 2 == 0 ? MealType.lunch : MealType.dinner;
      final totalRemainingPortions = remainingPortions.values
          .fold<int>(0, (sum, map) => sum + (map[mealType] ?? 0));
      print('[MPS]   totalRemainingPortions($mealType)=$totalRemainingPortions');
      if (totalRemainingPortions == 0) {
        // No more portions needed for this meal type — skip but keep going for
        // other days / other types instead of stopping the whole plan.
        print('[MPS]   -> SKIP (no portions left)');
        continue;
      }
      final selectedRecipe = _selectBestRecipe(
        availableRecipes: recipes,
        recipeUserServingsMap: recipeUserServingsMap,
        users: users,
        usedRecipes: usedRecipes,
        mealType: mealType,
        remainingPortions: remainingPortions,
        similarityCache: similarityCache,
        usagePenaltyWeight: usagePenaltyWeight,
        recencyPenaltyWeight: recencyPenaltyWeight,
        similarityPenaltyWeight: similarityPenaltyWeight,
        coverageBonusWeight: coverageBonusWeight,
        addExtraMealBonusWeight: addExtraMealBonusWeight,
        endOfPlanCoverageBoost: endOfPlanCoverageBoost,
        endOfPlanThresholdRatio: endOfPlanThresholdRatio,
        useMaxPossibleCoverageNormalization: useMaxPossibleCoverageNormalization,
        requireFullCycle: requireFullCycle,
        usedInCurrentCycle: usedInCurrentCycle,
        recentRecipeDaysAgo: recentRecipeDaysAgo,
        initialTotalPortions: users.length * durationDays * 2,
        recencyDecayFactor: recencyDecayFactor,
        useAbsoluteCoverageBonus: useAbsoluteCoverageBonus,
        pantryRemaining: pantryRemaining,
        canAddLeftover: i + 2 < numMeals,
        slotsRemaining: numMeals - i,
      );
      if (selectedRecipe == null) {
        print('[MPS]   -> selectedRecipe=NULL');
        meals[i] = null;
        continue;
      }
      print('[MPS]   -> selectedRecipe=${selectedRecipe.title}');
      final servingsForRecipe = recipeUserServingsMap[selectedRecipe.id] ?? {};
      final (userServingsForMeal, totalConsumed) = _consumePortions(
        users: users,
        servingsForRecipe: servingsForRecipe,
        mealType: mealType,
        remainingPortions: remainingPortions,
      );
      print('[MPS]   totalConsumed=$totalConsumed');
      if (totalConsumed == 0) {
        print('[MPS]   -> SKIP (totalConsumed=0)');
        meals[i] = null;
        continue;
      }
      int requiredServings = totalConsumed;
      if (selectedRecipe.addExtraMeal) {
        requiredServings = totalConsumed * 2;
      }
      final recipeMultiplier = requiredServings > 0 
          ? (requiredServings / selectedRecipe.servings).ceil() 
          : 1;
      // Consomme les ingrédients du frigo/placard pour cette recette
      _consumePantryItems(
        recipe: selectedRecipe,
        recipeMultiplier: recipeMultiplier,
        pantryRemaining: pantryRemaining,
      );
      final meal = Meal(
        recipe: selectedRecipe,
        date: mealDate,
        type: mealType,
        totalServings: totalConsumed,
        userServings: userServingsForMeal,
        recipeMultiplier: recipeMultiplier,
        isLeftoverMeal: false,
        userSelected: false,
      );
      meals[i] = meal;
      usedRecipes[selectedRecipe.id] = (usedRecipes[selectedRecipe.id] ?? 0) + 1;
      // Met à jour la récence pour la recette choisie
      recentRecipeDaysAgo.updateAll((key, value) => value + 1);
      recentRecipeDaysAgo[selectedRecipe.id] = 0;
      if (requireFullCycle) {
        usedInCurrentCycle.add(selectedRecipe.id);
        if (usedInCurrentCycle.length == recipes.length) {
          usedInCurrentCycle.clear();
        }
      }
      if (selectedRecipe.addExtraMeal && i + 2 < numMeals && totalConsumed > 0) {
        final nextMealDate = mealDate.add(const Duration(days: 1));
        pendingLeftovers[i + 2] = Meal(
          recipe: selectedRecipe,
          date: nextMealDate,
          type: mealType,
          totalServings: totalConsumed,
          userServings: userServingsForMeal,
          recipeMultiplier: recipeMultiplier,
          isLeftoverMeal: true,
          userSelected: false,
        );
      }
    }

    final finalMeals = meals.whereType<Meal>().toList();
    print('[MPS] ===== generateMealPlan END ===== meals generated: ${finalMeals.length}');
    for (final m in finalMeals) print('[MPS]   ${m.date} ${m.type.name} ${m.recipe.title} leftover=${m.isLeftoverMeal}');

    return MealPlan(
      id: '',
      startDate: startDate,
      durationDays: durationDays,
      meals: finalMeals,
      createdAt: DateTime.now(),
      pantryItems: pantryItems,
      selectedCategories: selectedCategories,
    );
  }
  /// Gère l'injection des userSelectedMeals dans le plan
  static void _handleUserSelectedMeals({
    required List<Meal>? userSelectedMeals,
    required List<Recipe> recipes,
    required List<Meal?> meals,
    required Map<int, Meal> pendingLeftovers,
    required Map<String, int> recentRecipeDaysAgo,
    required DateTime startDate,
    required int durationDays,
    required int numMeals,
  }) {
    if (userSelectedMeals == null || userSelectedMeals.isEmpty) return;
    for (final meal in userSelectedMeals) {
      if (!meal.userSelected) continue;
      if (meal.date.isBefore(startDate) || meal.date.isAfter(startDate.add(Duration(days: durationDays - 1)))) continue;
      final slot = meal.date.difference(startDate).inDays * 2 + (meal.type == MealType.lunch ? 0 : 1);
      if (slot >= 0 && slot < numMeals) {
        final exists = recipes.any((r) => r.id == meal.recipe.id);
        if (exists) {
          if (meals[slot] != null) {
            // Collision userSelected sur slot, slot déjà occupé
            continue;
          }
          meals[slot] = meal.copyWith(userSelected: true);
          if (meal.recipe.addExtraMeal) {
            final nextDate = meal.date.add(const Duration(days: 1));
            if (!nextDate.isBefore(startDate) && !nextDate.isAfter(startDate.add(Duration(days: durationDays - 1)))) {
              final nextSlot = slot + 2;
              if (nextSlot >= 0 && nextSlot < numMeals) {
                if (meals[nextSlot] != null || pendingLeftovers.containsKey(nextSlot)) {
                  // Collision leftover userSelected sur slot, slot déjà occupé
                } else {
                  final origUserServings = Map<String, int>.from(meal.userServings);
                  final origTotalServings = meal.totalServings;
                  final leftoverUserServings = <String, int>{};
                  origUserServings.forEach((k, v) {
                    leftoverUserServings[k] = v;
                  });
                  final leftoverTotalServings = origTotalServings;
                  final leftoverMeal = meal.copyWith(
                    date: nextDate,
                    isLeftoverMeal: true,
                    userSelected: true,
                    userServings: leftoverUserServings,
                    totalServings: leftoverTotalServings,
                  );
                  pendingLeftovers[nextSlot] = leftoverMeal;
                  recentRecipeDaysAgo[meal.recipe.id] = 0;
                }
              }
            }
          }
        }
      }
    }
  }

  /// Gère la consommation des portions pour un slot userSelected
  static bool _handleUserSelectedSlot(
    int i,
    List<Meal?> meals,
    Map<String, int> usedRecipes,
    List<User> users,
    Map<String, Map<String, (int, int)>> recipeUserServingsMap,
    Map<String, Map<MealType, int>> remainingPortions,
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
      return true;
    }
    return false;
  }

  /// Gère l'injection d'un leftover dans le slot
  static bool _handleLeftover(
    int i,
    Map<int, Meal> pendingLeftovers,
    List<Meal?> meals,
  ) {
    if (pendingLeftovers.containsKey(i)) {
      final leftoverMeal = pendingLeftovers[i]!;
      meals[i] = leftoverMeal;
      return true;
    }
    return false;
  }

  /// Consomme les portions pour un slot généré normalement
  static (Map<String, int>, int) _consumePortions({
    required List<User> users,
    required Map<String, (int lunch, int dinner)> servingsForRecipe,
    required MealType mealType,
    required Map<String, Map<MealType, int>> remainingPortions,
  }) {
    final userServingsForMeal = <String, int>{};
    int totalConsumed = 0;
    for (final user in users) {
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

  /// Selects the best recipe for a meal
  /// 
  /// Prioritizes:
  /// 1. Coverage of remaining portions (or desired servings if portions exhausted)
  /// 2. Diversity (avoid recently used recipes)
  /// 3. Ingredient similarity
  /// 4. Full cycle rule: can't reuse a recipe until all recipes used once (only if meals > recipes)
  /// Sélectionne la meilleure recette pour un slot donné
  ///
  /// Les pondérations suivantes influencent le score final :
  /// - usagePenaltyWeight : pénalise la réutilisation fréquente d'une recette
  /// - recencyPenaltyWeight : pénalise la récence d'utilisation
  /// - similarityPenaltyWeight : pénalise la similarité d'ingrédients
  /// - coverageBonusWeight : favorise la couverture des portions
  /// - addExtraMealBonusWeight : favorise les recettes générant des restes
  /// - endOfPlanCoverageBoost : booste la couverture en fin de plan
  /// - cyclePenaltyWeight : pénalise la réutilisation avant d'avoir fait le tour
  static Recipe? _selectBestRecipe({
    required List<Recipe> availableRecipes,
    required Map<String, Map<String, (int, int)>> recipeUserServingsMap,
    required List<User> users,
    required Map<String, int> usedRecipes,
    required MealType mealType,
    required Map<String, Map<MealType, int>> remainingPortions,
    required Map<String, Map<String, double>> similarityCache,
    required double usagePenaltyWeight,
    required double recencyPenaltyWeight,
    required double similarityPenaltyWeight,
    required double coverageBonusWeight,
    double addExtraMealBonusWeight = 30.0,
    double endOfPlanCoverageBoost = 1.5,
    double endOfPlanThresholdRatio = 0.2,
    bool useMaxPossibleCoverageNormalization = false,
    int? initialTotalPortions,
    bool requireFullCycle = false,
    Set<String> usedInCurrentCycle = const {},
    Map<String, int>? recentRecipeDaysAgo,
    double cyclePenaltyWeight = 50.0,
    double recencyDecayFactor = 0.9,
    bool useAbsoluteCoverageBonus = false,
    Map<String, (double, Unit)> pantryRemaining = const <String, (double, Unit)>{},
    double pantryBonusWeight = 70.0,
    bool canAddLeftover = true,
    int slotsRemaining = 1,
  }) {
    if (availableRecipes.isEmpty) return null;

    final candidates = <Recipe>[];
    double bestScore = double.infinity;
    const epsilon = 1e-6;
    // recentRecipes n'est plus utilisé pour la récence

    final maxTimesUsed = usedRecipes.values.fold<int>(0, (max, val) => val > max ? val : max);
    final totalRemainingPortions = remainingPortions.values
        .fold<int>(0, (sum, map) => sum + (map[mealType] ?? 0));

    // Optimisation: calculer totalConsumed et maxPossibleCoverage une seule fois par candidate
    final Map<String, int> candidateTotalConsumed = {};
    final Map<String, Map<MealType, double>> maxPossibleCoverageMap = {};
    for (final recipe in availableRecipes) {
      final servingsForRecipe = recipeUserServingsMap[recipe.id] ?? {};
      int totalConsumed = 0;
      for (final user in users) {
        final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
        final desired = mealType == MealType.lunch ? lunch : dinner;
        final remaining = remainingPortions[user.id]![mealType]!;
        if (remaining > 0 && desired > 0) {
          totalConsumed += remaining < desired ? remaining : desired;
        }
      }
      candidateTotalConsumed[recipe.id] = totalConsumed;
      // Pre-compute maxPossibleCoverage for each meal type
      maxPossibleCoverageMap[recipe.id] = {};
      for (final type in [MealType.lunch, MealType.dinner]) {
        double maxCoverage = 0.0;
        for (final user in users) {
          final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
          maxCoverage += (type == MealType.lunch ? lunch : dinner);
        }
        maxPossibleCoverageMap[recipe.id]![type] = maxCoverage;
      }
    }

    for (final recipe in availableRecipes) {
      final totalConsumed = candidateTotalConsumed[recipe.id]!;
      if (totalConsumed == 0) {
        continue;
      }
      final servingsForRecipe = recipeUserServingsMap[recipe.id] ?? {};
      // --- Coverage ---
      final coverageScore = totalConsumed.toDouble();
      final maxPossibleCoverage = maxPossibleCoverageMap[recipe.id]?[mealType] ?? 0.0;
      double normalizedCoverage = maxPossibleCoverage > 0
          ? (coverageScore / maxPossibleCoverage).clamp(0.0, 1.0)
          : 0.0;
      double coverageComponent = -coverageScore * coverageBonusWeight;
      if (initialTotalPortions != null && initialTotalPortions > 0) {
        final ratio = totalRemainingPortions / initialTotalPortions;
        if (ratio < endOfPlanThresholdRatio) {
          final t = 1.0 - (ratio / endOfPlanThresholdRatio);
          coverageComponent *= 1.0 + t * (endOfPlanCoverageBoost - 1.0);
        }
      }
      final timesUsed = usedRecipes[recipe.id] ?? 0;
      final normalizedUsage = maxTimesUsed > 0 ? (timesUsed / maxTimesUsed).clamp(0.0, 1.0) : 0.0;
      final usageComponent = normalizedUsage * usagePenaltyWeight;
      double recencyScore = 0.0;
      final decayFactor = recencyDecayFactor;
      if (recentRecipeDaysAgo != null && recentRecipeDaysAgo.containsKey(recipe.id)) {
        final daysAgo = recentRecipeDaysAgo[recipe.id]!;
        recencyScore = pow(decayFactor, daysAgo).toDouble();
      }
      recencyScore = recencyScore.clamp(0.0, 1.0);
      final recencyComponent = recencyScore * recencyPenaltyWeight;
      // New logic: calculate ingredient similarity with all recipes in recentRecipeDaysAgo (history + plan)
      double normalizedSimilarity = 0.0;
      if (recentRecipeDaysAgo != null && recentRecipeDaysAgo.isNotEmpty) {
        double weightedSimilarity = 0.0;
        double totalWeight = 0.0;
        for (final entry in recentRecipeDaysAgo.entries) {
          if (entry.key == recipe.id) continue; // do not compare to self
          final similarity = similarityCache[recipe.id]?[entry.key] ?? 0.0;
          // Weight: the more recent the recipe (small daysAgo), the more the similarity counts
          final daysAgo = entry.value;
          final recencyWeight = 1.0 / (1.0 + daysAgo); // ex: daysAgo=0 => 1.0, daysAgo=1 => 0.5, etc.
          weightedSimilarity += similarity * recencyWeight;
          totalWeight += recencyWeight;
        }
        normalizedSimilarity = totalWeight > 0 ? (weightedSimilarity / totalWeight) : 0.0;
        normalizedSimilarity = normalizedSimilarity.clamp(0.0, 1.0);
      }
      final similarityComponent = normalizedSimilarity * similarityPenaltyWeight;
        final addExtraMealComponent = recipe.addExtraMeal && normalizedCoverage > 0 && canAddLeftover
          ? -normalizedCoverage * addExtraMealBonusWeight
          : 0.0;
      double cyclePenalty = 0.0;
      if (requireFullCycle && usedInCurrentCycle.contains(recipe.id)) {
        final cycleProgress = usedInCurrentCycle.length.toDouble() / availableRecipes.length;
        cyclePenalty = cyclePenaltyWeight * cycleProgress.clamp(0.0, 1.0);
      }
      // --- Bonus frigo/placard avec urgence dynamique ---
      // Pour chaque ingrédient en stock correspondant, on calcule combien de fois
      // la recette doit encore être cuisinée pour épuiser le stock restant.
      // Plus l'urgence est grande (peu de slots restants vs beaucoup de stock),
      // plus le bonus est fort — peut surpasser la pénalité de récence.
      double pantryComponent = 0.0;
      if (pantryRemaining.isNotEmpty && recipe.ingredients.isNotEmpty) {
        int matchCount = 0;
        int maxUsesNeeded = 0;
        for (final ingredient in recipe.ingredients) {
          final name = ingredient.ingredient.name.toLowerCase().trim();
          final pantryEntry = pantryRemaining[name];
          if (pantryEntry != null) {
            final (pantryQty, pantryBaseUnit) = pantryEntry;
            if (pantryBaseUnit == _baseUnit(ingredient.unit) && pantryQty > 0.0) {
              matchCount++;
              final normalizedIngQty = _toNormalized(ingredient.quantity, ingredient.unit);
              if (normalizedIngQty > 0) {
                final usesNeeded = (pantryQty / normalizedIngQty).ceil();
                if (usesNeeded > maxUsesNeeded) maxUsesNeeded = usesNeeded;
              }
            }
          }
        }
        if (matchCount > 0) {
          // urgencyFactor : 1.0 (temps suffisant) → 3.0 (dernier moment)
          double urgencyFactor = 1.0;
          if (slotsRemaining > 0 && maxUsesNeeded > 0) {
            final urgency = (maxUsesNeeded / slotsRemaining).clamp(0.0, 2.0);
            urgencyFactor = 1.0 + urgency * 2.0;
          }
          pantryComponent = -matchCount * pantryBonusWeight * urgencyFactor;
        }
      }
      final totalScore = usageComponent + recencyComponent + similarityComponent +
          coverageComponent + addExtraMealComponent + cyclePenalty + pantryComponent;
      if (totalScore < bestScore - epsilon) {
        bestScore = totalScore;
        candidates.clear();
        candidates.add(recipe);
      } else if ((totalScore - bestScore).abs() < epsilon) {
        candidates.add(recipe);
      }
    }

    // Fallback: if no recipe consumes any portion, return null (empty slot)
    if (candidates.isEmpty) {
      // No possible candidate for this slot (incoherent data) — empty slot
      return null;
    }

    // Tie-break deterministic: least used, then by totalConsumed (coverage), then by ascending ID
    int minUsage = candidates.map((r) => usedRecipes[r.id] ?? 0).reduce(min);
    final leastUsed = candidates.where((r) => (usedRecipes[r.id] ?? 0) == minUsage).toList();
    if (leastUsed.length == 1) return leastUsed.first;
    int maxConsumedTieBreak = 0;
    for (final recipe in leastUsed) {
      final totalConsumed = candidateTotalConsumed[recipe.id]!;
      maxConsumedTieBreak = max(maxConsumedTieBreak, totalConsumed);
    }
    final byConsumption = leastUsed.where((r) {
      final totalConsumed = candidateTotalConsumed[r.id]!;
      return totalConsumed == maxConsumedTieBreak;
    }).toList();
    if (byConsumption.length == 1) return byConsumption.first;
    byConsumption.sort((a, b) => a.id.compareTo(b.id));
    return byConsumption.first;
  }

  /// Consomme les quantités du frigo/placard pour les ingrédients d'une recette sélectionnée
  /// Ne consomme que si les unités sont compatibles (même famille)
  static void _consumePantryItems({
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
  static Unit _baseUnit(Unit unit) {
    switch (unit) {
      case Unit.kg:         return Unit.g;
      case Unit.l:          return Unit.ml;
      case Unit.tablespoon: return Unit.teaspoon;
      case Unit.cup:        return Unit.teaspoon;
      default:              return unit;
    }
  }

  /// Convertit une quantité vers l'unité de base de sa famille
  static double _toNormalized(double qty, Unit unit) {
    switch (unit) {
      case Unit.kg:         return qty * 1000.0; // kg → g
      case Unit.l:          return qty * 1000.0; // l → ml
      case Unit.tablespoon: return qty * 3.0;    // c.à.s. → c.à.t.
      case Unit.cup:        return qty * 48.0;   // tasse → c.à.t. (1 tasse = 16 c.à.s. = 48 c.à.t.)
      default:              return qty;
    }
  }

  /// Builds a cache of ingredient similarity between all recipe pairs
  static Map<String, Map<String, double>> _buildSimilarityCache(List<Recipe> recipes, Map<String, double> ingredientWeights) {
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
  static (Map<String, int>, int) _calculateUserServings({
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

  /// Calculates dynamic ingredient weights according to their frequency in all recipes
  static Map<String, double> computeIngredientWeights(List<Recipe> recipes) {
    final freq = <String, int>{};
    int total = 0;
    for (final recipe in recipes) {
      for (final ing in recipe.ingredients) {
        final name = ing.ingredient.name.toLowerCase();
        freq[name] = (freq[name] ?? 0) + 1;
        total++;
      }
    }
    final weights = <String, double>{};
    for (final entry in freq.entries) {
      weights[entry.key] = 1.0 - (entry.value / total);
      if (weights[entry.key]! < 0.0) weights[entry.key] = 0.0;
    }
    return weights;
  }

  /// Calculates ingredient similarity between two recipes (0-1) using dynamic weighting
  /// Weights each ingredient based on its rarity across all recipes
  static double _calculateIngredientSimilarity(Recipe r1, Recipe r2, Map<String, double> ingredientWeights) {
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
}