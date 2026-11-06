// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerLeftovers on _PlannerPageState {
  /// Affiche un snackbar orange si des repas produisent des restes non injectés
  /// (créneau du lendemain occupé ou fin de plan).
  void _showWastedLeftoversSnackbar(MealPlan plan) {
    if (!mounted) return;
    final wastedLeftovers = <String>[];
    for (final m in plan.meals) {
      if (m.isLeftoverMeal) continue;
      final cooked = m.recipe.servings * m.recipeMultiplier;
      final leftoverPortions = cooked - m.totalServings;
      if (leftoverPortions <= 0) continue;

      final sourceDay = DateTime(m.date.year, m.date.month, m.date.day);

      // Trouver la prochaine occurrence FRAÎCHE (non-reste) de la même recette+créneau
      // après le jour source. Les restes au-delà ne comptent pas pour cette cuisson.
      DateTime? nextFreshDay;
      for (final other in plan.meals) {
        if (other.isLeftoverMeal) continue;
        if (other.recipe.id != m.recipe.id || other.type != m.type) continue;
        final otherDay = DateTime(other.date.year, other.date.month, other.date.day);
        if (otherDay.isAfter(sourceDay)) {
          if (nextFreshDay == null || otherDay.isBefore(nextFreshDay)) {
            nextFreshDay = otherDay;
          }
        }
      }

      // Compter tous les restes de cette recette+créneau entre sourceDay (exclu)
      // et nextFreshDay (exclu), en autorisant les restes qui sautent un jour
      // (slot occupé par un autre reste ce jour-là).
      int injectedPortions = 0;
      for (final leftover in plan.meals) {
        if (!leftover.isLeftoverMeal) continue;
        if (leftover.recipe.id != m.recipe.id || leftover.type != m.type) continue;
        final leftoverDay = DateTime(leftover.date.year, leftover.date.month, leftover.date.day);
        if (!leftoverDay.isAfter(sourceDay)) continue;
        if (nextFreshDay != null && !leftoverDay.isBefore(nextFreshDay)) continue;
        injectedPortions += leftover.totalServings;
      }

      if (kDebugMode) {
        debugPrint('[WASTED] ${m.recipe.title} ${m.date.day}/${m.date.month} ${m.type.name}'
            ' cooked=$cooked consumed=${m.totalServings} leftover=$leftoverPortions'
            ' injected=$injectedPortions nextFresh=${nextFreshDay != null ? '${nextFreshDay.day}/${nextFreshDay.month}' : 'none'}');
      }

      final wasted = leftoverPortions - injectedPortions;
      if (wasted <= 0) continue;
      final typeLabel = m.type == MealType.lunch ? 'midi' : 'soir';
      wastedLeftovers.add(
        '${m.recipe.title} (${m.date.day}/${m.date.month} $typeLabel)'
        ' — $wasted portion${wasted > 1 ? 's' : ''}'
        ' non utilisée${wasted > 1 ? 's' : ''}',
      );
    }
    if (wastedLeftovers.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.orange[800],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Portions non utilisées faute de créneau libre :',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            )),
          ]),
          const SizedBox(height: 4),
          ...wastedLeftovers.map((label) => Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text('• $label', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
          )),
        ],
      ),
    ));
  }

  /// Remplit les slots vides apparus après un multi-shuffle
  /// (ex : restes supprimés dont le nouveau repas ne produit pas de restes).
  /// Utilise l'algorithme de planification pour choisir la meilleure recette.
  /// [skipSlotKeys] : slots qui étaient originalement des restes — on les ignore
  /// pour ne pas injecter un repas frais là où un reste devrait aller.
  /// [onlySlotKeys] : si non-null, seuls ces slots sont traités (ignore les autres vides).
  Future<void> _fillVacatedSlots({Set<String> skipSlotKeys = const {}, Set<String>? onlySlotKeys}) async {
    if (_generatedMealPlan == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Charger recettes + servings une seule fois pour tous les slots vides.
    final allRecipesRaw = await _loadRecipes();
    final allServings = await _loadServings();

    // Résoudre les noms d'ingrédients pour que la similarité fonctionne correctement.
    final allIngredientIds = allRecipesRaw
        .expand((r) => r.ingredients.map((i) => i.ingredient.id))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
    final allRecipes = allRecipesRaw.map((recipe) {
      final resolved = recipe.ingredients.map((ri) {
        final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
        return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
      }).toList();
      return recipe.copyWith(ingredients: resolved);
    }).toList();

    final filteredRecipes = _applyPlannerRecipeFilters(allRecipes);
    if (filteredRecipes.isEmpty) return;

    final users = allServings
        .map((s) => s.userId)
        .toSet()
        .map((uid) => User(id: uid, name: uid))
        .toList();
    if (users.isEmpty) return;

    final currentUserIds = allServings.map((s) => s.userId).toSet();

    for (int i = 0; i < (_generatedMealPlan?.durationDays ?? 0); i++) {
      if (_generatedMealPlan == null) break;
      final day = _generatedMealPlan!.startDate.add(Duration(days: i));
      final dayNorm = DateTime(day.year, day.month, day.day);
      if (dayNorm.isBefore(today)) continue;

      for (final mealType in [MealType.lunch, MealType.dinner]) {
        if (_generatedMealPlan == null) break;
        // Skip slots that were originally leftovers — they should stay empty
        // or be filled naturally by leftover injection from the new source meal.
        if (skipSlotKeys.contains(_slotKey(day, mealType))) continue;
        // Si onlySlotKeys est fourni, ne traiter que ces slots spécifiques.
        if (onlySlotKeys != null && !onlySlotKeys.contains(_slotKey(day, mealType))) continue;
        final hasMeal = _generatedMealPlan!.meals.any((m) =>
            m.date.year == day.year &&
            m.date.month == day.month &&
            m.date.day == day.day &&
            m.type == mealType);
        if (hasMeal) continue;

        // Slot vide détecté — choisir la meilleure recette.

        // Compter les slots libres futurs (même type) disponibles pour des restes.
        final planEnd = _generatedMealPlan!.startDate
            .add(Duration(days: _generatedMealPlan!.durationDays - 1));
        int freeFollowingSlots = 0;
        DateTime checkDay = day.add(const Duration(days: 1));
        while (!DateTime(checkDay.year, checkDay.month, checkDay.day)
            .isAfter(DateTime(planEnd.year, planEnd.month, planEnd.day))) {
          final occupied = _generatedMealPlan!.meals.any((m) =>
              m.date.year == checkDay.year &&
              m.date.month == checkDay.month &&
              m.date.day == checkDay.day &&
              m.type == mealType);
          if (!occupied) freeFollowingSlots++;
          checkDay = checkDay.add(const Duration(days: 1));
        }

        // Si aucun slot suivant n'est libre, restreindre aux recettes sans restes.
        // Si aucune telle recette n'existe, laisser le slot vide et alerter.
        List<Recipe> recipesForSlot = filteredRecipes;
        if (freeFollowingSlots == 0) {
          final userPortions = allServings.fold<int>(0, (sum, s) =>
              sum + (mealType == MealType.lunch ? s.lunchServings : s.dinnerServings));
          final noLeftoverRecipes = filteredRecipes
              .where((r) => r.servings > 0 && userPortions % r.servings == 0)
              .toList();
          if (noLeftoverRecipes.isNotEmpty) {
            recipesForSlot = noLeftoverRecipes;
          } else {
            // Aucune recette sans restes disponible → slot laissé vide + alerte
            if (mounted) {
              final dayLabel =
                  '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
              final typeLabel = mealType == MealType.lunch ? 'déjeuner' : 'dîner';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour le $typeLabel du $dayLabel. Slot laissé vide.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            continue;
          }
        }

        final filteredHistory = _mealHistory.entries
            .expand((e) => e.value)
            .where((m) =>
                m.userServings.isEmpty ||
                m.userServings.keys.any((uid) => currentUserIds.contains(uid)))
            .toList();

        final otherPlanMeals = _generatedMealPlan!.meals
            .where((m) => !(
                m.date.year == day.year &&
                m.date.month == day.month &&
                m.date.day == day.day &&
                m.type == mealType))
            .toList();

        // Verrouille l'autre repas du même jour (s'il existe) pour que le slot
        // qui nous intéresse reçoive la bonne pénalité de similarité.
        final otherTypeForFill =
            mealType == MealType.lunch ? MealType.dinner : MealType.lunch;
        final sameDayOtherFillMeal = _generatedMealPlan!.meals.where((m) =>
            m.date.year == day.year &&
            m.date.month == day.month &&
            m.date.day == day.day &&
            m.type == otherTypeForFill &&
            !m.isLeftoverMeal).firstOrNull;
        final userSelectedForFill = sameDayOtherFillMeal != null
            ? [sameDayOtherFillMeal.copyWith(userSelected: true)]
            : <Meal>[];

        final tempPlan = await MealPlanningService.generateMealPlan(
          recipes: recipesForSlot,
          servings: allServings,
          users: users,
          startDate: day,
          durationDays: 1,
          recentMeals: [...filteredHistory, ...otherPlanMeals],
          userSelectedMeals: userSelectedForFill.isEmpty ? null : userSelectedForFill,
          pantryItems: _pantryIngredients,
          selectedCategories: _selectedCategories.toList(),
          referenceDate: day,
        );

        final newMeal = tempPlan.meals
            .where((m) => m.type == mealType)
            .firstOrNull;
        if (newMeal == null) continue;

        // Insérer le repas dans le plan courant.
        final insertedMeal = newMeal.copyWith(date: day);
        final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals)
          ..add(insertedMeal);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        if (mounted) setState(() => _generatedMealPlan = updatedPlan);
        // Injecter un reste si la recette produit plus de portions que consommées.
        await _injectLeftoverIfNeeded(insertedMeal);
      }
    }
  }

  /// Returns consecutive leftover meals associated with [mainMeal]:
  /// same recipe.id, same type, isLeftoverMeal=true, strictly after mainMeal's
  /// date (same type order), stopping at the first non-leftover occurrence of
  /// the same recipe (new independent serving).
  List<Meal> _getConsecutiveLeftoversOfMeal(Meal mainMeal, List<Meal> allMeals) {
    final mainDay = DateTime(mainMeal.date.year, mainMeal.date.month, mainMeal.date.day);
    final futureSameType = allMeals
        .where((m) => m.type == mainMeal.type)
        .where((m) {
          final mDay = DateTime(m.date.year, m.date.month, m.date.day);
          return mDay.isAfter(mainDay);
        })
        .toList()
      ..sort((a, b) {
        final da = DateTime(a.date.year, a.date.month, a.date.day);
        final db = DateTime(b.date.year, b.date.month, b.date.day);
        return da.compareTo(db);
      });

    final leftovers = <Meal>[];
    for (final m in futureSameType) {
      if (m.recipe.id != mainMeal.recipe.id) continue;
      if (!m.isLeftoverMeal) break; // nouvelle occurrence indépendante
      leftovers.add(m);
    }
    return leftovers;
  }

  /// Injecte un repas reste dans le slot du lendemain (même type) si la recette
  /// de [newMeal] produit plus de portions que consommées. Gère également le cas
  /// où le slot courant est lui-même un reste du jour précédent.
  ///
  /// Si [forceReplace] est true (choix explicite de l'utilisateur), les repas
  /// déjà présents dans les slots cibles sont supprimés pour laisser place aux restes.
  /// Retourne les slot keys des slots qui ont été vidés (pour pouvoir les re-remplir).
  Future<Set<String>> _injectLeftoverIfNeeded(Meal newMeal, {bool forceReplace = false}) async {
    final vacatedSlots = <String>{};
    if (_generatedMealPlan == null) return vacatedSlots;
    final cookedServings = newMeal.recipe.servings * newMeal.recipeMultiplier;
    final leftoverServings = cookedServings - newMeal.totalServings;
    if (leftoverServings <= 0) return vacatedSlots;

    final prevDay = newMeal.date.subtract(const Duration(days: 1));
    final prevDayHasSameRecipe = _generatedMealPlan!.meals.any((m) =>
        m.recipe.id == newMeal.recipe.id &&
        m.date.year == prevDay.year &&
        m.date.month == prevDay.month &&
        m.date.day == prevDay.day &&
        m.type == newMeal.type &&
        !m.isLeftoverMeal);
    if (prevDayHasSameRecipe) {
      // Le slot courant est lui-même un reste du jour précédent.
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);
      final idx = updatedMeals.indexWhere((m) =>
          m.recipe.id == newMeal.recipe.id &&
          m.date.year == newMeal.date.year &&
          m.date.month == newMeal.date.month &&
          m.date.day == newMeal.date.day &&
          m.type == newMeal.type);
      if (idx != -1) {
        updatedMeals[idx] = updatedMeals[idx].copyWith(isLeftoverMeal: true);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        setState(() => _generatedMealPlan = updatedPlan);
      }
    } else {
      // Propage les portions restantes sur les jours suivants (même type),
      // en boucle comme generateMealPlan, jusqu'à épuisement ou fin du plan.
      final planEnd = _generatedMealPlan!.startDate
          .add(Duration(days: _generatedMealPlan!.durationDays - 1));
      final planEndNorm = DateTime(planEnd.year, planEnd.month, planEnd.day);

      var remainingLeft = leftoverServings;
      DateTime candidateDay = newMeal.date.add(const Duration(days: 1));

      while (remainingLeft > 0) {
        final candidateNorm = DateTime(
            candidateDay.year, candidateDay.month, candidateDay.day);
        if (candidateNorm.isAfter(planEndNorm)) break;

        // Ne pas injecter si la recette est déjà présente ce jour-là.
        final alreadyHasSame = _generatedMealPlan!.meals.any((m) =>
            m.date.year == candidateDay.year &&
            m.date.month == candidateDay.month &&
            m.date.day == candidateDay.day &&
            m.type == newMeal.type &&
            m.recipe.id == newMeal.recipe.id);
        if (alreadyHasSame) {
          candidateDay = candidateDay.add(const Duration(days: 1));
          continue;
        }

        // En mode forceReplace (choix explicite de l'utilisateur), on supprime
        // les repas déjà présents sur ce slot pour laisser place aux restes.
        // On supprime aussi tous les restes futurs des recettes écrasées pour
        // éviter les restes orphelins.
        // En mode normal (shuffle auto), on respecte les repas existants.
        if (forceReplace) {
          // Identifier les repas frais qui vont être écrasés (pour nettoyer leurs restes)
          final mealsToRemove = _generatedMealPlan!.meals.where((m) =>
              m.date.year == candidateDay.year &&
              m.date.month == candidateDay.month &&
              m.date.day == candidateDay.day &&
              m.type == newMeal.type).toList();
          final candidateDayNorm = DateTime(candidateDay.year, candidateDay.month, candidateDay.day);
          // Identifier les restes futurs des recettes écrasées AVANT suppression
          // pour les ajouter à vacatedSlots (ils deviendront des slots vides).
          final futureLeftoversOfErased = _generatedMealPlan!.meals.where((m) {
            if (!m.isLeftoverMeal) return false;
            final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
            if (!mDateNorm.isAfter(candidateDayNorm)) return false;
            return mealsToRemove.any((removed) =>
                !removed.isLeftoverMeal &&
                removed.recipe.id == m.recipe.id &&
                removed.type == m.type);
          }).toList();
          final updatedMealsForce = List<Meal>.from(_generatedMealPlan!.meals)
            ..removeWhere((m) {
              // Supprimer le repas du slot cible
              if (m.date.year == candidateDay.year &&
                  m.date.month == candidateDay.month &&
                  m.date.day == candidateDay.day &&
                  m.type == newMeal.type) return true;
              // Supprimer les restes futurs des recettes écrasées
              if (m.isLeftoverMeal) {
                final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
                if (mDateNorm.isAfter(candidateDayNorm)) {
                  return mealsToRemove.any((removed) =>
                      !removed.isLeftoverMeal &&
                      removed.recipe.id == m.recipe.id &&
                      removed.type == m.type);
                }
              }
              return false;
            });
          // Tracker les restes futurs supprimés → ils deviennent des slots vides à remplir
          for (final lo in futureLeftoversOfErased) {
            vacatedSlots.add(_slotKey(lo.date, lo.type));
          }
          _generatedMealPlan = _generatedMealPlan!.copyWith(meals: updatedMealsForce);
        }

        // Utilisateurs qui ont déjà un repas (frais OU reste) ce slot.
        // En mode forceReplace ils ont été supprimés ci-dessus, donc tous sont éligibles.
        final usersWithAnyMeal = forceReplace
            ? <String>{}
            : _generatedMealPlan!.meals
                .where((m) =>
                    m.date.year == candidateDay.year &&
                    m.date.month == candidateDay.month &&
                    m.date.day == candidateDay.day &&
                    m.type == newMeal.type)
                .expand((m) => m.userServings.keys)
                .toSet();

        // Calculer les portions à injecter pour ce slot.
        final leftoverUserServings = <String, int>{};
        int leftoverTotal = 0;
        final eligibleEntries = newMeal.userServings.entries
            .where((e) => !usersWithAnyMeal.contains(e.key))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        for (int idx = 0; idx < eligibleEntries.length; idx++) {
          if (remainingLeft <= 0) break;
          final entry = eligibleEntries[idx];
          final portionsNeeded = entry.value;
          final usersLeft = eligibleEntries.length - idx;
          final fairShare = max(1, remainingLeft ~/ usersLeft);
          final toAssign = min(portionsNeeded, min(fairShare, remainingLeft));
          if (toAssign > 0) {
            leftoverUserServings[entry.key] = toAssign;
            leftoverTotal += toAssign;
            remainingLeft -= toAssign;
          }
        }

        if (leftoverTotal == 0) {
          // Tous les users ont déjà un repas ce slot → arrêter la cascade.
          break;
        }

        final leftover = Meal(
          recipe: newMeal.recipe,
          date: candidateDay,
          type: newMeal.type,
          totalServings: leftoverTotal,
          userServings: leftoverUserServings,
          recipeMultiplier: 1,
          isLeftoverMeal: true,
        );
        final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals)..add(leftover);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        setState(() => _generatedMealPlan = updatedPlan);

        candidateDay = candidateDay.add(const Duration(days: 1));
      }
    }
    return vacatedSlots;
  }
}
