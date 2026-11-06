import '../entities/recipe.dart';
import '../entities/user_recipe_serving.dart';
import '../entities/user.dart';
import '../entities/meal_plan.dart';
import 'dart:math';
import '../entities/recipe_ingredient.dart';
import '../../core/constants/unit.dart';
import '../../core/constants/meal_time.dart';

part 'meal_planning_recipe_selection.dart';
part 'meal_planning_helpers.dart';

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
  /// [similarityPenaltyWeight]: penalty for ingredient similarity (default: 60)
  /// [coverageBonusWeight]: bonus multiplier for portion coverage (default: 2)
  static Future<MealPlan> generateMealPlan({
    required List<Recipe> recipes,
    required List<UserRecipeServing> servings,
    required List<User> users,
    required DateTime startDate,
    required int durationDays,
    double usagePenaltyWeight = 20.0,
    double recencyPenaltyWeight = 100.0,
    double similarityPenaltyWeight = 60.0,
    double coverageBonusWeight = 2.0,
    double endOfPlanCoverageBoost = 1.5,
    double endOfPlanThresholdRatio = 0.2,
    bool useMaxPossibleCoverageNormalization = false,
    double recencyDecayFactor = 0.9,
    bool useAbsoluteCoverageBonus = false,
    List<Meal>? recentMeals,
    List<Meal>? userSelectedMeals,
    List<RecipeIngredient> pantryItems = const [],
    Set<String> urgentPantryIngredientNames = const {},
    List<String> selectedCategories = const [],
    DateTime? referenceDate,
    double wastePenaltyWeight = 0.0,
    List<String> leftoverUserOrder = const [],
    bool strictNoWaste = false,
    bool ignoreHistoryLeftovers = false,
    int minDaysBetweenRepeat = 4,
    void Function(int filled, int total)? onProgress,
  }) async {
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
    // Noms normalisés (minuscule) des ingrédients urgents transmis au moteur de scoring.
    final urgentPantrySet = urgentPantryIngredientNames
        .map((n) => n.toLowerCase().trim())
        .toSet();
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
    if (!ignoreHistoryLeftovers && recentMeals != null && recentMeals.isNotEmpty) {
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
      if (onProgress != null) {
        onProgress(i, numMeals);
        await Future.delayed(Duration.zero);
      }
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
      if (_handleUserSelectedSlot(i, meals, usedRecipes, users, recipeUserServingsMap, remainingPortions, pantryRemaining)) { continue; }
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

      // Compter les slots CONSÉCUTIFS libres suivants du même type.
      // On vérifie à la fois meals[] (repas verrouillés/générés) ET pendingLeftovers
      // (restes de repas verrouillés pas encore injectés dans meals[]).
      // On s'arrête au premier slot occupé : les restes ne sautent pas les jours pris.
      int freeFollowingSlots = 0;
      for (int fs = i + 2; fs < numMeals; fs += 2) {
        if (meals[fs] != null) break; // repas verrouillé ou généré → arrêt
        if (pendingLeftovers.containsKey(fs)) break; // leftover prévu → arrêt
        freeFollowingSlots++;
      }
      final maxLeftoverSlots = freeFollowingSlots;
      // Appliquer strictNoWaste dès que des slots suivants existent (pas fin de plan).
      // Le filtre maxLeftoverSlots dans _selectBestRecipe gère déjà le comptage
      // précis (exclut les recettes dont leftoverDays > maxLeftoverSlots). Ce flag
      // empêche uniquement le fallback "all-recipes" quand filtered.isEmpty : si
      // toutes les recettes dépassent les slots disponibles, on retourne null
      // (échec waste-constrained) plutôt que de proposer une recette gaspilleuse.
      final effectiveStrictNoWaste = strictNoWaste && (i + 2 < numMeals);

      // Lookahead : avant de sélectionner le déjeuner, anticiper la meilleure
      // recette du dîner et l'injecter temporairement dans le contexte de récence.
      // Le composant de similarité pénalisera ainsi les candidats au déjeuner trop
      // proches du dîner prévu (ex : deux recettes avec pâtes le même jour).
      Recipe? peekedDinner;
      bool peekedDinnerAdded = false;
      if (mealType == MealType.lunch && i + 1 < numMeals && meals[i + 1] == null) {
        peekedDinner = _selectBestRecipe(
          availableRecipes: recipes,
          recipeUserServingsMap: recipeUserServingsMap,
          users: users,
          usedRecipes: usedRecipes,
          mealType: MealType.dinner,
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
          urgentPantryNames: urgentPantrySet,
          slotsRemaining: numMeals - i - 1,
          wastePenaltyWeight: wastePenaltyWeight,
          maxLeftoverSlots: maxLeftoverSlots,
          strictNoWaste: effectiveStrictNoWaste,
          minDaysAgoThreshold: minDaysBetweenRepeat,
        );
        if (peekedDinner != null && !recentRecipeDaysAgo.containsKey(peekedDinner.id)) {
          recentRecipeDaysAgo[peekedDinner.id] = 0;
          peekedDinnerAdded = true;
        }
      }
      // Si le dîner prévu couvre des items urgents, on relâche la contrainte dure
      // urgente pour le déjeuner en simulant leur consommation (copie locale du
      // placard). Ainsi le déjeuner n'est plus forcé de choisir la même famille
      // d'ingrédients que le dîner (ex : éviter deux repas aux pâtes le même jour).
      var pantryForLunchSelection = pantryRemaining;
      if (peekedDinner != null && urgentPantrySet.isNotEmpty) {
        final coveredUrgentNames = <String>{};
        for (final ing in peekedDinner.ingredients) {
          final name = ing.ingredient.name.toLowerCase().trim();
          if (urgentPantrySet.contains(name) && (pantryRemaining[name]?.$1 ?? 0.0) > 0.0) {
            coveredUrgentNames.add(name);
          }
        }
        if (coveredUrgentNames.isNotEmpty) {
          pantryForLunchSelection = Map.of(pantryRemaining);
          for (final name in coveredUrgentNames) {
            final entry = pantryForLunchSelection[name]!;
            pantryForLunchSelection[name] = (0.0, entry.$2);
          }
        }
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
        pantryRemaining: pantryForLunchSelection,
        urgentPantryNames: urgentPantrySet,
        slotsRemaining: numMeals - i,
        wastePenaltyWeight: wastePenaltyWeight,
        maxLeftoverSlots: maxLeftoverSlots,
        strictNoWaste: effectiveStrictNoWaste,
        minDaysAgoThreshold: minDaysBetweenRepeat,
      ); // wastePenaltyWeight non passé par défaut (les restes du plan complet sont utiles)
      // Retire l'entrée temporaire du lookahead pour ne pas biaiser le dîner
      if (peekedDinnerAdded) recentRecipeDaysAgo.remove(peekedDinner!.id);
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
          // Si le slot suivant est déjà occupé (repas généré ou verrouillé), on arrête
          // la cascade : les restes ne sautent pas les jours occupés.
          if (meals[nextSlot] != null) { break; }
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
          // Slot entièrement occupé par d'autres leftovers → passer au suivant sans break
          if (leftoverTotal == 0) { nextSlot += 2; continue; }
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
    if (onProgress != null) onProgress(numMeals, numMeals);

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

}