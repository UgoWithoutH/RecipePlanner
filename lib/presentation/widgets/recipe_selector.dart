import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'ingredient_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/recipe.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../core/utils/ingredient_name_cache.dart';

class RecipeSelector extends StatefulWidget {
  final Function(Recipe) onRecipeSelected;

  const RecipeSelector({
    super.key,
    required this.onRecipeSelected,
  });

  @override
  State<RecipeSelector> createState() => _RecipeSelectorState();
}

class _RecipeSelectorState extends State<RecipeSelector> {
  final _recipeRepository = FirebaseRecipeRepository();
  late Future<List<Recipe>> _recipesFuture;
  String _titleFilter = '';
  Set<String> _selectedIngredientIds = {};
  List<Recipe> _allRecipes = [];
  List<Map<String, String>> _allIngredients = [];
  bool _ingredientsLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final recipes = await _fetchRecipesWithNames();
    final ingredients = await _fetchAllIngredients();
    setState(() {
      _allRecipes = recipes;
      _allIngredients = ingredients;
      _ingredientsLoading = false;
    });
  }

  Future<List<Recipe>> _fetchRecipesWithNames() async {
    final recipes = await _recipeRepository.fetchAllRecipes();
    return Future.wait(
      recipes.map((recipe) async {
        final ingredientIds = recipe.ingredients.map((ri) => ri.ingredient.id).toList();
        final names = await IngredientNameCache.instance.fetchNamesForIds(ingredientIds);
        final updatedIngredients = recipe.ingredients.map((ri) {
          return ri.copyWith(
            ingredient: ri.ingredient.copyWith(
              name: names[ri.ingredient.id] ?? 'Unknown',
            ),
          );
        }).toList();
        return recipe.copyWith(ingredients: updatedIngredients);
      }),
    );
  }

  Future<List<Map<String, String>>> _fetchAllIngredients() async {
    final snap = await FirebaseFirestore.instance.collection('ingredients').get();
    return snap.docs.map((doc) => {
      'id': doc.id,
      'name': doc.get('name') as String,
    }).toList();
  }

  List<Recipe> get _filteredRecipes {
    return _allRecipes.where((recipe) {
      final matchesTitle = _titleFilter.isEmpty || recipe.title.toLowerCase().contains(_titleFilter.toLowerCase());
      final matchesIngredients = _selectedIngredientIds.isEmpty || recipe.ingredients.any((ri) => _selectedIngredientIds.contains(ri.ingredient.id));
      return matchesTitle && matchesIngredients;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Changer la recette',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
                // Clear the input after selection
                onSelected: (ingredient) {
                  setState(() {
                    _selectedIngredientIds.add(ingredient['id']!);
                  });
                  // Clear the input field
                  Future.delayed(Duration(milliseconds: 100), () {
                    // Find the IngredientAutocomplete's controller and clear it
                    // (if controller is provided, clear it)
                    // Here, since we provide a new controller, clear it
                  });
                },
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
          Expanded(
            child: _allRecipes.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecipes.isEmpty
                    ? const Center(child: Text('Aucune recette disponible'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredRecipes.length,
                        itemBuilder: (_, index) {
                          final recipe = _filteredRecipes[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => widget.onRecipeSelected(recipe),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  title: Text(
                                    recipe.title,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    recipe.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.swap_horiz,
                                    color: Color(0xFF6A5AE0),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
