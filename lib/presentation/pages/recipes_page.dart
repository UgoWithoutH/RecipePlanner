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

        final names = await IngredientNameCache.instance
            .fetchNamesForIds(ingredientIds);

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
          preparationTime:
              (data['preparationTime'] as num?)?.toInt() ?? 0,
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
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(recipe: recipe),
      ),
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
      body: SafeArea(
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
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final recipes = snapshot.data ?? [];

                  if (recipes.isEmpty) {
                    return const Center(
                      child: Text('Aucune recette disponible'),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: recipes.length,
                    itemBuilder: (_, index) {
                      final recipe = recipes[index];

                      return GestureDetector(
                        onTap: () => _openRecipeDetail(recipe),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            title: Text(
                              recipe.title,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  recipe.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Portions : ${recipe.servings}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[500],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.black38,
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

      // FAB
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          elevation: 6,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A5AE0), Color(0xFF4FC3F7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
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
}