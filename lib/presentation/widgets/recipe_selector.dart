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

  @override
  void initState() {
    super.initState();
    _recipesFuture = _fetchRecipesWithNames();
  }

  Future<List<Recipe>> _fetchRecipesWithNames() async {
    final recipes = await _recipeRepository.fetchAllRecipes();

    // Fetch ingredient names for all recipes
    return Future.wait(
      recipes.map((recipe) async {
        final ingredientIds = recipe.ingredients
            .map((ri) => ri.ingredient.id)
            .toList();

        final names = await IngredientNameCache.instance
            .fetchNamesForIds(ingredientIds);

        // Update ingredients with their names
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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              'Changer la recette',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Recipe>>(
              future: _recipesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final recipes = snapshot.data ?? [];

                if (recipes.isEmpty) {
                  return const Center(child: Text('Aucune recette disponible'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: recipes.length,
                  itemBuilder: (_, index) {
                    final recipe = recipes[index];
                    return GestureDetector(
                      onTap: () => widget.onRecipeSelected(recipe),
                      child: Container(
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
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
