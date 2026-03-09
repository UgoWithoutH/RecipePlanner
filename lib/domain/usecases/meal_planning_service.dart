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
    double endOfPlanCoverageBoost = 1.5,
    double endOfPlanThresholdRatio = 0.2,
    bool useMaxPossibleCoverageNormalization = false,
    double recencyDecayFactor = 0.9,
    bool useAbsoluteCoverageBonus = false,
    List<Meal>? recentMeals,
    List<Meal>? userSelectedMeals,
    List<RecipeIngredient> pantryItems = const [],
    List<String> selectedCategories = const [],
    DateTime? referenceDate,
    double wastePenaltyWeight = 0.0,
    List<String> leftoverUserOrder = const [],
  }) {
    if (recipes.isEmpty || users.isEmpty) {
      throw Exception('Recipes and users are required');
    }

    final numMeals = durationDays * 2; // lunch + dinner per day
    final meals = List<Meal?>.filled(numMeals, null); // Pre-allocate slots
    final pendingLeftovers = <int, List<Meal>>{}; // Track leftovers to insert (multiple per slot)
    final leftoverMealsList = <Meal>[]; // Accumulates all leftover meals for the final plan

    // Ordre round-robin pour l'attribution équitable des restes.
    // On part de l'ordre sauvegardé ; les nouveaux utilisateurs sont ajoutés à la fin.
    final currentUserOrder = <String>[
      ...leftoverUserOrder.where((uid) => users.any((u) => u.id == uid)),
      ...users.map((u) => u.id).where((uid) => !leftoverUserOrder.contains(uid)),
    ];

    // Compteur de restes reçus par utilisateur (historique + plan en cours).
    // Critère primaire pour équilibrer l'attribution des restes entre utilisateurs.
    final leftoverCountPerUser = <String, int>{
      for (final user in users) user.id: 0,
    };
    if (recentMeals != null) {
      for (final meal in recentMeals) {
        if (meal.isLeftoverMeal) {
          for (final uid in meal.userServings.keys) {
            leftoverCountPerUser[uid] = (leftoverCountPerUser[uid] ?? 0) + 1;
          }
        }
      }
    }

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
    // referenceDate allows computing distances relative to a pivot (e.g. the shuffled meal)
    // instead of now — meals closer to the pivot are penalised more, symmetrically
    // for both past AND future slots.
    final now = DateTime.now();
    final pivot = referenceDate ?? now;
    if (recentMeals != null && recentMeals.isNotEmpty) {
      for (final meal in recentMeals) {
        final daysAgo = pivot.difference(meal.date).inDays.abs();
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

    // --- GESTION DES LEFTOVERS HISTORIQUES (calcul automatique des restes du J-1) ---
    if (recentMeals != null && recentMeals.isNotEmpty) {
      final expectedDate = startDate.subtract(const Duration(days: 1));
      // Filter J-1 meals that are NOT themselves leftovers (avoid double-cascading)
      final mealsJ1 = recentMeals.where((m) =>
          m.date.year == expectedDate.year &&
          m.date.month == expectedDate.month &&
          m.date.day == expectedDate.day &&
          !m.isLeftoverMeal
      ).toList();
      for (final meal in mealsJ1) {
        // Automatic leftover detection: cooked vs consumed
        final cookedJ1 = meal.recipe.servings * meal.recipeMultiplier;
        var remainingLeftJ1 = cookedJ1 - meal.totalServings;
        if (remainingLeftJ1 <= 0) continue;

        // Soustraire les portions déjà attribuées comme restes dans le plan
        // existant (passé via recentMeals). Sans ce check, lorsque l'on
        // re-génère un slot en mode shuffle, l'algo voit des portions libres
        // et les réattribue à quelqu'un d'autre, alors qu'elles sont déjà
        // consommées par un leftover existant.
        final alreadyInPlan = recentMeals.where((m) =>
            m.date.year == startDate.year &&
            m.date.month == startDate.month &&
            m.date.day == startDate.day &&
            m.type == meal.type &&
            m.recipe.id == meal.recipe.id &&
            m.isLeftoverMeal).toList();
        final alreadyAllocatedPortions =
            alreadyInPlan.fold(0, (s, m) => s + m.totalServings);
        remainingLeftJ1 -= alreadyAllocatedPortions;
        if (remainingLeftJ1 <= 0) continue;

        final alreadyAssignedFromPlan =
            alreadyInPlan.expand((m) => m.userServings.keys).toSet();

        // Determine which users can eat from leftover (greedy, prioritise users with more remaining portions)
        // Slot calculé en amont pour vérifier les doublons
        final slot = (meal.type == MealType.lunch) ? 0 : 1;
        final alreadyAssignedJ1 = {
          ...pendingLeftovers[slot]
                  ?.expand((m) => m.userServings.keys).toSet() ??
              <String>{},
          ...alreadyAssignedFromPlan,
        };
        final leftoverUserServingsJ1 = <String, int>{};
        int leftoverTotalJ1 = 0;
        final sortedEntriesJ1 = meal.userServings.entries.toList()
          ..sort((a, b) {
            // Primaire : moins de restes reçus (historique + plan) = priorité
            final cmpLO = (leftoverCountPerUser[a.key] ?? 0)
                .compareTo(leftoverCountPerUser[b.key] ?? 0);
            if (cmpLO != 0) return cmpLO;
            // Secondaire : round-robin
            final aIdx = currentUserOrder.indexOf(a.key);
            final bIdx = currentUserOrder.indexOf(b.key);
            return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
          });
        final eligibleEntriesJ1 = sortedEntriesJ1
            .where((e) => !alreadyAssignedJ1.contains(e.key))
            .toList();
        for (int idx = 0; idx < eligibleEntriesJ1.length; idx++) {
          if (remainingLeftJ1 <= 0) break;
          final entry = eligibleEntriesJ1[idx];
          final userId = entry.key;
          final portionsNeeded = entry.value;
          final usersLeft = eligibleEntriesJ1.length - idx;
          final fairShare = max(1, remainingLeftJ1 ~/ usersLeft);
          final toAssign = min(portionsNeeded, min(fairShare, remainingLeftJ1));
          if (toAssign > 0) {
            leftoverUserServingsJ1[userId] = toAssign;
            leftoverTotalJ1 += toAssign;
            remainingLeftJ1 -= toAssign;
          }
        }
        if (leftoverTotalJ1 == 0) continue;
        // Rotation : les utilisateurs assignés passent en fin d'ordre + compteur de restes
        for (final uid in leftoverUserServingsJ1.keys) {
          leftoverCountPerUser[uid] = (leftoverCountPerUser[uid] ?? 0) + 1;
          currentUserOrder.remove(uid);
          currentUserOrder.add(uid);
        }
        if (slot < meals.length) {
          if (meals[slot] != null) continue; // blocked by user-selected
          pendingLeftovers.putIfAbsent(slot, () => []).add(Meal(
            recipe: meal.recipe,
            date: startDate,
            type: meal.type,
            totalServings: leftoverTotalJ1,
            userServings: leftoverUserServingsJ1,
            recipeMultiplier: 1,
            isLeftoverMeal: true,
          ));
          recentRecipeDaysAgo[meal.recipe.id] = 0;
        }
      }
    }

    for (int i = 0; i < numMeals; i++) {
      // 1. Process pending leftover meals for this slot (may cover some or all users)
      // On track les users déjà couverts par un leftover pour ce slot afin
      // de ne pas leur générer un repas normal en plus.
      final usersWithLeftoverThisSlot = <String>{};
      if (pendingLeftovers.containsKey(i)) {
        for (final leftoverMeal in pendingLeftovers[i]!) {
          final mealTypeForLO = leftoverMeal.type;
          // Only inject leftover for users who still have portions remaining
          final filteredServings = <String, int>{};
          for (final entry in leftoverMeal.userServings.entries) {
            final uid = entry.key;
            final portions = entry.value;
            if ((remainingPortions[uid]?[mealTypeForLO] ?? 0) <= 0) continue;
            filteredServings[uid] = portions;
            usersWithLeftoverThisSlot.add(uid);
            remainingPortions[uid]![mealTypeForLO] =
                max(0, (remainingPortions[uid]![mealTypeForLO] ?? 0) - portions);
          }
          if (filteredServings.isNotEmpty) {
            leftoverMealsList.add(leftoverMeal.copyWith(userServings: filteredServings));
            recentRecipeDaysAgo[leftoverMeal.recipe.id] = 0;
          }
        }
        pendingLeftovers.remove(i);
      }
      // 2. Gestion des userSelectedMeals
      if (_handleUserSelectedSlot(i, meals, usedRecipes, users, recipeUserServingsMap, remainingPortions)) { continue; }
      // 3. Skip slots already filled by user-selected
      if (meals[i] != null) { continue; }
      // 4. Génération normale du slot — on exclut les users déjà couverts par un leftover
      final mealDate = startDate.add(Duration(days: i ~/ 2));
      final mealType = i % 2 == 0 ? MealType.lunch : MealType.dinner;
      // Ne compter que les users qui n'ont pas déjà un leftover pour ce slot
      final totalRemainingPortions = remainingPortions.entries
          .where((e) => !usersWithLeftoverThisSlot.contains(e.key))
          .fold<int>(0, (sum, e) => sum + (e.value[mealType] ?? 0));
      if (totalRemainingPortions == 0) {
        // No more portions needed for this meal type — skip but keep going for
        // other days / other types instead of stopping the whole plan.
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
        slotsRemaining: numMeals - i,
        wastePenaltyWeight: wastePenaltyWeight,
      ); // wastePenaltyWeight non passé par défaut (les restes du plan complet sont utiles)
      if (selectedRecipe == null) {
        meals[i] = null;
        continue;
      }
      final servingsForRecipe = recipeUserServingsMap[selectedRecipe.id] ?? {};
      final (userServingsForMeal, totalConsumed) = _consumePortions(
        users: users,
        servingsForRecipe: servingsForRecipe,
        mealType: mealType,
        remainingPortions: remainingPortions,
        excludedUsers: usersWithLeftoverThisSlot,
      );
      if (totalConsumed == 0) {
        meals[i] = null;
        continue;
      }
      final recipeMultiplier = totalConsumed > 0
          ? (totalConsumed / selectedRecipe.servings).ceil()
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
      // Auto leftover calculation: propagate remaining cooked portions across future days
      if (totalConsumed > 0) {
        final cookedServings = selectedRecipe.servings * recipeMultiplier;
        var remainingLeftover = cookedServings - totalConsumed;
        int nextSlot = i + 2;
        while (remainingLeftover > 0 && nextSlot < numMeals) {
          final nextMealType = nextSlot % 2 == 0 ? MealType.lunch : MealType.dinner;
          final nextMealDate = startDate.add(Duration(days: nextSlot ~/ 2));
          final leftoverUserServings = <String, int>{};
          int leftoverTotal = 0;
          // On considère TOUS les utilisateurs ayant des portions configurées
          // pour cette recette (pas seulement ceux du repas original) afin
          // d'alterner équitablement les restes entre tous les utilisateurs.
          final servingsForRecipeLO = recipeUserServingsMap[selectedRecipe.id] ?? {};
          final sortedEntriesLO = users
              .map((u) {
                final (lunch, dinner) = servingsForRecipeLO[u.id] ?? (0, 0);
                final portions = nextMealType == MealType.lunch ? lunch : dinner;
                return MapEntry(u.id, portions);
              })
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) {
              // Primaire : moins de restes reçus (historique + plan) = priorité
              final cmpLO = (leftoverCountPerUser[a.key] ?? 0)
                  .compareTo(leftoverCountPerUser[b.key] ?? 0);
              if (cmpLO != 0) return cmpLO;
              // Secondaire : utilisateurs absents du repas original prioritaires
              // (rétablissement de l'équité quand un slot original était solo)
              final aInOriginal = userServingsForMeal.containsKey(a.key) ? 1 : 0;
              final bInOriginal = userServingsForMeal.containsKey(b.key) ? 1 : 0;
              if (aInOriginal != bInOriginal) return aInOriginal.compareTo(bInOriginal);
              // Tertiaire : round-robin
              final aIdx = currentUserOrder.indexOf(a.key);
              final bIdx = currentUserOrder.indexOf(b.key);
              return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
            });
          // Users déjà assignés à un leftover pour ce slot (depuis une autre recette)
          final alreadyAssignedLO = pendingLeftovers[nextSlot]
              ?.expand((m) => m.userServings.keys).toSet() ?? <String>{};
          final eligibleEntriesLO = sortedEntriesLO
              .where((e) => !alreadyAssignedLO.contains(e.key))
              .toList();
          // Calcule un quota de portions par slot pour répartir les restes
          // sur plusieurs jours plutôt que de tout donner au premier slot.
          // Ex : 3 restes, 2 users × 1 portion → quota=1 par slot → J+1=user seul, J+2=les deux.
          final totalEligiblePortionsLO =
              eligibleEntriesLO.fold(0, (s, e) => s + e.value);
          final estimatedSlotsLO = totalEligiblePortionsLO > 0
              ? (remainingLeftover / totalEligiblePortionsLO).ceil().clamp(1, 9999)
              : 1;
          final perSlotQuotaLO = remainingLeftover ~/ estimatedSlotsLO;
          int perSlotTotalLO = 0;
          for (int idx = 0; idx < eligibleEntriesLO.length; idx++) {
            if (remainingLeftover <= 0) break;
            if (perSlotTotalLO >= perSlotQuotaLO) break; // quota atteint : reporter au slot suivant
            final entry = eligibleEntriesLO[idx];
            final userId = entry.key;
            final portionsNeeded = entry.value;
            final usersLeft = eligibleEntriesLO.length - idx;
            final fairShare = max(1, remainingLeftover ~/ usersLeft);
            final toAssign = min(portionsNeeded, min(fairShare, remainingLeftover));
            if (toAssign > 0) {
              leftoverUserServings[userId] = toAssign;
              leftoverTotal += toAssign;
              remainingLeftover -= toAssign;
              perSlotTotalLO += toAssign;
            }
          }
          if (leftoverTotal == 0) break;
          // Rotation : les utilisateurs assignés passent en fin d'ordre + compteur de restes
          for (final uid in leftoverUserServings.keys) {
            leftoverCountPerUser[uid] = (leftoverCountPerUser[uid] ?? 0) + 1;
            currentUserOrder.remove(uid);
            currentUserOrder.add(uid);
          }
          pendingLeftovers.putIfAbsent(nextSlot, () => []).add(Meal(
            recipe: selectedRecipe,
            date: nextMealDate,
            type: nextMealType,
            totalServings: leftoverTotal,
            userServings: leftoverUserServings,
            recipeMultiplier: 1,
            isLeftoverMeal: true,
            userSelected: false,
          ));
          nextSlot += 2;
        }
      }
    }

    final finalMeals = [
      ...meals.whereType<Meal>(),
      ...leftoverMealsList,
    ];

    return MealPlan(
      id: '',
      startDate: startDate,
      durationDays: durationDays,
      meals: finalMeals,
      createdAt: DateTime.now(),
      pantryItems: pantryItems,
      selectedCategories: selectedCategories,
      leftoverUserOrder: currentUserOrder,
    );
  }
  /// Gère l'injection des userSelectedMeals dans le plan
  static void _handleUserSelectedMeals({
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
          // Auto leftover for user-selected meals
          final cookedUS = meal.recipe.servings * meal.recipeMultiplier;
          var remainingLeftUS = cookedUS - meal.totalServings;
          int nextSlotUS = slot + 2;
          while (remainingLeftUS > 0 && nextSlotUS < numMeals) {
            final nextDateUS = startDate.add(Duration(days: nextSlotUS ~/ 2));
            if (!nextDateUS.isBefore(startDate) &&
                !nextDateUS.isAfter(startDate.add(Duration(days: durationDays - 1)))) {
              final leftoverUserServingsUS = <String, int>{};
              int leftoverTotalUS = 0;
              final shuffledUSentries = meal.userServings.entries.toList()..shuffle();
              for (int idx = 0; idx < shuffledUSentries.length; idx++) {
                if (remainingLeftUS <= 0) break;
                final entry = shuffledUSentries[idx];
                final userId = entry.key;
                final portionsNeeded = entry.value;
                final usersLeftUS = shuffledUSentries.length - idx;
                final fairShareUS = max(1, remainingLeftUS ~/ usersLeftUS);
                final toAssignUS = min(portionsNeeded, min(fairShareUS, remainingLeftUS));
                if (toAssignUS > 0) {
                  leftoverUserServingsUS[userId] = toAssignUS;
                  leftoverTotalUS += toAssignUS;
                  remainingLeftUS -= toAssignUS;
                }
              }
              if (leftoverTotalUS == 0) break;
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

  /// Consomme les portions pour un slot généré normalement
  static (Map<String, int>, int) _consumePortions({
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
    int slotsRemaining = 1,
    double wastePenaltyWeight = 0.0,
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
      // --- Coverage ---
      final coverageScore = totalConsumed.toDouble();
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
      // --- Pénalité de gaspillage : préfère les recettes dont les portions cuisinées
      // correspondent au plus près aux portions consommées (recipeMultiplier minimal).
      // wasteRatio = 0 → recette parfaite, wasteRatio = 1 → tout gaspillé.
      double wasteComponent = 0.0;
      if (wastePenaltyWeight > 0.0 && totalConsumed > 0) {
        final recipeMultiplier = (totalConsumed / recipe.servings).ceil();
        final cookedServings = recipe.servings * recipeMultiplier;
        final wasteRatio = cookedServings > 0
            ? (cookedServings - totalConsumed) / cookedServings
            : 0.0;
        wasteComponent = wasteRatio.clamp(0.0, 1.0) * wastePenaltyWeight;
      }
      final totalScore = usageComponent + recencyComponent + similarityComponent +
          coverageComponent + cyclePenalty + pantryComponent + wasteComponent;
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