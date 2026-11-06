// ignore_for_file: invalid_use_of_protected_member
part of 'ingredients_page.dart';

extension _IngredientsFilters on _IngredientsPageState {
  Future<void> _showRecipesForIngredient(String ingredientId, String ingredientName) async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    try {
      final groupSnap = await FirebaseFirestore.instance
          .collection('recipes')
          .where('groupId', isEqualTo: groupId)
          .get();
      docs = groupSnap.docs;
    } catch (_) {
      // Réseau indisponible ou erreur Firestore : on affiche la modale vide
    }
    if (!mounted) return;
    final groupRecipes = <Recipe>[];
    final Map<String, int> groupRecipeCounts = {};
    for (final doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final ingredients = data['ingredients'] as List<dynamic>? ?? [];
        if (ingredients.any((i) => i['ingredientId'] == ingredientId)) {
          final usage = (data['usageCount'] as num?)?.toInt() ?? 0;
          if (usage > 0) groupRecipeCounts[doc.id] = usage;
          final rawIngredients = data['ingredients'] as List<dynamic>? ?? [];
          final mappedIngredients = rawIngredients.map((i) {
            return RecipeIngredient(
              ingredient: Ingredient(id: i['ingredientId'] ?? '', name: '...'),
              quantity: (i['quantity'] as num?)?.toDouble() ?? 0.0,
              unit: Unit.values.firstWhere((u) => u.label == i['unit'], orElse: () => Unit.g),
              notes: i['notes'],
            );
          }).toList();
          groupRecipes.add(Recipe(
            id: doc.id,
            title: data['title'] ?? '',
            description: data['description'] ?? '',
            preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
            cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
            servings: (data['servings'] as num?)?.toInt() ?? 1,
            categoryIds: (data['categoryIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                ((data['category'] as String?)?.isNotEmpty == true ? [data['category'] as String] : []),
            ingredients: mappedIngredients,
            instructions: List<String>.from(data['instructions'] ?? []),
            createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
            isFavorite: data['isFavorite'] ?? false,
            rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
            mealTime: MealTime.fromString(data['mealTime'] as String?),
          ));
        }
      } catch (_) {
        // Données malformées pour cette recette, on l'ignore
      }
    }
    groupRecipes.sort((a, b) => a.title.compareTo(b.title));

    const double headerPx = 130;
    const double itemPx = 62;
    const double minFraction = 0.50;
    const double maxFraction = 0.95;
    final screenH = MediaQuery.of(context).size.height;
    final contentH = headerPx + groupRecipes.length * itemPx + 80;
    final initial = (contentH / screenH).clamp(minFraction, maxFraction);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipesForIngredientSheet(
        ingredientName: ingredientName,
        recipes: groupRecipes,
        recipeCounts: groupRecipeCounts,
        initialChildSize: initial,
        maxChildSize: maxFraction,
      ),
    );
  }

  Future<void> _openFiltersSheet() async {
    String tempSort = _sortMode;
    final tempTypes = Set<String>.from(_selectedTypeIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Filtres ingrédients',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.sort_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Tri',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort_by_alpha_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('A-Z'),
                            ],
                          ),
                          selected: tempSort == 'alpha',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'alpha'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bar_chart_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Plus utilisés'),
                            ],
                          ),
                          selected: tempSort == 'usage',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'usage'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.block_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Jamais utilisés'),
                            ],
                          ),
                          selected: tempSort == 'unused',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'unused'),
                        ),
                      ],
                    ),
                    if (_types.isNotEmpty) ...[const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.label_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Types',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Tous', style: TextStyle(fontWeight: FontWeight.w600)),
                            selected: tempTypes.isEmpty,
                            backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.15),
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(() => tempTypes.clear()),
                          ),
                          for (final type in _types)
                            FilterChip(
                              label: Text(
                                type.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              selected: tempTypes.contains(type.id),
                              backgroundColor: Color(type.color).withOpacity(0.15),
                              selectedColor: Color(type.color).withOpacity(0.35),
                              onSelected: (_) {
                                setStateSheet(() {
                                  if (tempTypes.contains(type.id)) {
                                    tempTypes.remove(type.id);
                                  } else {
                                    tempTypes.add(type.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setStateSheet(() {
                                tempSort = 'alpha';
                                tempTypes.clear();
                              });
                            },
                            child: Text(
                              'Réinitialiser',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _sortMode = tempSort;
                                _selectedTypeIds = tempTypes.toList();
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              'Appliquer',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _activeFiltersCount() {
    int count = 0;
    if (_sortMode != 'alpha') count++;
    if (_selectedTypeIds.isNotEmpty) count++;
    return count;
  }
}
