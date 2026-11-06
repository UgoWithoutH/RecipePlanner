// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerMealDelete on _PlannerPageState {
  void _openRecipeDetail(Meal meal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: meal.recipe.id,
          initialRecipe: meal.recipe,
        ),
      ),
    ).then((_) {
      _loadMostRecentMealPlanAndHistory();
    });
  }

  Future<void> _deleteMeal(Meal mealToDelete) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mealDate = DateTime(
        mealToDelete.date.year, mealToDelete.date.month, mealToDelete.date.day);
    final isHistory = mealDate.isBefore(today);

    if (isHistory) {
      // ── Suppression d'un repas historisé ──
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
              ),
              const SizedBox(height: 16),
              Text('Supprimer de l\'historique ?',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
              const SizedBox(height: 8),
              Text('Voulez-vous retirer "${mealToDelete.recipe.title}" de l\'historique ?',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400], foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                )),
              ]),
            ],
          ),
        ),
      );
      if (confirmed != true) return;

      setState(() => _isLoading = true);
      try {
        // Mettre à jour l'historique local + Firestore
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        final previousMeals = List<Meal>.from(historyMeals);
        historyMeals.removeWhere((m) =>
            m.date.year == mealToDelete.date.year &&
            m.date.month == mealToDelete.date.month &&
            m.date.day == mealToDelete.date.day &&
            m.type == mealToDelete.type &&
            m.recipe.id == mealToDelete.recipe.id);

        if (historyMeals.isEmpty) {
          _mealHistory.remove(mealDate);
          await _historyRepo.deleteDayFromHistory(mealDate, mealsBeingDeleted: previousMeals);
        } else {
          _mealHistory[mealDate] = historyMeals;
          await _historyRepo.addDayToHistory(mealDate, historyMeals, previousMeals: previousMeals);
        }
        setState(() {});
      } finally {
        setState(() => _isLoading = false);
      }

      if (!mounted) return;
      // Proposer de remettre les ingrédients dans le frigo/placard
      final restorePantry = await _showPantryModificationDialog(
        title: 'Remettre dans le frigo/placard ?',
        message:
            'Ce plat n\'a pas été cuisiné. Voulez-vous remettre les ingrédients de "${mealToDelete.recipe.title}" dans le frigo/placard ?',
        confirmLabel: 'Oui, remettre',
        icon: Icons.kitchen_rounded,
        color: const Color(0xFF6A5AE0),
      );

      if (restorePantry == true) {
        setState(() => _isLoading = true);
        try {
          final fullRecipe =
              await _recipeRepo.fetchRecipeById(mealToDelete.recipe.id);
          if (fullRecipe != null) {
            final mealWithIngredients = mealToDelete.copyWith(recipe: fullRecipe);
            await FirebasePantryRepository.instance
                .restoreFromMeals([mealWithIngredients]);
            await _loadPantryFromRepository();
          }
        } finally {
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (_generatedMealPlan == null) return;

    // Vérifie si une deuxième occurrence (restes) existe le lendemain
    final nextDay = mealToDelete.date.add(const Duration(days: 1));
    final hasLeftover = !mealToDelete.isLeftoverMeal &&
        _generatedMealPlan!.meals.any((m) =>
            m.recipe.id == mealToDelete.recipe.id &&
            m.date.year == nextDay.year &&
            m.date.month == nextDay.month &&
            m.date.day == nextDay.day &&
            m.isLeftoverMeal);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text('Supprimer ce repas ?',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous retirer "${mealToDelete.recipe.title}" du plan ?',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
            if (hasLeftover) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cette recette est prévue en deux fois : le repas du lendemain (restes) sera également retiré du plan.',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400], foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
              )),
            ]),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to delete (slot = date + type + isLeftoverMeal).
      final indexToDelete = updatedMeals.indexWhere(
        (m) =>
            m.date.year == mealToDelete.date.year &&
            m.date.month == mealToDelete.date.month &&
            m.date.day == mealToDelete.date.day &&
            m.type == mealToDelete.type &&
            m.isLeftoverMeal == mealToDelete.isLeftoverMeal,
      );

      if (indexToDelete == -1) return;

      // Remove leftover of this recipe from next day if one exists
      if (!mealToDelete.isLeftoverMeal) {
        // Also remove the leftover from the next day
        final nextDay = mealToDelete.date.add(const Duration(days: 1));
        updatedMeals.removeWhere(
          (m) =>
              m.recipe.id == mealToDelete.recipe.id &&
              m.date.year == nextDay.year &&
              m.date.month == nextDay.month &&
              m.date.day == nextDay.day &&
              m.isLeftoverMeal,
        );
      }

      // Delete the main meal
      updatedMeals.removeAt(indexToDelete);

      // Update the plan
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

      // Save to database
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Repas supprimé', style: GoogleFonts.poppins(color: Colors.white))),
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
}
