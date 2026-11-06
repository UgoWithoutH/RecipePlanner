// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerGeneration on _PlannerPageState {
  Future<void> _deletePlan() async {
    final confirm = await showModalBottomSheet<bool>(
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
            Text('Supprimer le plan',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Le plan de repas actuel sera supprimé définitivement. L\'historique ne sera pas affecté.',
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
    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _mealPlanRepo.deleteMealPlan(_generatedMealPlan!.id);
      await FirebasePantrySnapshotRepository.instance.delete();
      await FirebaseShoppingListRepository().deleteGroupShoppingList();
      final historyDates = _mealHistory.keys.toList()..sort((a, b) => b.compareTo(a));
      setState(() {
        _generatedMealPlan = null;
        _pantrySnapshot = [];
        _calendarFormat = null;
        _selectedMealDate = historyDates.isNotEmpty ? historyDates.first : null;
        _focusedDay = historyDates.isNotEmpty ? historyDates.first : DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchPlanning() async {
    if (_selectedStartDate == null || _selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'Veuillez sélectionner une date et une durée',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF6A5AE0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isGenerating = true;
      _generationProgress = 0.0;
      _generationStep = 'Chargement des recettes…';
    });
    // New plan — clear all auto-change bans
    _autoChangeBannedRecipes.clear();
    _algoExhaustedSlots.clear();
    try {
      final allRecipes = await _loadRecipes(forceRefresh: true);
      // History duration is always based on the total number of recipes (all categories)
      _maxHistoryDays = allRecipes.length;

      if (mounted) setState(() { _generationProgress = 0.02; _generationStep = 'Filtrage des recettes…'; });

      final recipes = _applyPlannerRecipeFilters(allRecipes);

      if (recipes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette trouvée pour les filtres sélectionnés.',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.9),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              elevation: 4,
            ),
          );
        }
        return;
      }

      if (mounted) setState(() { _generationProgress = 0.04; _generationStep = 'Chargement des portions…'; });

      final servings = await _loadServings();
      // Synchroniser _userNames depuis les servings via la méthode centralisée
      await _loadUserNames();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      if (mounted) setState(() { _generationProgress = 0.06; _generationStep = 'Résolution des ingrédients…'; });

      // Résoudre les noms d'ingrédients (stockés séparément dans Firestore)
      // Les recettes ont ingredient.name = '' par défaut après fetchAllRecipes()
      final allIngredientIds = recipes
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final recipesWithNames = recipes.map((recipe) {
        final resolvedIngredients = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolvedIngredients);
      }).toList();

      // Filter historical meals to only include the last N days (N = total recipe count)
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: _maxHistoryDays));
      final currentUserIds = servings.map((s) => s.userId).toSet();
      final filteredHistoryMeals = _mealHistory.entries
          .where((entry) => !entry.key.isBefore(cutoffDate))
          .expand((entry) => entry.value)
          // Discard meals whose userServings belong to stale/deleted users.
          // This prevents leftover injection from old seed data (e.g. userA/userB)
          // when the current user set has changed.
          .where((meal) => meal.userServings.isEmpty ||
              meal.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      if (mounted) setState(() { _generationProgress = 0.08; _generationStep = 'Génération du plan…'; });

      final plan = await MealPlanningService.generateMealPlan(
        recipes: recipesWithNames,
        servings: servings,
        users: users,
        startDate: _selectedStartDate!,
        durationDays: _selectedDuration!,
        recentMeals: filteredHistoryMeals,
        pantryItems: _pantryIngredients,
        urgentPantryIngredientNames: _urgentPantryNames,
        selectedCategories: _selectedCategories.toList(),
        leftoverUserOrder: _generatedMealPlan?.leftoverUserOrder ?? [],
        ignoreHistoryLeftovers: true,
        onProgress: (filled, total) {
          if (!mounted) return;
          final dayNum = (filled ~/ 2) + 1;
          final totalDays = total ~/ 2;
          final mealLabel = filled % 2 == 0 ? 'midi' : 'soir';
          setState(() {
            _generationProgress = 0.08 + 0.84 * filled / total;
            _generationStep = filled < total
                ? 'Jour $dayNum/$totalDays — $mealLabel'
                : 'Finalisation…';
          });
        },
      );

      setState(() {
        _generatedMealPlan = plan;
        _selectedMealDate = plan.startDate;
        _focusedDay = plan.startDate;
        _calendarFormat = null; // Reset to recalculate format
      });

      // ── LOG plan généré ──
      if (kDebugMode) {
        // ── Frigo / placard transmis à l'algorithme ──
        debugPrint('[PLAN] ===== Frigo / Placard =====');
        if (_pantryIngredients.isEmpty) {
          debugPrint('[PLAN]   (vide)');
        } else {
          for (final ri in _pantryIngredients) {
            final urgent = _urgentPantryNames.contains(ri.ingredient.name) ? ' [URGENT]' : '';
            debugPrint('[PLAN]   ${ri.ingredient.name}$urgent  ${ri.quantity} ${ri.unit.label}');
          }
        }
        debugPrint('[PLAN] ================================');

        // ── Historique transmis à l'algorithme ──
        debugPrint('[PLAN] ===== Historique utilisé =====');
        if (filteredHistoryMeals.isEmpty) {
          debugPrint('[PLAN]   (aucun historique)');
        } else {
          final histByDay = <String, List<Meal>>{};
          for (final m in filteredHistoryMeals) {
            final key = '${m.date.year}-${m.date.month.toString().padLeft(2,'0')}-${m.date.day.toString().padLeft(2,'0')}';
            histByDay.putIfAbsent(key, () => []).add(m);
          }
          for (final day in (histByDay.keys.toList()..sort())) {
            final hMeals = histByDay[day]!..sort((a, b) => a.type.index.compareTo(b.type.index));
            for (final m in hMeals) {
              final type = m.type == MealType.lunch ? 'MIDI ' : 'SOIR ';
              final leftover = m.isLeftoverMeal ? ' [RESTE]' : '';
              final rating = m.recipe.rating > 0
                  ? ' | note ${m.recipe.rating.toStringAsFixed(m.recipe.rating % 1 == 0 ? 0 : 1)}/5'
                  : ' | note -';
              final portions = m.userServings.isEmpty
                  ? '${m.totalServings} portion(s)'
                  : m.userServings.entries.map((e) => '${e.key.substring(0,6)}:${e.value}p').join(', ');
              debugPrint('[PLAN]   $day $type| ${m.recipe.title}$leftover$rating  ($portions)');
            }
          }
        }
        debugPrint('[PLAN] ============================');

        debugPrint('[PLAN] ===== Plan généré =====');
        debugPrint('[PLAN] Début: ${plan.startDate.day}/${plan.startDate.month}/${plan.startDate.year}  |  Durée: ${plan.durationDays} jours');
        debugPrint('[PLAN] Nombre de repas total: ${plan.meals.length}');
        final mealsByDay = <String, List<Meal>>{};
        for (final m in plan.meals) {
          final key = '${m.date.year}-${m.date.month.toString().padLeft(2,'0')}-${m.date.day.toString().padLeft(2,'0')}';
          mealsByDay.putIfAbsent(key, () => []).add(m);
        }
        for (final day in (mealsByDay.keys.toList()..sort())) {
          final meals = mealsByDay[day]!..sort((a, b) => a.type.index.compareTo(b.type.index));
          for (final m in meals) {
            final type = m.type == MealType.lunch ? 'MIDI ' : 'SOIR ';
            final leftover = m.isLeftoverMeal ? ' [RESTE]' : '';
            final mult = m.recipeMultiplier > 1 ? ' x${m.recipeMultiplier}' : '';
            final rating = m.recipe.rating > 0
                ? ' | note ${m.recipe.rating.toStringAsFixed(m.recipe.rating % 1 == 0 ? 0 : 1)}/5'
                : ' | note -';
            final portions = m.userServings.isEmpty
                ? '${m.totalServings} portion(s)'
                : m.userServings.entries.map((e) => '${e.key.substring(0,6)}:${e.value}p').join(', ');
            debugPrint('[PLAN]   $day $type| ${m.recipe.title}$mult$leftover$rating  ($portions)');
          }
        }
        debugPrint('[PLAN] ========================');
      }

      // ── Détection des restes non injectés (portions perdues) ──
      _showWastedLeftoversSnackbar(plan);

      if (mounted) setState(() { _generationProgress = 0.93; _generationStep = 'Sauvegarde du plan…'; });

      final savedId = await _saveMealPlan(plan);

      if (mounted) setState(() { _generationProgress = 0.97; _generationStep = 'Mise à jour du frigo/placard…'; });

      // Figer le snapshot frigo/placard pour ce plan
      final currentPantryItems = await FirebasePantryRepository.instance.getAll();
      await FirebasePantrySnapshotRepository.instance.save(currentPantryItems);
      if (mounted) {
        setState(() {
          _pantrySnapshot = currentPantryItems
              .map(PantrySnapshotItem.fromPantryItem)
              .toList();
        });
      }

      // Update the plan with the saved ID
      setState(() {
        _generatedMealPlan = MealPlan(
          id: savedId,
          startDate: plan.startDate,
          durationDays: plan.durationDays,
          meals: plan.meals,
          createdAt: plan.createdAt,
          pantryItems: plan.pantryItems,
          selectedCategories: plan.selectedCategories,
          leftoverUserOrder: plan.leftoverUserOrder,
        );
      });

      if (mounted) setState(() { _generationProgress = 1.0; _generationStep = 'Plan généré !'; });

      // Planifie silencieusement les notifications pour ce nouveau plan
      _autoScheduleNotifications(_generatedMealPlan!).ignore();

    } finally {
      setState(() {
        _isLoading = false;
        _isGenerating = false;
        _generationProgress = 0.0;
        _generationStep = '';
      });
    }
  }

  /// Planifie silencieusement les notifications locales pour [plan] en utilisant
  /// les préférences sauvegardées de l'utilisateur courant.
  /// Appelée à chaque chargement/génération de plan — remplace les notifs existantes.
  Future<void> _autoScheduleNotifications(MealPlan plan) async {
    try {
      final settings = await NotificationSettingsRepository().load();
      final notifService = NotificationService();
      final granted = await notifService.requestPermissions();
      if (!granted) return;

      final now = DateTime.now();
      final effectiveDays = settings.effectiveNotificationDaysForPlan(
          plan.id, plan.durationDays);

      // Jours activés ET dont la notification est dans le futur
      final activeDays = <int>{};
      for (int i = 0; i < plan.durationDays; i++) {
        if (!effectiveDays[i]) continue;
        final planDay = plan.startDate.add(Duration(days: i));
        final notifyDay = planDay.add(Duration(days: settings.offsetDays));
        final notifyDateTime = DateTime(
          notifyDay.year, notifyDay.month, notifyDay.day,
          settings.time.hour, settings.time.minute,
        );
        if (notifyDateTime.isAfter(now)) activeDays.add(i);
      }

      if (activeDays.isEmpty) return;

      await notifService.scheduleMealPlanNotifications(
        plan: plan,
        notificationTime: settings.time,
        activeDays: activeDays,
        offsetDays: settings.offsetDays,
      );
    } catch (e, st) {
      // Ne doit pas bloquer l'UI — loggé en debug pour diagnostic
      debugPrint('[Notifications] Erreur : $e\n$st');
    }
  }

  String _slotKey(DateTime date, MealType type) =>
      '${date.year}-${date.month}-${date.day}_${type.name}';

  /// Clé unique pour identifier un Meal spécifique dans le multi-shuffle.
  String _mealKey(Meal meal) =>
      '${meal.date.year}-${meal.date.month}-${meal.date.day}_${meal.type.name}_${meal.recipe.id}_${meal.isLeftoverMeal}';
}
