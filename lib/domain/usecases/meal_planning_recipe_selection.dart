part of 'meal_planning_service.dart';

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
Recipe? _selectBestRecipe({
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
  double pantryBonusWeight = 15.0,
  Set<String> urgentPantryNames = const {},
  int slotsRemaining = 1,
  double wastePenaltyWeight = 0.0,
  int maxLeftoverSlots = 999,
  bool strictNoWaste = false,
  int minDaysAgoThreshold = 0,
}) {
  if (availableRecipes.isEmpty) return null;

  // Si aucun slot libre suivant, restreindre aux recettes sans restes
  // (portions cuisinées = portions consommées exactement).
  // On filtre en se basant sur candidateTotalConsumed calculé juste après,
  // donc on fait un premier passage pour identifier les recettes éligibles.
  List<Recipe> recipesToScore = availableRecipes;

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

  // Exclusion dure : recettes utilisées trop récemment (historique ou plan en cours).
  // Évite que le bonus frigo/placard écrase la pénalité de récence pour des recettes
  // mangées la veille ou avant-veille. Fallback : si toutes les recettes sont exclues
  // (catalogue trop petit), on ignore le seuil pour ne pas laisser de slot vide.
  if (minDaysAgoThreshold > 0 && recentRecipeDaysAgo != null) {
    final filtered = availableRecipes
        .where((r) => (recentRecipeDaysAgo[r.id] ?? 999) >= minDaysAgoThreshold)
        .toList();
    if (filtered.isNotEmpty) {
      recipesToScore = filtered;
    }
    // sinon fallback : recipesToScore reste = availableRecipes
  }

  // Filtrer selon le nombre de slots consécutifs libres disponibles pour les restes.
  // maxLeftoverSlots=0 → préférence pour les recettes sans restes.
  // maxLeftoverSlots=n → recettes dont les restes tiennent en n jours au plus.
  // Fallback : si le filtre élimine toutes les recettes (ex. aucune recette avec
  // exactement les bonnes portions), on autorise quand même les restes plutôt que
  // de laisser le slot vide (les restes seront gaspillés mais c'est préférable à
  // un slot non rempli qui garde l'ancienne recette).
  if (maxLeftoverSlots < 999) {
    final filtered = recipesToScore.where((r) {
      final consumed = candidateTotalConsumed[r.id] ?? 0;
      if (consumed <= 0) return false;
      final multiplier = (consumed / r.servings).ceil();
      final cooked = r.servings * multiplier;
      final leftover = cooked - consumed;
      if (leftover <= 0) return true; // pas de restes → toujours OK
      // Nombre de jours de restes estimé (même consommation par jour)
      final leftoverDays = (leftover / consumed).ceil();
      return leftoverDays <= maxLeftoverSlots;
    }).toList();
    if (filtered.isNotEmpty) {
      recipesToScore = filtered;
    } else if (!strictNoWaste) {
      // Fallback : si le filtre est trop strict, on accepte toutes les recettes
      // pour éviter un slot vide (les restes excédentaires seront gaspillés).
      recipesToScore = availableRecipes;
    } else {
      // strictNoWaste && filtered.isEmpty : aucune recette sans gaspillage dispo.
      // → on retourne null (le slot ne sera pas rempli plutôt que de gaspiller).
      recipesToScore = [];
    }
  }

  final candidates = <Recipe>[];
  double bestScore = double.infinity;
  const epsilon = 1e-6;

  // Contrainte dure : si des ingrédients urgents sont encore disponibles ET qu'au
  // moins une recette du pool DE SCORING les utilise, on exclut les recettes qui
  // n'en utilisent aucun.
  // IMPORTANT : on vérifie recipesToScore (et non availableRecipes) pour éviter
  // le cas où la seule recette urgente a été filtrée (ex : produit des restes
  // avec maxLeftoverSlots=0) → hasUrgentConstraint=true mais aucune recette
  // scorable ne satisfait la contrainte → candidates vide → retour null incorrect.
  final bool hasUrgentConstraint = urgentPantryNames.isNotEmpty &&
      urgentPantryNames.any((name) {
        final entry = pantryRemaining[name];
        return entry != null && entry.$1 > 0.0;
      }) &&
      recipesToScore.any((r) => r.ingredients.any((ing) {
        final n = ing.ingredient.name.toLowerCase().trim();
        return urgentPantryNames.contains(n) &&
            (pantryRemaining[n]?.$1 ?? 0.0) > 0.0;
      }));

  for (final recipe in recipesToScore) {
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
    // Pénalité absolue : croît linéairement avec le nombre d'utilisations
    // (contrairement à une normalisation qui plafonnait toutes les recettes
    // au même niveau dès qu'elles atteignaient le maximum).
    final usageComponent = timesUsed.toDouble() * usagePenaltyWeight;
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
    // --- Contrainte mealTime : recette réservée midi ou soir uniquement ---
    if (mealType == MealType.lunch && recipe.mealTime == MealTime.dinnerOnly) continue;
    if (mealType == MealType.dinner && recipe.mealTime == MealTime.lunchOnly) continue;
    // --- Contrainte dure ingrédients urgents ---
    // Si des ingrédients urgents sont disponibles et que cette recette n'en
    // utilise aucun, on l'exclut du calcul pour ce slot.
    if (hasUrgentConstraint) {
      final usesUrgent = recipe.ingredients.any((ing) {
        final n = ing.ingredient.name.toLowerCase().trim();
        return urgentPantryNames.contains(n) &&
            (pantryRemaining[n]?.$1 ?? 0.0) > 0.0;
      });
      if (!usesUrgent) continue;
    }
    // --- Bonus frigo/placard avec urgence dynamique ---
    // Ingrédients normaux : urgencyFactor dynamique 1.0 → 3.0.
    // Ingrédients urgents (marqués par l'utilisateur) : bonus fixe 8× pour
    // garantir leur consommation prioritaire même sans contrainte dure.
    double pantryComponent = 0.0;
    if (pantryRemaining.isNotEmpty && recipe.ingredients.isNotEmpty) {
      int normalMatchCount = 0;
      int urgentMatchCount = 0;
      int maxUsesNeeded = 0;
      for (final ingredient in recipe.ingredients) {
        final name = ingredient.ingredient.name.toLowerCase().trim();
        final pantryEntry = pantryRemaining[name];
        if (pantryEntry != null) {
          final (pantryQty, pantryBaseUnit) = pantryEntry;
          if (pantryBaseUnit == _baseUnit(ingredient.unit) && pantryQty > 0.0) {
            if (urgentPantryNames.contains(name)) {
              urgentMatchCount++;
            } else {
              normalMatchCount++;
            }
            final normalizedIngQty = _toNormalized(ingredient.quantity, ingredient.unit);
            if (normalizedIngQty > 0) {
              final usesNeeded = (pantryQty / normalizedIngQty).ceil();
              if (usesNeeded > maxUsesNeeded) maxUsesNeeded = usesNeeded;
            }
          }
        }
      }
      if (normalMatchCount + urgentMatchCount > 0) {
        // urgencyFactor dynamique pour les ingrédients normaux
        double urgencyFactor = 1.0;
        if (slotsRemaining > 0 && maxUsesNeeded > 0) {
          final urgency = (maxUsesNeeded / slotsRemaining).clamp(0.0, 2.0);
          urgencyFactor = 1.0 + urgency * 2.0;
        }
        final normalBonus = normalMatchCount > 0
            ? -normalMatchCount * pantryBonusWeight * urgencyFactor
            : 0.0;
        // Bonus urgent fixe (8×) : surpasse toutes les autres pénalités
        const urgentBonusMultiplier = 8.0;
        final urgentBonus = urgentMatchCount > 0
            ? -urgentMatchCount * pantryBonusWeight * urgentBonusMultiplier
            : 0.0;
        pantryComponent = normalBonus + urgentBonus;
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
    // Diagnostique pourquoi aucun candidat n'a été retenu.
    final totalRemainingCheck = remainingPortions.values
        .fold<int>(0, (s, m) => s + (m[mealType] ?? 0));
    final allZeroConsumed = recipesToScore.every(
        (r) => (candidateTotalConsumed[r.id] ?? 0) == 0);
    // ignore: avoid_print
    print('[ALGO] _selectBestRecipe → null. mealType=$mealType '
        'recipesToScore=${recipesToScore.length} '
        'hasUrgentConstraint=$hasUrgentConstraint '
        'totalRemaining=$totalRemainingCheck '
        'allZeroConsumed=$allZeroConsumed '
        'maxLeftoverSlots=$maxLeftoverSlots');
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
