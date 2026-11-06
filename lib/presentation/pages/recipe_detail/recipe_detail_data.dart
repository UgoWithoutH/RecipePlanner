// ignore_for_file: invalid_use_of_protected_member
part of 'recipe_detail_page.dart';

extension _RecipeDetailData on _RecipeDetailPageState {
  Future<void> _loadUsageCount() async {
    try {
      final counts = await FirebaseStatsRepository.instance.getRecipeUsageCounts();
      final id = widget.recipeId;
      if (mounted) setState(() => _usageCount = counts[id] ?? 0);
    } catch (_) {}
  }

  Future<void> _saveRating(double newRating) async {
    if (_recipe == null || _recipe!.id.isEmpty) return;
    final previousRating = _recipe!.rating;
    final updated = _recipe!.copyWith(rating: newRating);
    setState(() => _recipe = updated);
    if (newRating > 0) {
      _showTransientRatingLabel(newRating);
    } else {
      _ratingFeedbackTimer?.cancel();
      if (mounted) {
        setState(() => _showRatingFeedback = false);
      }
    }
    try {
      await FirebaseFirestore.instance
          .collection('recipes')
          .doc(_recipe!.id)
          .update({'rating': newRating});
      FirebaseRecipeRepository.invalidateCache();
      _wasModified = true;
    } catch (_) {
      // Revert on failure
      if (mounted) {
        setState(() => _recipe = _recipe!.copyWith(rating: previousRating));
      }
    }
  }

  Future<void> _checkIfAlreadyImported() async {
    if (_recipe == null) return;
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null || !mounted) return;
    final snap = await FirebaseFirestore.instance
        .collection('recipes')
        .where('groupId', isEqualTo: groupId)
        .where('title', isEqualTo: _recipe!.title)
        .limit(1)
        .get();
    if (mounted) setState(() => _isAlreadyImported = snap.docs.isNotEmpty);
  }

  Future<void> _loadIngredientTypes() async {
    try {
      final types = await _ingredientTypeRepo.getTypes();
      if (mounted) setState(() => _ingredientTypes = types);
    } catch (_) {}
  }

  Future<void> _loadFullRecipe() async {
    if (!mounted) return;
    setState(() => _isLoadingRecipe = true);
    try {
      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic>? data;
      String? docId;

      // 1. Direct document fetch by ID (most reliable path)
      final directDoc =
          await firestore.collection('recipes').doc(widget.recipeId).get();
      if (directDoc.exists) {
        data = directDoc.data() as Map<String, dynamic>;
        docId = directDoc.id;
      } 
      
      // 2. Fallback: query by stored 'id' field
      if (data == null) {
        final query = await firestore
            .collection('recipes')
            .where('id', isEqualTo: widget.recipeId)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          data = query.docs.first.data() as Map<String, dynamic>;
          docId = query.docs.first.id;
        }
      }

      // 3. Last resort: query by TITLE (exact or capitalized) — scoped to current group
      if (data == null && widget.initialRecipe != null) {
        final groupId = await GroupRepository.instance.getCurrentGroupId();
        // Try exact title first
        var titleQuery = await firestore
          .collection('recipes')
          .where('title', isEqualTo: widget.initialRecipe!.title)
          .where('groupId', isEqualTo: groupId)
          .limit(1)
          .get();
        
        // If failed, try capitalizing the first letter (seed data convention)
        if (titleQuery.docs.isEmpty && widget.initialRecipe!.title.isNotEmpty) {
          final t = widget.initialRecipe!.title;
          final capitalized = t[0].toUpperCase() + t.substring(1);
          if (capitalized != t) {
            titleQuery = await firestore
             .collection('recipes')
             .where('title', isEqualTo: capitalized)
             .where('groupId', isEqualTo: groupId)
             .limit(1)
             .get();
          }
        }

        if (titleQuery.docs.isNotEmpty) {
          data = titleQuery.docs.first.data() as Map<String, dynamic>;
          docId = titleQuery.docs.first.id; // Override ID with the new one
        }
      }

      if (data == null || !mounted) {
        // Could not load recipe from Firestore
        return;
      }

      // Parse ingredients — use null-safe id extraction to avoid cast errors
      final ingredientsData = (data['ingredients'] as List<dynamic>?) ?? [];

      final ingredientIds = ingredientsData
          .map((i) {
             if (i is Map<String, dynamic>) {
                return (i['ingredientId'] as String?) ?? '';
             }
             return '';
          })
          .where((id) => id.isNotEmpty)
          .toList();

      // Enrich ingredient names + fetch typeIds in parallel (independent queries)
      final namesFuture = ingredientIds.isNotEmpty
          ? IngredientNameCache.instance.fetchNamesForIds(ingredientIds)
          : Future.value(<String, String>{});
      final typeIdFuture = ingredientIds.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('ingredients')
              .where(FieldPath.documentId, whereIn: ingredientIds)
              .get()
          : Future.value(null);

      final names = await namesFuture;
      Map<String, String?> ingredientIdToTypeId = {};
      final typeIdSnap = await typeIdFuture;
      if (typeIdSnap != null) {
        for (final doc in typeIdSnap.docs) {
          final data = doc.data();
          ingredientIdToTypeId[doc.id] = data.containsKey('typeId') ? data['typeId'] as String? : null;
        }
      }

      final enriched = ingredientsData.map((i) {
        if (i is! Map<String, dynamic>) return null;
        final id = (i['ingredientId'] as String?) ?? '';
        // Prend le typeId Firestore si présent, sinon va le chercher dans la collection ingredients
        final typeId = i.containsKey('typeId') && i['typeId'] != null
            ? i['typeId'] as String?
            : ingredientIdToTypeId[id];
        return RecipeIngredient(
          ingredient: Ingredient(
            id: id,
            name: names[id] ?? (i['ingredientName'] as String? ?? ''),
            typeId: typeId,
          ),
          quantity: (i['quantity'] as num?)?.toDouble() ?? 0,
          unit: Unit.values.firstWhere(
            (u) => u.label == i['unit'] || u.name == i['unit'],
            orElse: () => Unit.g,
          ),
          notes: i['notes'] as String?,
        );
      }).whereType<RecipeIngredient>().toList();

      if (!mounted) return;
      
      final currentRecipe = _recipe;
      
        setState(() {
        _fullRecipeLoaded = true;
        _recipe = Recipe(
          // Preserve the original id used to find the recipe so that
          // subsequent saves / fetches keep working correctly.
          id: docId ?? widget.recipeId,
          title: data!['title'] as String? ?? currentRecipe?.title ?? '',
          description: data['description'] as String? ?? currentRecipe?.description ?? '',
          url: data['url'] as String? ?? currentRecipe?.url,
          preparationTime:
            (data['preparationTime'] as num?)?.toInt() ??
            currentRecipe?.preparationTime ?? 0,
          cookingTime:
            (data['cookingTime'] as num?)?.toInt() ?? currentRecipe?.cookingTime ?? 0,
          servings:
            (data['servings'] as num?)?.toInt() ?? currentRecipe?.servings ?? 1,
          categoryIds: (data['categoryIds'] != null ? List<String>.from(data['categoryIds']) : (data['category'] != null ? [data['category'] as String] : [])),
          ingredients: enriched,
          instructions: List<String>.from(data['instructions'] ?? []),
          createdAt:
            DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            currentRecipe?.createdAt ?? DateTime.now(),
          isFavorite: data['isFavorite'] as bool? ?? currentRecipe?.isFavorite ?? false,
          rating:
            (data['rating'] as num?)?.toDouble() ?? currentRecipe?.rating ?? 0.0,
          mealTime: MealTime.fromString(data['mealTime'] as String?),
        );
        // Update displayed category name once the full recipe is loaded
        if (_categories.isNotEmpty && _recipe != null) {
          _currentCategories = _categories.where((c) =>
            _recipe!.categoryIds.contains(c.id) || _recipe!.categoryIds.contains(c.name)
          ).toList();
        }
        });
      
      // Load secondary data if it wasn't loaded before
      _loadUserServings();
      _loadCategories();
      
    } catch (e, stack) {
      // Log the real error so it is visible in the debug console
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Impossible de charger les détails : $e', 
                    style: GoogleFonts.poppins(color: Colors.white)
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRecipe = false);
    }
  }

  Future<void> _loadUserServings() async {
    if (_recipe == null || _recipe!.id.isEmpty) return;
    try {
      final servings = await _userServingRepo.fetchServingsForRecipe(_recipe!.id);
      if (!mounted) return;
      setState(() {
        _userServings = servings;
        _isLoadingServings = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingServings = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (_recipe != null) {
          _currentCategories = _categories.where((c) =>
            _recipe!.categoryIds.contains(c.id) || _recipe!.categoryIds.contains(c.name)
          ).toList();
        }
      });
    } catch (_) {}
  }

  Future<void> _deleteRecipe() async {
    if (_recipe != null) {
      setState(() => _isDeleting = true);
      await FirebaseRecipeRepository().deleteRecipe(_recipe!.id);
    }
    if (mounted) Navigator.pop(context, true);
  }
}
