// ignore_for_file: invalid_use_of_protected_member
part of 'create_recipe_page.dart';

extension _CreateRecipeData on _CreateRecipePageState {
  Future<void> _loadIngredientTypes() async {
    try {
      final types = await _ingredientTypeRepo.getTypes() ?? [];
      if (mounted) setState(() => _ingredientTypes = types);
    } catch (_) {}
  }

  Future<void> _onServingsEditingDone() async {
    final newServings = int.tryParse(_servingsController.text);
    if (newServings == null || newServings <= 0) return;
    if (_previousServings <= 0 || newServings == _previousServings) {
      _previousServings = newServings;
      return;
    }
    if (_ingredients.isEmpty) {
      _previousServings = newServings;
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.scale_rounded, color: Color(0xFF6A5AE0), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Adapter les quantités ?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Vous passez de $_previousServings à $newServings portions. Voulez-vous mettre à jour les quantités des ingrédients en conséquence ?',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Non', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A5AE0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: Text('Oui, adapter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ratio = newServings / _previousServings;
      setState(() {
        for (int i = 0; i < _ingredients.length; i++) {
          final ri = _ingredients[i];
          _ingredients[i] = RecipeIngredient(
            ingredient: ri.ingredient,
            quantity: double.parse((ri.quantity * ratio).toStringAsFixed(2)),
            unit: ri.unit,
            notes: ri.notes,
          );
        }
      });
    }
    _previousServings = newServings;
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (mounted) setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  // _waitForTypesAndPrefill supprimé : remplacé par Future.wait dans initState

  void _prefillFromPreset(Map<String, dynamic> preset) {
    // Libérer le focus avant de modifier les controllers pour éviter RangeError
    FocusManager.instance.primaryFocus?.unfocus();

    _titleController.value = TextEditingValue(text: preset['title'] as String? ?? '');
    _descriptionController.value = TextEditingValue(text: preset['description'] as String? ?? '');
    _preparationTimeController.value = TextEditingValue(
        text: ((preset['preparationTime'] as num?)?.toInt() ?? 0).toString());
    _cookingTimeController.value = TextEditingValue(
        text: ((preset['cookingTime'] as num?)?.toInt() ?? 0).toString());
    _servingsController.value = TextEditingValue(
        text: ((preset['servings'] as num?)?.toInt() ?? 4).toString());

    // Match category names → IDs
    final presetCats =
        List<String>.from(preset['categories'] as List? ?? []);
    _selectedCategoryIds = _categories
        .where((c) => presetCats.contains(c.name))
        .map((c) => c.id)
        .toList();

    // Instructions
    _instructions
      ..clear()
      ..addAll(List<String>.from(preset['instructions'] as List? ?? []));

    // Ingredients
    _ingredients.clear();
    _pendingIngredients.clear();
    final rawIngredients = preset['ingredients'] as List? ?? [];
    for (final raw in rawIngredients) {
      final i = Map<String, dynamic>.from(raw as Map);
      final name = i['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final qty = (i['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitLabel = i['unit'] as String? ?? '';
      final typeName = i['type'] as String? ?? '';

      // Match unit label to Unit enum
      final unit = Unit.values.firstWhere(
        (u) => u.label == unitLabel || u.name == unitLabel,
        orElse: () => Unit.piece,
      );

      // Match type name to typeId
      final typeMatch = _ingredientTypes.firstWhere(
        (t) => t.name == typeName,
        orElse: () => IngredientType(id: '', name: '', color: 0xFFBDBDBD),
      );
      final typeId = typeMatch.id.isNotEmpty ? typeMatch.id : null;

      _pendingIngredients.add(PendingIngredient(
        name: name,
        typeId: typeId,
        quantity: qty,
        unit: unit,
        notes: null,
      ));
      _ingredients.add(RecipeIngredient(
        ingredient: Ingredient(id: '', name: name, typeId: typeId),
        quantity: qty,
        unit: unit,
        notes: null,
      ));
    }

    setState(() {});
  }

  Future<void> _loadUsers() async {
    final users = await _userRepo.getUsers();
    if (!mounted) return;
    setState(() => _users = users);
    // Init default servings (1 lunch + 1 dinner) for new recipes
    if (widget.recipe == null) {
      for (final user in users) {
        _userServings.putIfAbsent(user.id, () => UserRecipeServing(
          userId: user.id,
          recipeId: '',
          lunchServings: 1,
          dinnerServings: 1,
          userName: user.name,
          recipeTitle: '',
        ));
      }
    }
  }

  Future<void> _loadExistingServings() async {
    if (widget.recipe == null) return;

    final servings = await _userServingRepo.fetchServingsForRecipe(
      widget.recipe!.id,
    );

    if (!mounted) return;

    setState(() {
      for (var serving in servings) {
        _userServings[serving.userId] = serving;
      }
    });
  }

  Future<bool> _recipeTitleExists(String title, {String? excludeId}) async {
    final recipes = await _recipeRepo.fetchRecipesByTitle(
      title.trim().toLowerCase(),
    );
    if (excludeId != null) {
      return recipes.any((r) => r.id != excludeId);
    }
    return recipes.isNotEmpty;
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    if (await _recipeTitleExists(_titleController.text, excludeId: widget.recipe?.id)) {
      _showError('Une recette avec ce titre existe déjà dans le groupe');
      return;
    }

    if (_ingredients.isEmpty) {
      _showError('Ajoutez au moins un ingrédient');
      return;
    }

    // Vérifier que la somme des portions utilisateurs ne dépasse pas le nombre de portions de la recette (midi et soir séparément)
    final int recipeServings = int.tryParse(_servingsController.text) ?? 0;
    final int totalLunch = _selectedMealTime == MealTime.dinnerOnly
        ? 0
        : _userServings.values.fold(0, (sum, s) => sum + s.lunchServings);
    final int totalDinner = _selectedMealTime == MealTime.lunchOnly
        ? 0
        : _userServings.values.fold(0, (sum, s) => sum + s.dinnerServings);
    if (totalLunch > recipeServings || totalDinner > recipeServings) {
      final List<String> overflowParts = [];
      if (totalLunch > recipeServings) {
        overflowParts.add('le midi ($totalLunch portion${totalLunch > 1 ? 's' : ''})');
      }
      if (totalDinner > recipeServings) {
        overflowParts.add('le soir ($totalDinner portion${totalDinner > 1 ? 's' : ''})');
      }
      _showError(
        'La somme des portions dépasse le nombre de portions de la recette ($recipeServings) pour : ${overflowParts.join(' et ')}',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Créer les nouveaux ingrédients en parallèle et récupérer les IDs
      if (_pendingIngredients.isNotEmpty) {
        final creates = await Future.wait(
          _pendingIngredients.map((p) => _ingredientRepo.createIngredientWithType(p.name, p.typeId)),
        );
        for (int i = 0; i < _pendingIngredients.length; i++) {
          final pending = _pendingIngredients[i];
          final newId = creates[i];
          final idx = _ingredients.indexWhere(
            (ri) => ri.ingredient.id == '' && ri.ingredient.name == pending.name,
          );
          if (idx != -1) {
            final old = _ingredients[idx];
            _ingredients[idx] = RecipeIngredient(
              ingredient: Ingredient(id: newId, name: pending.name, typeId: pending.typeId),
              quantity: old.quantity,
              unit: old.unit,
              notes: old.notes,
            );
          }
        }
        _pendingIngredients.clear();
      }

      // 2. Sauvegarde la recette normalement
      String recipeId;
      final recipe = Recipe(
        id: widget.recipe?.id ?? '',
        title: _titleController.text.trim().toLowerCase(),
        description: _descriptionController.text,
        preparationTime: int.parse(_preparationTimeController.text),
        cookingTime: int.parse(_cookingTimeController.text),
        servings: int.parse(_servingsController.text),
        categoryIds: _selectedCategoryIds,
        ingredients: _ingredients,
        instructions: _instructions,
        createdAt: widget.recipe?.createdAt ?? DateTime.now(),
        mealTime: _selectedMealTime,
      );

      if (widget.recipe == null) {
        recipeId = await _recipeRepo.createRecipe(recipe);
      } else {
        await _recipeRepo.updateRecipe(recipe);
        recipeId = recipe.id;

        // Si mise à jour d'une recette : propager les changements aux plans existants
        // et regénérer leurs listes de courses en parallèle.
        final planRepo = FirebaseMealPlanRepository();
        final updatedPlans = await planRepo.updatePlansForRecipe(recipe);
        if (updatedPlans.isNotEmpty) {
          await Future.wait(
            updatedPlans.map((plan) => ShoppingListGenerator().generateAndSaveShoppingList(plan)),
          );
        }
      }

      // Sauvegarder les portions utilisateurs en parallèle
      await Future.wait(
        _userServings.values.map((s) => _userServingRepo.save(s.copyWith(recipeId: recipeId))),
      );

      if (!mounted) return;
      final recipeToReturn = recipe.copyWith(id: recipeId);
      Navigator.pop(context, recipeToReturn);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Erreur lors de la sauvegarde : $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE53935), // Less flashy red
        behavior:
            SnackBarBehavior.floating, // Floating creates the "bubble" effect
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        elevation: 4,
      ),
    );
  }
}
