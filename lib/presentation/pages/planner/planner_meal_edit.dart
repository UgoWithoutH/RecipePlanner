// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerMealEdit on _PlannerPageState {
  Future<void> _changeMealRecipe(Meal mealToUpdate, Recipe newRecipe, {bool showSnackbar = true, Meal? fullMeal, bool suppressLeftoverDialog = false}) async {
    setState(() => _isLoading = true);
    try {
      // Check if the meal belongs to history
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final mealDate = DateTime(mealToUpdate.date.year, mealToUpdate.date.month, mealToUpdate.date.day);
      final isHistory = mealDate.isBefore(today);

      if (isHistory) {
        // Edit the meal in history
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        final previousMeals = List<Meal>.from(historyMeals); // snapshot avant modif
        final indexToUpdate = historyMeals.indexWhere(
          (m) =>
              m.date.year == mealToUpdate.date.year &&
              m.date.month == mealToUpdate.date.month &&
              m.date.day == mealToUpdate.date.day &&
              m.type == mealToUpdate.type &&
              m.recipe.id == mealToUpdate.recipe.id,
        );
        if (indexToUpdate == -1) return;

        // Replace the meal with the new one
        historyMeals[indexToUpdate] = Meal(
          recipe: newRecipe,
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          totalServings: newRecipe.servings,
          userServings: {},
          recipeMultiplier: 1,
          isLeftoverMeal: false,
          userSelected: true,
        );

        // Update local history
        _mealHistory[mealDate] = historyMeals;

        // Persist the change in Firestore history (diff pour usageCount)
        await _historyRepo.addDayToHistory(mealDate, historyMeals, previousMeals: previousMeals);

        // Sync the change back to the meal plan document so that deleting
        // history and re-adding doesn't restore the old recipe.
        if (_generatedMealPlan != null) {
          final planMealIndex = _generatedMealPlan!.meals.indexWhere((m) =>
              m.date.year == mealToUpdate.date.year &&
              m.date.month == mealToUpdate.date.month &&
              m.date.day == mealToUpdate.date.day &&
              m.type == mealToUpdate.type &&
              m.recipe.id == mealToUpdate.recipe.id);
          if (planMealIndex != -1) {
            final updatedPlanMeals = List<Meal>.from(_generatedMealPlan!.meals);
            updatedPlanMeals[planMealIndex] = historyMeals[indexToUpdate];
            final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedPlanMeals);
            await _mealPlanRepo.saveMealPlan(updatedPlan);
            _generatedMealPlan = updatedPlan;
          }
        }

        setState(() {});

        if (!mounted) return;
        if (showSnackbar)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Recette historique modifiée', style: GoogleFonts.poppins(color: Colors.white))),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );

        // Proposer de REMETTRE les ingrédients de l'ANCIENNE recette dans le frigo/placard
        // (elle n'a pas été cuisinée)
        if (!mounted) return;
        final restorePantry = await _showPantryModificationDialog(
          title: 'Remettre dans le frigo/placard ?',
          message:
              'Vous n\'avez pas cuisiné "${mealToUpdate.recipe.title}". Voulez-vous remettre ses ingrédients dans le frigo/placard ?',
          confirmLabel: 'Oui, remettre',
          icon: Icons.kitchen_rounded,
          color: const Color(0xFF6A5AE0),
        );
        if (restorePantry == true) {
          setState(() => _isLoading = true);
          try {
            final oldFullRecipe = await _recipeRepo.fetchRecipeById(mealToUpdate.recipe.id);
            if (oldFullRecipe != null) {
              // Résoudre les noms des ingrédients (stockés séparément)
              final ids = oldFullRecipe.ingredients
                  .map((i) => i.ingredient.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              final nameMap = await IngredientNameCache.instance.fetchNamesForIds(ids);
              final resolved = oldFullRecipe.copyWith(
                ingredients: oldFullRecipe.ingredients.map((ri) {
                  final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
                  return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
                }).toList(),
              );
              final oldMeal = Meal(
                recipe: resolved,
                date: mealToUpdate.date,
                type: mealToUpdate.type,
                totalServings: resolved.servings,
                userServings: {},
                recipeMultiplier: 1,
                isLeftoverMeal: false,
                userSelected: true,
              );
              await FirebasePantryRepository.instance.restoreFromMeals([oldMeal]);
              await _loadPantryFromRepository();
            }
          } finally {
            setState(() => _isLoading = false);
          }
        }

        // Proposer de DÉDUIRE les ingrédients de la NOUVELLE recette du frigo/placard
        // (elle a été cuisinée à la place, et c'est un jour passé)
        if (!mounted) return;
        final deductPantry = await _showPantryModificationDialog(
          title: 'Déduire du frigo/placard ?',
          message:
              'Vous avez cuisiné "${newRecipe.title}" à la place. Voulez-vous déduire ses ingrédients du frigo/placard ?',
          confirmLabel: 'Oui, déduire',
          icon: Icons.kitchen_rounded,
          color: const Color(0xFF6A5AE0),
        );
        if (deductPantry == true) {
          setState(() => _isLoading = true);
          try {
            final fullRecipe = await _recipeRepo.fetchRecipeById(newRecipe.id);
            if (fullRecipe != null) {
              // Résoudre les noms des ingrédients (stockés séparément)
              final ids = fullRecipe.ingredients
                  .map((i) => i.ingredient.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              final nameMap = await IngredientNameCache.instance.fetchNamesForIds(ids);
              final resolved = fullRecipe.copyWith(
                ingredients: fullRecipe.ingredients.map((ri) {
                  final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
                  return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
                }).toList(),
              );
              final newMeal = Meal(
                recipe: resolved,
                date: mealToUpdate.date,
                type: mealToUpdate.type,
                totalServings: resolved.servings,
                userServings: {},
                recipeMultiplier: 1,
                isLeftoverMeal: false,
                userSelected: true,
              );
              await FirebasePantryRepository.instance.deductFromMeals([newMeal]);
              await _loadPantryFromRepository();
            }
          } finally {
            setState(() => _isLoading = false);
          }
        }
        return;
      }

      // ...existing logic for the generated plan...
      if (_generatedMealPlan == null) return;
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to update.
      // Identify the slot by (date, type, isLeftoverMeal) — not by recipe.id —
      // so the lookup is robust even when the plan has been reloaded from Firestore.
      final indexToUpdate = updatedMeals.indexWhere(
        (m) =>
            m.date.year == mealToUpdate.date.year &&
            m.date.month == mealToUpdate.date.month &&
            m.date.day == mealToUpdate.date.day &&
            m.type == mealToUpdate.type &&
            m.isLeftoverMeal == mealToUpdate.isLeftoverMeal,
      );

      if (indexToUpdate == -1) return;

      // --- CLEANUP OLD RECIPE LOGIC (Same as delete) ---

      // Remove ALL future leftovers of the old recipe (any day after the source meal).
      // Only removing J+1 left orphaned leftovers on J+2, J+3, etc., which then
      // blocked _injectLeftoverIfNeeded from cascading to those days correctly.
      if (!mealToUpdate.isLeftoverMeal) {
        final sourceDateNorm = DateTime(
            mealToUpdate.date.year, mealToUpdate.date.month, mealToUpdate.date.day);
        updatedMeals.removeWhere((m) {
          if (!m.isLeftoverMeal) return false;
          if (m.recipe.id != mealToUpdate.recipe.id) return false;
          if (m.type != mealToUpdate.type) return false;
          final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
          return mDateNorm.isAfter(sourceDateNorm);
        });
      }

      // --- UPDATE CURRENT SLOT ---
      // Si un Meal complet est fourni (ex: shuffle), on l'utilise directement.
      // Sinon (sélection manuelle), on calcule les vrais userServings depuis
      // la config des portions pour détecter correctement les restes.
      final Meal savedMeal;
      if (fullMeal != null) {
        savedMeal = fullMeal.copyWith(
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          isLeftoverMeal: false,
          userSelected: true,
        );
      } else {
        // Calcul des portions réellement consommées depuis la config
        final allServings = await _loadServings();
        final userServingsMap = <String, int>{};
        int totalConsumed = 0;
        for (final s in allServings.where((s) => s.recipeId == newRecipe.id)) {
          final portions = mealToUpdate.type == MealType.lunch
              ? s.lunchServings
              : s.dinnerServings;
          if (portions > 0) {
            userServingsMap[s.userId] = portions;
            totalConsumed += portions;
          }
        }
        // Fallback si pas de config : toutes les portions consommées (pas de restes)
        savedMeal = Meal(
          recipe: newRecipe,
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          totalServings: totalConsumed > 0 ? totalConsumed : newRecipe.servings,
          userServings: userServingsMap,
          recipeMultiplier: 1,
          isLeftoverMeal: false,
          userSelected: true,
        );
      }
      updatedMeals[indexToUpdate] = savedMeal;

      // --- SAVE ---

      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
      );

      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (kDebugMode) {
        final _typeLabel = savedMeal.type == MealType.lunch ? 'MIDI' : 'SOIR';
        final _cooked = savedMeal.recipe.servings * savedMeal.recipeMultiplier;
        debugPrint('[MANUAL] Recette modifiée — ${savedMeal.date.day}/${savedMeal.date.month} $_typeLabel');
        debugPrint('[MANUAL]   Recette   : ${savedMeal.recipe.title}');
        debugPrint('[MANUAL]   Portions cuisinées : $_cooked  |  Consommées : ${savedMeal.totalServings}  |  Restes : ${(_cooked - savedMeal.totalServings).clamp(0, 999)}');
      }

      // --- RESTES : proposer de cascader si la recette en produit ---
      if (!suppressLeftoverDialog && fullMeal == null) {
        final cookedServings = savedMeal.recipe.servings * savedMeal.recipeMultiplier;
        final leftoverServings = cookedServings - savedMeal.totalServings;
        if (leftoverServings > 0 && mounted) {
          final injectLeftovers = await _showPantryModificationDialog(
            title: 'Planifier les restes ?',
            message:
                '"${newRecipe.title}" donne $cookedServings portions pour ${savedMeal.totalServings} consommée${savedMeal.totalServings > 1 ? 's' : ''}. '
                'Voulez-vous planifier les $leftoverServings portion${leftoverServings > 1 ? 's' : ''} restante${leftoverServings > 1 ? 's' : ''} sur les jours suivants ?',
            confirmLabel: 'Oui, planifier',
            icon: Icons.restaurant_rounded,
            color: const Color(0xFF6A5AE0),
          );
          if (injectLeftovers == true) {
            final vacated = await _injectLeftoverIfNeeded(savedMeal, forceReplace: true);
            // Informer l'utilisateur des slots laissés vides suite aux écrasements.
            if (vacated.isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${vacated.length} créneau${vacated.length > 1 ? 'x' : ''} laissé${vacated.length > 1 ? 's' : ''} vide${vacated.length > 1 ? 's' : ''} suite aux restes. Ajoutez manuellement un repas si nécessaire.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFF6A5AE0),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 6),
              ));
            }
          }
        }
      }

      if (_generatedMealPlan != null) _showWastedLeftoversSnackbar(_generatedMealPlan!);
      if (!mounted) return;
      if (showSnackbar)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Recette modifiée', style: GoogleFonts.poppins(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMealToPlan(
    Recipe recipe,
    DateTime date,
    MealType type,
  ) async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final mealDate = DateTime(date.year, date.month, date.day);
      final newMeal = Meal(
        recipe: recipe,
        date: date,
        type: type,
        totalServings: recipe.servings,
        userServings: {},
        recipeMultiplier: 1,
        isLeftoverMeal: false,
        userSelected: true,
      );

      if (mealDate.isBefore(today)) {
        // Add to history
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        historyMeals.add(newMeal);
        _mealHistory[mealDate] = historyMeals;
        await _historyRepo.addDayToHistory(mealDate, historyMeals);
        setState(() {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Repas historique ajouté', style: GoogleFonts.poppins(color: Colors.white))),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );
        return;
      }

      // Add to the generated plan (existing behavior)
      if (_generatedMealPlan == null) return;
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);
      updatedMeals.add(newMeal);
      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
      );
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
      setState(() {
        _generatedMealPlan = updatedPlan;
      });
      if (kDebugMode) {
        final _addTypeLabel = newMeal.type == MealType.lunch ? 'MIDI' : 'SOIR';
        debugPrint('[MANUAL] Repas ajouté — ${newMeal.date.day}/${newMeal.date.month} $_addTypeLabel');
        debugPrint('[MANUAL]   Recette   : ${newMeal.recipe.title}');
        debugPrint('[MANUAL]   Portions cuisinées : ${newMeal.recipe.servings}  |  Consommées : ${newMeal.totalServings}  |  Restes : ${(newMeal.recipe.servings - newMeal.totalServings).clamp(0, 999)}');
      }
      _showWastedLeftoversSnackbar(updatedPlan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Repas ajouté', style: GoogleFonts.poppins(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRecipeSelector({
    Meal? mealToUpdate,
    DateTime? date,
    MealType? type,
    bool requireConfirmation = true,
  }) async {
    // Pre-load recipe count to compute a snug initial sheet height
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    final snap = groupId != null
        ? await FirebaseFirestore.instance
            .collection('recipes')
            .where('groupId', isEqualTo: groupId)
            .get()
        : await FirebaseFirestore.instance.collection('recipes').limit(0).get();
    if (!mounted) return;
    final recipeCount = snap.docs.length;

    // header ≈ 305 px (outer title + RecipeSelector header + filters), each item ≈ 82 px
    const double headerPx = 305;
    const double itemPx = 82;
    const double minFraction = 0.50;
    const double maxFraction = 0.95;
    final screenH = MediaQuery.of(context).size.height;
    final contentH = headerPx + recipeCount * itemPx + 24;
    final initial = (contentH / screenH).clamp(minFraction, maxFraction);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          DraggableScrollableSheet(
            initialChildSize: initial,
            minChildSize: 0.3,
            maxChildSize: maxFraction,
            builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choisir une recette',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black45),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: RecipeSelector(
                scrollController: scrollController,
          onRecipeSelected: (newRecipe) async {
            // Check if it's a historical meal (past date, without time)
            bool isHistory = false;
            if (mealToUpdate != null) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final mealDate = DateTime(
                mealToUpdate.date.year,
                mealToUpdate.date.month,
                mealToUpdate.date.day,
              );
              isHistory = mealDate.isBefore(today);
            }
            if (mealToUpdate != null && isHistory && requireConfirmation) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history, color: Colors.orange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Repas historique',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(foregroundColor: Colors.black54),
                      child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A5AE0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        elevation: 0,
                      ),
                      child: Text('Oui, modifier', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              Navigator.pop(context); // Close modal after confirmation
              _changeMealRecipe(mealToUpdate, newRecipe);
              return;
            }
            Navigator.pop(context); // Close modal (normal case)
            if (mealToUpdate != null) {
              _changeMealRecipe(mealToUpdate, newRecipe);
            } else if (date != null && type != null) {
              _addMealToPlan(newRecipe, date, type);
            }
          },
        ),
            ),
          ],
        ),
      ),
          ), // DraggableScrollableSheet
        ], // Stack children
      ), // Stack
    );
  }

  /* ================= UI ================= */
}
