import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/unit.dart' show Unit;
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../core/utils/ingredient_name_cache.dart';

import 'recipe_detail_page.dart';
import 'categories_page.dart';
import 'create_recipe_page.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = fetchRecipes();
  }

  // =========================
  // FETCH RECIPES
  // =========================
  Future<List<Recipe>> fetchRecipes() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .get();

    return Future.wait(
      snapshot.docs.map((doc) async {
        final data = doc.data();
        final ingredientsData = data['ingredients'] as List<dynamic>? ?? [];

        final ingredientIds = ingredientsData
            .map((i) => i['ingredientId'] as String)
            .toList();

        final names = await IngredientNameCache.instance.fetchNamesForIds(
          ingredientIds,
        );

        final ingredients = ingredientsData.map((i) {
          final id = i['ingredientId'];
          final name = names[id] ?? 'Unknown';

          return RecipeIngredient(
            ingredient: Ingredient(id: id, name: name),
            quantity: (i['quantity'] as num).toDouble(),
            unit: Unit.values.firstWhere(
              (u) => u.label == i['unit'],
              orElse: () => Unit.g,
            ),
            notes: i['notes'],
          );
        }).toList();

        final id = (data['id'] as String?)?.isNotEmpty == true
            ? data['id'] as String
            : doc.id;

        return Recipe(
          id: id,
          title: data['title'] ?? '',
          description: data['description'] ?? '',
          preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
          cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
          servings: (data['servings'] as num?)?.toInt() ?? 1,
          category: data['category'] ?? '',
          ingredients: ingredients,
          instructions: List<String>.from(data['instructions'] ?? []),
          createdAt:
              DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
          isFavorite: data['isFavorite'] ?? false,
          rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        );
      }),
    );
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
      MaterialPageRoute(builder: (_) => RecipeDetailPage(recipe: recipe)),
    );

    if (result == true) {
      _refreshRecipes();
    }
  }

  void _openCategoriesPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesPage()),
    );
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.category,
                        color: Color(0xFF6A5AE0),
                      ),
                    ),
                  ),
                ],
              ),
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

                  if (recipes.isEmpty) {
                    return const Center(
                      child: Text('Aucune recette disponible'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    separatorBuilder: (_, __) => const SizedBox(height: 20),
                    itemCount: recipes.length,
                    itemBuilder: (_, index) {
                      final recipe = recipes[index];

                      return Container(
                        decoration: BoxDecoration(
                          // color moved to Material for InkWell effect
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
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                recipe.title,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(
                                                    0xFF1A1A1A,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (recipe.isFavorite) ...[
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.favorite_rounded,
                                                size: 22,
                                                color: Colors.redAccent,
                                              ),
                                            ],
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
                                              const Color(
                                                0xFF5C6BC0,
                                              ), // Soft indigo
                                            ),
                                            const SizedBox(width: 24),
                                            _buildStatItem(
                                              Icons
                                                  .pie_chart_rounded, // Icon "part"
                                              '${recipe.servings} portions',
                                              const Color(
                                                0xFFFF8A65,
                                              ), // Soft deep orange
                                            ),
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
          borderRadius: BorderRadius.circular(24),
          elevation: 6,
          child: Ink(
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
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _createNewRecipe,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
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
