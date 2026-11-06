// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerData on _PlannerPageState {
  Future<void> _loadPantryFromRepository() async {
    try {
      final items = await FirebasePantryRepository.instance.getAll();
      if (!mounted) return;
      setState(() {
        _pantryIngredients =
            items.map((i) => i.toRecipeIngredient()).toList();
        _rawPantryItems = items;
        _urgentPantryNames = items
            .where((i) => i.isUrgent)
            .map((i) => i.name)
            .toSet();
      });
    } catch (_) {
      // Silently fall back to plan-stored items if repository is unavailable.
    }
  }

  Future<void> _loadAllCategories({bool forceRefresh = false}) async {
    if (!forceRefresh && _categoryDataById.isNotEmpty) return;
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('groupId', isEqualTo: groupId)
        .get();
    
    final allCategories = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['name'] as String? ?? '').trim(),
        'color': data['color'] is int ? data['color'] as int : 0xFF6A5AE0,
      };
    }).where((e) => (e['name'] as String).isNotEmpty).toList();

    if (mounted) {
      setState(() {
        _categoryDataById = {
          for (final e in allCategories) e['id'] as String: e
        };
      });
    }
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load categories
    final savedCats = prefs.getStringList(_kPrefKeyCategories);
    if (savedCats != null && savedCats.isNotEmpty && mounted) {
      setState(() => _selectedCategories = savedCats.toSet());
    }

    // Load duration
    final savedDuration = prefs.getInt(_kPrefKeyDuration);
    if (savedDuration != null && mounted) {
      setState(() => _selectedDuration = savedDuration);
    }

    // Load minimum rating
    final savedMinRating = prefs.getDouble(_kPrefKeyMinRating);
    if (savedMinRating != null && mounted) {
      setState(() => _selectedMinRating = savedMinRating.clamp(0.0, 5.0));
    }

    // Load persisted locked slots (multi-shuffle)
    final savedLocked = prefs.getStringList(_kPrefKeyLockedSlots);
    if (savedLocked != null) {
      _persistedLockedSlotKeys = savedLocked.toSet();
    }
  }

  Future<void> _saveCategories(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKeyCategories, ids.toList());
  }

  Future<void> _saveDuration(int duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefKeyDuration, duration);
  }

  Future<void> _saveMinRating(double rating) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefKeyMinRating, rating);
  }

  Future<void> _saveLockedSlots(Set<String> slotKeys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKeyLockedSlots, slotKeys.toList());
  }

  bool _passesMinRatingFilter(Recipe recipe) {
    final rating = recipe.rating;
    // Recettes non notées (0) toujours autorisées, quel que soit le minimum choisi.
    if (rating <= 0) return true;
    return rating >= _selectedMinRating;
  }

  List<Recipe> _applyPlannerRecipeFilters(List<Recipe> recipes) {
    final validSelectedCategories =
        _selectedCategories.where((id) => _categoryDataById.containsKey(id)).toSet();

    final categoryFiltered = validSelectedCategories.isEmpty
        ? recipes
        : recipes
            .where(
              (r) => r.categoryIds.any((c) => validSelectedCategories.contains(c)),
            )
            .toList();

    return categoryFiltered.where(_passesMinRatingFilter).toList();
  }

  String _minRatingValueLabel() {
    if (_selectedMinRating <= 0) return 'Toutes (inclut non notées)';
    return '≥ ${_selectedMinRating.toInt()}/5 (+ non notées)';
  }

  Future<void> _saveMinRatingAndApply(double rating) async {
    if (mounted) setState(() => _selectedMinRating = rating);
    await _saveMinRating(rating);
  }

  /// Charge les noms des utilisateurs du groupe dans [_userNames].
  /// Indépendant des autres chargements pour être résilient aux exceptions.
  Future<void> _loadUserNames() async {
    // Garde : si les noms sont déjà chargés, pas besoin de relire Firestore.
    if (_userNames.isNotEmpty) return;
    // Les deux sources sont indépendantes : on les lance en parallèle.
    final usersFuture = FirebaseUserRepository().getUsers();
    final servingsFuture = _userServingRepo.fetchAllGroupServings();
    try {
      final realUsers = await usersFuture;
      for (final u in realUsers) {
        if (u.name.isNotEmpty) _userNames[u.id] = u.name;
      }
    } catch (_) {}
    // Fallback depuis les servings (userName stocké dans recipeServings)
    try {
      final servingsForNames = await servingsFuture;
      for (final s in servingsForNames) {
        if (s.userName.isNotEmpty && s.userName != s.userId) {
          // Toujours mettre à jour : les servings peuvent avoir un nom plus récent
          _userNames[s.userId] = s.userName;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMostRecentMealPlanAndHistory() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      // Lancer noms, recettes et plans en parallèle — indépendants les uns des autres.
      final userNamesFuture = _loadUserNames();
      final recipesFuture = _loadRecipes(forceRefresh: true);
      final plansFuture = _mealPlanRepo.getAllMealPlans();
      // Load recipe count to calculate the history window size
      final allRecipes = await recipesFuture;
      _maxHistoryDays = allRecipes.length;

      final plans = await plansFuture;
      await userNamesFuture;
      if (plans.isNotEmpty) {
        plans.sort((a, b) => b.startDate.compareTo(a.startDate));
        final loadedPlan = plans.first;
        // The plan already contains all card-display data (description, category…)
        // persisted in Firestore — no recipeMap enrichment needed.
        _generatedMealPlan = loadedPlan;
        
        // Restore context from the plan
        if (loadedPlan.selectedCategories.isNotEmpty) {
          _selectedCategories = loadedPlan.selectedCategories.toSet();
        }
        // Note: pantry items are loaded from the dedicated pantry repository
        // (_loadPantryFromRepository), not from the plan snapshot, so that
        // the header always reflects the current fridge/pantry state.

        // Set today as selected if it is within the plan range
        final today = DateTime.now();
        final planStart = _generatedMealPlan!.startDate;
        final planEnd = planStart.add(
          Duration(days: _generatedMealPlan!.durationDays - 1),
        );
        if (!today.isBefore(planStart) && !today.isAfter(planEnd)) {
          // Aujourd'hui est dans la plage du plan
          _selectedMealDate = today;
          _focusedDay = today;
        } else if (today.isAfter(planEnd)) {
          // Plan terminé - se positionner sur le dernier jour
          _selectedMealDate = planEnd;
          _focusedDay = planEnd;
        } else {
          // Plan pas encore démarré - se positionner sur le premier jour
          _selectedMealDate = planStart;
          _focusedDay = planStart;
        }
        _calendarFormat = null; // Reset to recalculate format
        // Lecture rapide de l'historique existant et snapshot en parallèle.
        final historyFuture = _historyRepo.getHistory();
        final snapshotFuture = FirebasePantrySnapshotRepository.instance.get();
        _mealHistory = await historyFuture;
        // Planifie silencieusement les notifications (pour tous les utilisateurs)
        _autoScheduleNotifications(loadedPlan).ignore();

        // Charger le snapshot frigo/placard figé de ce plan
        try {
          final snapshot = await snapshotFuture;
          if (mounted) setState(() => _pantrySnapshot = snapshot);
        } catch (_) {}
      } else {
        // Pas de plan — charger uniquement l'historique
        _mealHistory = await _historyRepo.getHistory();
      }
      // History-only mode: if no plan loaded, initialise selected date from history
      if (_generatedMealPlan == null && _mealHistory.isNotEmpty && _selectedMealDate == null) {
        final sortedDates = _mealHistory.keys.toList()..sort((a, b) => b.compareTo(a));
        _selectedMealDate = sortedDates.first;
        _focusedDay = sortedDates.first;
        _calendarFormat = CalendarFormat.month;
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    // Mise à jour de l'historique en arrière-plan : inscrit les repas passés du plan
    // dans l'historique et déduit les ingrédients du frigo/placard.
    // Cette opération peut nécessiter de nombreuses écritures Firestore (une par jour
    // passé non encore enregistré), c'est pourquoi elle est découplée du chargement
    // initial pour éviter de bloquer l'affichage du plan.
    if (_generatedMealPlan != null) {
      _historyRepo
          .updateHistoryFromPlan(_generatedMealPlan, _maxHistoryDays)
          .then((updatedHistory) {
        if (mounted) setState(() => _mealHistory = updatedHistory);
      }).ignore();
    }
  }

  Future<List<Recipe>> _loadRecipes({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedRecipes != null) return _cachedRecipes!;
    _cachedRecipes = await FirebaseRecipeRepository().fetchAllRecipes();
    return _cachedRecipes!;
  }

  double _currentRecipeRating(Recipe recipe) {
    final cachedRecipes = _cachedRecipes;
    if (cachedRecipes == null) return recipe.rating;
    for (final cached in cachedRecipes) {
      if (cached.id == recipe.id) return cached.rating;
    }
    return recipe.rating;
  }

  /// Invalide le cache recettes (à appeler après ajout/modification/suppression).
  void _invalidateRecipeCache() => _cachedRecipes = null;

  Future<List<UserRecipeServing>> _loadServings() async {
    return _userServingRepo.fetchAllGroupServings();
  }

  Future<String> _saveMealPlan(MealPlan plan) async {
    setState(() => _isLoading = true);
    try {
      final savedId = await _mealPlanRepo.saveMealPlan(plan);
      
      // Update shopping list (pass pantryItems so they are subtracted from the list)
      final planForShoppingList = MealPlan(
        id: savedId,
        startDate: plan.startDate,
        durationDays: plan.durationDays,
        meals: plan.meals,
        createdAt: plan.createdAt,
        pantryItems: plan.pantryItems,
        selectedCategories: plan.selectedCategories,
        leftoverUserOrder: plan.leftoverUserOrder,
      );
      
      await ShoppingListGenerator().generateAndSaveShoppingList(planForShoppingList);

      if (!mounted) return savedId;
      // Removed the saved snackbar confirmation
      return savedId;
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
