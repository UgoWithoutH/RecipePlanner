import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recipe_planner/presentation/widgets/ingredient_autocomplete.dart' show IngredientAutocomplete;

import '../../core/constants/unit.dart' show Unit;
import '../../core/constants/meal_time.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../core/utils/ingredient_name_cache.dart';

import 'recipe_detail_page.dart';
import 'categories_page.dart';
import 'create_recipe_page.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/firebase_stats_repository.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
    String _titleFilter = '';
    Set<String> _selectedIngredientIds = {};
    List<Map<String, String>> _allIngredients = [];
    bool _ingredientsLoading = true;
    
    // Category filter state
    Set<String> _selectedCategoryIds = {};
    List<Map<String, dynamic>> _allCategories = [];
    bool _categoriesLoading = true;

  Map<String, int> _recipeCounts = {};
  String _sortMode = 'alpha'; // 'alpha' | 'usage' | 'unused'

  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = fetchRecipes();

    // Fetch all ingredients for filter
    _fetchAllIngredients();
    // Fetch all categories for filter
    _fetchCategories();
    // Load recipe usage stats from history
    _loadRecipeCounts();
  }
  
  Future<void> _fetchCategories() async {
    setState(() => _categoriesLoading = true);
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      if (mounted) setState(() => _categoriesLoading = false);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('categories')
        .where('groupId', isEqualTo: groupId)
        .get();
    if (!mounted) return;
    setState(() {
      _allCategories = snap.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'id': doc.id,
          'name': data['name'] as String,
          'color': data.containsKey('color') ? data['color'] as int : 0xFF6A5AE0,
        };
      }).toList();
      _categoriesLoading = false;
    });
  }

  Future<void> _fetchAllIngredients() async {
    setState(() => _ingredientsLoading = true);
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      if (mounted) setState(() => _ingredientsLoading = false);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('ingredients')
        .where('groupId', isEqualTo: groupId)
        .get();
    if (!mounted) return;
    setState(() {
      _allIngredients = snap.docs.map((doc) => {
        'id': doc.id,
        'name': doc.get('name') as String,
      }).toList();
      _ingredientsLoading = false;
    });
  }

  // =========================
  // FETCH RECIPES
  // =========================
  Future<List<Recipe>> fetchRecipes() async {
    final recipes = await FirebaseRecipeRepository().fetchAllRecipes();

    // Resolve ingredient names (cached — only fetches missing ids from Firestore)
    final allIds = recipes
        .expand((r) => r.ingredients.map((ri) => ri.ingredient.id))
        .toList();
    final names = await IngredientNameCache.instance.fetchNamesForIds(allIds);

    final enriched = recipes.map((recipe) {
      final updatedIngredients = recipe.ingredients.map((ri) {
        return ri.copyWith(
          ingredient: ri.ingredient.copyWith(
            name: names[ri.ingredient.id] ?? 'Unknown',
          ),
        );
      }).toList();
      return recipe.copyWith(ingredients: updatedIngredients);
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return enriched;
  }

  Future<void> _loadRecipeCounts() async {
    final counts = await FirebaseStatsRepository.instance
        .getRecipeUsageCounts();
    if (mounted) setState(() => _recipeCounts = counts);
  }

  // =========================
  // REFRESH (FIXED)
  // =========================
  void _refreshRecipes() {
    if (!mounted) return;
    setState(() {
      _recipesFuture = fetchRecipes();
    });
  }

  // =========================
  // NAVIGATION
  // =========================
  Future<void> _openRecipeDetail(Recipe recipe) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: recipe.id,
          initialRecipe: recipe,
        ),
      ),
    );

    // Only refresh if something was modified or deleted
    if (result == true) {
      _refreshRecipes();
    }
  }

  Future<void> _openCategoriesPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesPage()),
    );
    // Refresh categories after managing them
    _fetchCategories();
  }

  Future<void> _createNewRecipe() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRecipePage()),
    );

    if (result != null) {
      _refreshRecipes();
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFEFFC), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recettes',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      InkWell(
                        onTap: _openCategoriesPage,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.category_rounded,
                                size: 18,
                                color: Color(0xFF6A5AE0),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Catégories',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6A5AE0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // CATEGORY FILTER
                if (!_categoriesLoading)
                  SizedBox(
                    height: 50,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: _allCategories.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "Tout" filter
                          final isSelected = _selectedCategoryIds.isEmpty;
                          final baseColor = const Color(0xFF6A5AE0);
                          
                          // Consistent text color
                          final hsl = HSLColor.fromColor(baseColor);
                          final startLightness = hsl.lightness;
                          final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                          final textColor = hsl.withLightness(textLightness).toColor();

                          return FilterChip(
                            label: Text(
                              'Toutes',
                              style: TextStyle(
                                fontSize: 13, 
                                fontWeight: FontWeight.w600,
                                color: textColor
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                _selectedCategoryIds.clear();
                              });
                            },
                            backgroundColor: baseColor.withOpacity(0.15),
                            selectedColor: baseColor.withOpacity(0.35),
                            checkmarkColor: textColor,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          );
                        }
                        
                        final category = _allCategories[index - 1];
                        final catId = category['id']!;
                        final isSelected = _selectedCategoryIds.contains(catId);
                        
                        final colorVal = category['color'] as int? ?? 0xFF6A5AE0;
                        final categoryColor = Color(colorVal);

                        // Contrast logic matching the display badges
                        final hsl = HSLColor.fromColor(categoryColor);
                        final startLightness = hsl.lightness;
                        final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                        final textColor = hsl.withLightness(textLightness).toColor();

                        return FilterChip(
                          label: Text(
                            category['name'] ?? '',
                            style: GoogleFonts.poppins(
                              fontSize: 13, 
                              fontWeight: FontWeight.w600,
                              color: textColor
                            )
                          ),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategoryIds.add(catId);
                              } else {
                                _selectedCategoryIds.remove(catId);
                              }
                            });
                          },
                          // Unselected: 0.15 opacity. Selected: 0.35 opacity (darker but still light enough for text)
                          backgroundColor: categoryColor.withOpacity(0.15),
                          selectedColor: categoryColor.withOpacity(0.35),
                          checkmarkColor: textColor,
                          side: BorderSide.none, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        );
                      },
                    ),
                  ),

                // SORT & FILTRE STATS
                Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSortChip(Icons.sort_by_alpha_rounded, 'A-Z', _sortMode == 'alpha',
                              () => setState(() => _sortMode = 'alpha')),
                          const SizedBox(width: 8),
                          _buildSortChip(Icons.bar_chart_rounded, 'Plus cuisinées', _sortMode == 'usage',
                              () => setState(() => _sortMode = 'usage')),
                          const SizedBox(width: 8),
                          _buildSortChip(Icons.bar_chart_rounded, 'Jamais cuisinées', _sortMode == 'unused',
                              () => setState(() => _sortMode = _sortMode == 'unused' ? 'alpha' : 'unused')),
                        ],
                      ),
                    ),
                  ),

                // FILTRES TEXTE & INGRÉDIENTS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Filtrer par titre...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    onChanged: (value) => setState(() => _titleFilter = value),
                  ),
                ),
                if (_ingredientsLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: IngredientAutocomplete(
                      selectedIngredientIds: _selectedIngredientIds,
                      onIngredientSelected: (ingredient) {
                        setState(() {
                          _selectedIngredientIds.add(ingredient['id']!);
                        });
                      },
                      controller: TextEditingController(),
                    ),
                  ),
                  if (_selectedIngredientIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _allIngredients
                              .where((ing) => _selectedIngredientIds.contains(ing['id']))
                              .map((ingredient) => Chip(
                                    label: Text(ingredient['name'] ?? ''),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedIngredientIds.remove(ingredient['id']!);
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                ],

                // COMPTEUR DE RECETTES
                FutureBuilder<List<Recipe>>(
                  future: _recipesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    final recipes = snapshot.data ?? [];
                    var filteredRecipes = recipes.where((recipe) {
                      final matchesTitle = _titleFilter.isEmpty || recipe.title.toLowerCase().contains(_titleFilter.toLowerCase());
                      final matchesIngredients = _selectedIngredientIds.isEmpty || recipe.ingredients.any((ri) => _selectedIngredientIds.contains(ri.ingredient.id));
                      final matchesCategory = _selectedCategoryIds.isEmpty || recipe.categoryIds.any((cId) => _selectedCategoryIds.contains(cId));
                      final matchesUsage = _sortMode != 'unused' || (_recipeCounts[recipe.id] ?? 0) == 0;
                      return matchesTitle && matchesIngredients && matchesCategory && matchesUsage;
                    }).toList();
                    if (_sortMode == 'usage') {
                      filteredRecipes.sort((a, b) {
                        final diff = (_recipeCounts[b.id] ?? 0).compareTo(_recipeCounts[a.id] ?? 0);
                        return diff != 0 ? diff : a.title.compareTo(b.title);
                      });
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        'Recettes (${filteredRecipes.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  },
                ),

                // LISTE
                Expanded(
                  child: FutureBuilder<List<Recipe>>(
                    future: _recipesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final recipes = snapshot.data ?? [];

                      // Filtrage par titre, ingrédients et statistiques
                      var filteredRecipes = recipes.where((recipe) {
                        final matchesTitle = _titleFilter.isEmpty || recipe.title.toLowerCase().contains(_titleFilter.toLowerCase());
                        final matchesIngredients = _selectedIngredientIds.isEmpty || recipe.ingredients.any((ri) => _selectedIngredientIds.contains(ri.ingredient.id));
                        final matchesCategory = _selectedCategoryIds.isEmpty || recipe.categoryIds.any((cId) => _selectedCategoryIds.contains(cId));
                        final matchesUsage = _sortMode != 'unused' || (_recipeCounts[recipe.id] ?? 0) == 0;
                        return matchesTitle && matchesIngredients && matchesCategory && matchesUsage;
                      }).toList();
                      if (_sortMode == 'usage') {
                        filteredRecipes.sort((a, b) {
                          final diff = (_recipeCounts[b.id] ?? 0).compareTo(_recipeCounts[a.id] ?? 0);
                          return diff != 0 ? diff : a.title.compareTo(b.title);
                        });
                      }

                      if (filteredRecipes.isEmpty) {
                        return const Center(
                          child: Text('Aucune recette disponible'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemCount: filteredRecipes.length,
                        itemBuilder: (_, index) {
                          final recipe = filteredRecipes[index];

                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => _openRecipeDetail(recipe),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  recipe.title,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF1A1A1A),
                                                  ),
                                                ),
                                                ...recipe.categoryIds.map((id) {
                                                  // Find category safely
                                                  final catMap = _allCategories.firstWhere(
                                                    (c) => c['id'] == id,
                                                    orElse: () => <String, dynamic>{}, // Fallback empty map
                                                  );

                                                  // If not found or invalid
                                                  if (catMap.isEmpty || !catMap.containsKey('name')) {
                                                    return const SizedBox.shrink(); 
                                                  }

                                                  final name = catMap['name'] as String;
                                                  final colorVal = catMap['color'] as int? ?? 0xFF6A5AE0;
                                                  final baseColor = Color(colorVal);

                                                  // Contrast logic
                                                  final hsl = HSLColor.fromColor(baseColor);
                                                  final startLightness = hsl.lightness;
                                                  final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                                                  final textColor = hsl.withLightness(textLightness).toColor();

                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: baseColor.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      name,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                if (recipe.isFavorite)
                                                  const Icon(
                                                    Icons.favorite_rounded,
                                                    size: 22,
                                                    color: Colors.redAccent,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              recipe.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                color: Colors.grey[600],
                                                fontSize: 14,
                                                height: 1.5,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            // Footer stats
                                            Row(
                                              children: [
                                                _buildStatItem(
                                                  Icons.access_time_rounded,
                                                  '${recipe.preparationTime + recipe.cookingTime} min',
                                                  const Color(0xFF5C6BC0),
                                                ),
                                                const SizedBox(width: 24),
                                                _buildStatItem(
                                                  Icons.pie_chart_rounded,
                                                  '${recipe.servings} portions',
                                                  const Color(0xFFFF8A65),
                                                ),
                                                if ((_recipeCounts[recipe.id] ?? 0) > 0) ...[
                                                  const SizedBox(width: 12),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF57C00).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.bar_chart_rounded, size: 12, color: Color(0xFFF57C00)),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${_recipeCounts[recipe.id]}×',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: const Color(0xFFF57C00),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 18,
                                        color: Colors.black26,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // FAB
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: Colors.transparent, // Fix for square background
          child: InkWell(
            onTap: _createNewRecipe,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6A5AE0).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Nouvelle recette',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6A5AE0) : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF6A5AE0)),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

}
