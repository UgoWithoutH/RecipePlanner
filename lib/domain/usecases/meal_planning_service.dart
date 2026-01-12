import '../entities/recipe.dart';
import '../entities/user_recipe_serving.dart';
import '../entities/user.dart';
import '../entities/meal_plan.dart';

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
  }) {
    if (recipes.isEmpty || users.isEmpty) {
      throw Exception('Recipes and users are required');
    }

    final numMeals = durationDays * 2; // lunch + dinner per day
    final meals = List<Meal?>.filled(numMeals, null); // Pre-allocate slots
    final pendingLeftovers = <int, Meal>{}; // Track leftovers to insert

    // Build recipe -> user servings map
    final recipeUserServingsMap = <String, Map<String, (int lunch, int dinner)>>{};
    for (final serving in servings) {
      recipeUserServingsMap.putIfAbsent(serving.recipeId, () => {});
      recipeUserServingsMap[serving.recipeId]![serving.userId] =
          (serving.lunchServings, serving.dinnerServings);
    }

    // Track remaining portions for each user and meal type
    final remainingPortions = <String, Map<MealType, int>>{};
    for (final user in users) {
      remainingPortions[user.id] = {
        MealType.lunch: servings
            .where((s) => s.userId == user.id)
            .fold(0, (sum, s) => sum + s.lunchServings),
        MealType.dinner: servings
            .where((s) => s.userId == user.id)
            .fold(0, (sum, s) => sum + s.dinnerServings),
      };
    }

    final usedRecipes = <String, int>{}; // track usage per recipe
    final recentRecipes = <String>[]; // sliding window for diversity
    
    // Track full cycle: all recipes must be used once before reusing any
    // Only necessary when numMeals > recipes (otherwise no reuse needed)
    final requireFullCycle = numMeals > recipes.length;
    final usedInCurrentCycle = <String>{}; // recipes used in current cycle
    
    // Pre-compute ingredient similarity cache for performance
    final similarityCache = _buildSimilarityCache(recipes);

    for (int i = 0; i < numMeals; i++) {
      // Skip if slot already reserved by a leftover
      if (pendingLeftovers.containsKey(i)) {
        final leftoverMeal = pendingLeftovers[i]!;
        meals[i] = leftoverMeal;
        
        // Track leftover in recent recipes for diversity (avoid similar ingredients)
        recentRecipes.add(leftoverMeal.recipe.id);
        if (recentRecipes.length > 5) recentRecipes.removeAt(0);
        // Note: usedRecipes is NOT incremented - leftovers are not a new choice
        
        continue;
      }

      final mealDate = startDate.add(Duration(days: i ~/ 2));
      final mealType = i % 2 == 0 ? MealType.lunch : MealType.dinner;

      // Check if all portions are exhausted for this meal type
      final allPortionsExhausted = remainingPortions.values
          .every((map) => (map[mealType] ?? 0) == 0);

      // Select best recipe considering remaining portions and diversity
      final selectedRecipe = _selectBestRecipe(
        availableRecipes: recipes,
        recipeUserServingsMap: recipeUserServingsMap,
        users: users,
        usedRecipes: usedRecipes,
        recentRecipes: recentRecipes,
        mealType: mealType,
        remainingPortions: remainingPortions,
        similarityCache: similarityCache,
        usagePenaltyWeight: usagePenaltyWeight,
        recencyPenaltyWeight: recencyPenaltyWeight,
        similarityPenaltyWeight: similarityPenaltyWeight,
        coverageBonusWeight: coverageBonusWeight,
        allPortionsExhausted: allPortionsExhausted,
        requireFullCycle: requireFullCycle,
        usedInCurrentCycle: usedInCurrentCycle,
      );

      if (selectedRecipe == null) break;

      // Calculate servings for this meal - ENSURE ALL USERS ARE COVERED
      final servingsForRecipe = recipeUserServingsMap[selectedRecipe.id] ?? {};
      final (userServingsForMeal, totalConsumed) = _calculateUserServings(
        users: users,
        servingsForRecipe: servingsForRecipe,
        mealType: mealType,
        remainingPortions: remainingPortions,
        ignorePortions: allPortionsExhausted, // Ignore portions if all exhausted
      );

      // Batch cooking: calculate how many times the recipe must be prepared
      // Formula: ceil(requiredServings / recipe.servings)
      // If addExtraMeal = true: requiredServings = totalConsumed × 2 (cook once for 2 meals)
      // Example: 7 portions needed, recipe makes 4 → multiplier = 2 (8 portions, 1 leftover)
      int requiredServings = totalConsumed;
      if (selectedRecipe.addExtraMeal) {
        requiredServings = totalConsumed * 2;  // Double for both meals
      }
      final recipeMultiplier = requiredServings > 0 
          ? (requiredServings / selectedRecipe.servings).ceil() 
          : 1;

      final meal = Meal(
        recipe: selectedRecipe,
        date: mealDate,
        type: mealType,
        totalServings: totalConsumed,
        userServings: userServingsForMeal,
        recipeMultiplier: recipeMultiplier,
        isLeftoverMeal: false,
      );

      meals[i] = meal;

      // Track usage and maintain recent recipes for diversity
      usedRecipes[selectedRecipe.id] = (usedRecipes[selectedRecipe.id] ?? 0) + 1;
      recentRecipes.add(selectedRecipe.id);
      if (recentRecipes.length > 5) recentRecipes.removeAt(0);
      
      // Track cycle: mark recipe as used in current cycle (only if cycle needed)
      if (requireFullCycle) {
        usedInCurrentCycle.add(selectedRecipe.id);
        // Reset cycle when all recipes have been used
        if (usedInCurrentCycle.length == recipes.length) {
          usedInCurrentCycle.clear();
        }
      }

      // Handle addExtraMeal: leftover meal for next day (same meal type)
      // Cook once (with x2 multiplier), serve twice: today and tomorrow (same meal type)
      if (selectedRecipe.addExtraMeal && i + 2 < numMeals && totalConsumed > 0) {
        // Next day, same meal type: lunch → lunch (i+2), dinner → dinner (i+2)
        final nextMealDate = mealDate.add(const Duration(days: 1));
        
        // Reserve slot i+2 for leftover
        pendingLeftovers[i + 2] = Meal(
          recipe: selectedRecipe,
          date: nextMealDate,
          type: mealType, // Same meal type (lunch or dinner)
          totalServings: totalConsumed, // Same total as first meal
          userServings: userServingsForMeal, // Same users with same servings
          recipeMultiplier: recipeMultiplier, // Same multiplier (already x2)
          isLeftoverMeal: true, // Mark as leftover
        );
      }
    }

    return MealPlan(
      id: '',
      startDate: startDate,
      durationDays: durationDays,
      meals: meals.whereType<Meal>().toList(), // Filter out nulls
      createdAt: DateTime.now(),
    );
  }

  /// Selects the best recipe for a meal
  /// 
  /// Prioritizes:
  /// 1. Coverage of remaining portions (or desired servings if portions exhausted)
  /// 2. Diversity (avoid recently used recipes)
  /// 3. Ingredient similarity
  /// 4. Full cycle rule: can't reuse a recipe until all recipes used once (only if meals > recipes)
  static Recipe? _selectBestRecipe({
    required List<Recipe> availableRecipes,
    required Map<String, Map<String, (int, int)>> recipeUserServingsMap,
    required List<User> users,
    required Map<String, int> usedRecipes,
    required List<String> recentRecipes,
    required MealType mealType,
    required Map<String, Map<MealType, int>> remainingPortions,
    required Map<String, Map<String, double>> similarityCache,
    required double usagePenaltyWeight,
    required double recencyPenaltyWeight,
    required double similarityPenaltyWeight,
    required double coverageBonusWeight,
    bool allPortionsExhausted = false,
    bool requireFullCycle = false,
    Set<String> usedInCurrentCycle = const {},
  }) {
    if (availableRecipes.isEmpty) return null;
    
    // Filter recipes based on full cycle rule
    // Only apply if requireFullCycle AND current cycle not complete
    List<Recipe> candidateRecipes = availableRecipes;
    if (requireFullCycle && usedInCurrentCycle.isNotEmpty) {
      final unusedRecipes = availableRecipes
          .where((r) => !usedInCurrentCycle.contains(r.id))
          .toList();
      // Only filter if there are unused recipes, otherwise allow all (cycle complete)
      if (unusedRecipes.isNotEmpty) {
        candidateRecipes = unusedRecipes;
      }
    }
    
    Recipe? bestRecipe;
    double bestScore = double.infinity;
    
    // Calculate normalization factors for scoring
    final maxTimesUsed = usedRecipes.values.fold<int>(0, (max, val) => val > max ? val : max);
    final totalRemainingPortions = remainingPortions.values
        .fold<int>(0, (sum, map) => sum + (map[mealType] ?? 0));
    
    // Calculate max remaining portions for equity normalization
    final maxUserRemaining = remainingPortions.values
        .fold<int>(0, (max, map) {
          final total = map.values.fold(0, (a, b) => a + b);
          return total > max ? total : max;
        });

    for (final recipe in candidateRecipes) {
      final servingsForRecipe = recipeUserServingsMap[recipe.id] ?? {};

      // Calculate coverage score: favor equity (users most behind) over total coverage
      double coverageScore = 0;
      
      for (final user in users) {
        final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
        final desired = mealType == MealType.lunch ? lunch : dinner;
        final remaining = remainingPortions[user.id]![mealType]!;

        if (allPortionsExhausted) {
          // When portions exhausted, score based on desired servings
          if (desired > 0) {
            coverageScore += desired.toDouble();
          }
        } else {
          // Normal mode: score based on remaining portions
          if (remaining > 0 && desired > 0) {
            final served = remaining < desired ? remaining : desired;
            // Equity weight (0-1): users with more remaining portions get higher priority
            // Formula: userRemaining / maxRemaining → 0 (no portions left) to 1 (most behind)
            final userTotalRemaining = remainingPortions[user.id]!.values.fold(0, (a, b) => a + b);
            final equityWeight = maxUserRemaining > 0 
                ? userTotalRemaining / maxUserRemaining 
                : 0.0;
            coverageScore += served * (1.0 + equityWeight); // Apply as multiplier 1→2
          }
        }
      }

      // All scores normalized to 0-1 range, then weights applied
      
      // 1. Coverage score (0-1, higher = better coverage)
      // Formula: coverageScore / totalRemaining → accounts for equity weights (1-2 multiplier)
      final normalizedCoverage = totalRemainingPortions > 0
          ? (coverageScore / (totalRemainingPortions * 2.0)).clamp(0.0, 1.0)
          : 0.0;
      final coverageComponent = -normalizedCoverage * coverageBonusWeight;

      // 2. Usage penalty (0-1, higher = more used)
      final timesUsed = usedRecipes[recipe.id] ?? 0;
      final normalizedUsage = maxTimesUsed > 0 ? (timesUsed / maxTimesUsed).clamp(0.0, 1.0) : 0.0;
      final usageComponent = normalizedUsage * usagePenaltyWeight;

      // 3. Recency penalty (0-1, 1 if in recent window)
      final normalizedRecency = recentRecipes.contains(recipe.id) ? 1.0 : 0.0;
      final recencyComponent = normalizedRecency * recencyPenaltyWeight;

      // 4. Similarity penalty (0-1, weighted average with temporal decay)
      // Recent recipes have more weight than older ones
      double normalizedSimilarity = 0;
      if (recentRecipes.isNotEmpty) {
        double weightedSimilarity = 0;
        double totalWeight = 0;
        for (int i = 0; i < recentRecipes.length; i++) {
          final recentId = recentRecipes[i];
          final similarity = similarityCache[recipe.id]?[recentId] ?? 0.0;
          // Temporal decay: more recent = higher weight (0.2 to 1.0)
          final recencyWeight = 0.2 + (0.8 * (i + 1) / recentRecipes.length);
          weightedSimilarity += similarity * recencyWeight;
          totalWeight += recencyWeight;
        }
        normalizedSimilarity = totalWeight > 0 
            ? (weightedSimilarity / totalWeight).clamp(0.0, 1.0) 
            : 0.0;
      }
      final similarityComponent = normalizedSimilarity * similarityPenaltyWeight;

      // 5. AddExtraMeal bonus (proportional to coverage gain)
      // Formula: -normalizedCoverage × 30 if addExtraMeal = true
      // Rationale: Recipes with addExtraMeal reduce cooking days by 50%
      // Coefficient 30 balances with other penalties (usage=20, similarity=30, recency=100)
      final addExtraMealComponent = recipe.addExtraMeal && normalizedCoverage > 0
          ? -normalizedCoverage * 30.0
          : 0.0;

      // Total score: lower is better (all components properly normalized)
      final totalScore = usageComponent + recencyComponent + similarityComponent + 
                        coverageComponent + addExtraMealComponent;

      if (totalScore < bestScore) {
        bestScore = totalScore;
        bestRecipe = recipe;
      }
    }

    return bestRecipe;
  }

  /// Builds a cache of ingredient similarity between all recipe pairs
  static Map<String, Map<String, double>> _buildSimilarityCache(List<Recipe> recipes) {
    final cache = <String, Map<String, double>>{};
    
    for (int i = 0; i < recipes.length; i++) {
      cache[recipes[i].id] = {};
      for (int j = 0; j < recipes.length; j++) {
        if (i != j) {
          cache[recipes[i].id]![recipes[j].id] = 
              _calculateIngredientSimilarity(recipes[i], recipes[j]);
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
    bool ignorePortions = false, // Ignore portion limits if true
  }) {
    final userServingsForMeal = <String, int>{};
    int totalConsumed = 0;

    for (final user in users) {
      final (lunch, dinner) = servingsForRecipe[user.id] ?? (0, 0);
      final desired = mealType == MealType.lunch ? lunch : dinner;
      final remaining = remainingPortions[user.id]![mealType]!;

      int servingCount;
      // Check if THIS user has exhausted their portions OR if global ignorePortions is true
      if (ignorePortions || remaining == 0) {
        // When portions exhausted for this user, serve desired amount (allows recipe reuse)
        servingCount = desired;
      } else {
        // Normal mode: serve minimum of desired and remaining
        servingCount = (desired > 0 && remaining > 0) 
            ? (desired < remaining ? desired : remaining) 
            : 0;
        
        // Consume portions only in normal mode
        if (servingCount > 0) {
          remainingPortions[user.id]![mealType] = remaining - servingCount;
        }
      }
      
      if (servingCount > 0) {
        userServingsForMeal[user.id] = servingCount;
        totalConsumed += servingCount;
      }
    }

    return (userServingsForMeal, totalConsumed);
  }

  /// Common base ingredients to exclude from similarity calculation
  static const _commonIngredients = {
    'sel', 'salt', 'poivre', 'pepper', 'huile', 'oil', 'eau', 'water',
    'beurre', 'butter', 'sucre', 'sugar', 'farine', 'flour',
  };

  /// Calculates ingredient similarity between two recipes (0-1)
  /// Excludes common base ingredients for more meaningful comparison
  static double _calculateIngredientSimilarity(Recipe r1, Recipe r2) {
    if (r1.ingredients.isEmpty || r2.ingredients.isEmpty) return 0;

    // Filter out common ingredients
    final ing1Names = r1.ingredients
        .map((i) => i.ingredient.name.toLowerCase())
        .where((name) => !_commonIngredients.contains(name))
        .toSet();
    final ing2Names = r2.ingredients
        .map((i) => i.ingredient.name.toLowerCase())
        .where((name) => !_commonIngredients.contains(name))
        .toSet();

    if (ing1Names.isEmpty || ing2Names.isEmpty) return 0;

    final intersection = ing1Names.intersection(ing2Names).length;
    final union = ing1Names.union(ing2Names).length;

    if (union == 0) return 0;
    return intersection / union;
  }
}