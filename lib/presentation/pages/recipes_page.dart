import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  // Future for fetching recipes
  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = fetchRecipes();
  }

  /// Fetch recipes from Firestore and resolve ingredient names via cache
  Future<List<Recipe>> fetchRecipes() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .get();

    return Future.wait(snapshot.docs.map((doc) async {
      final data = doc.data();
      final ingredientsData = data['ingredients'] as List<dynamic>? ?? [];

      // Fetch ingredient names by their IDs
      final ingredientIds = ingredientsData.map((i) => i['ingredientId'] as String).toList();
      final names = await IngredientNameCache.instance.fetchNamesForIds(ingredientIds);

      // Build list of RecipeIngredient objects
      final ingredients = ingredientsData.map((i) {
        final id = i['ingredientId'];
        final name = names[id] ?? 'Unknown';
        return RecipeIngredient(
          ingredient: Ingredient(id: id, name: name),
          quantity: (i['quantity'] as num).toDouble(),
          unit: Unit.values.firstWhere((u) => u.label == i['unit'], orElse: () => Unit.g),
          notes: i['notes'],
        );
      }).toList();

      // Build Recipe object
      final id = (data['id'] as String?)?.isNotEmpty == true ? data['id'] as String : doc.id;

      return Recipe(
        id: id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
        cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
        servings: (data['servings'] as num?)?.toInt() ?? 1, // Display servings
        category: data['category'] ?? '',
        ingredients: ingredients,
        instructions: List<String>.from(data['instructions'] ?? []),
        createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        isFavorite: data['isFavorite'] ?? false,
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList());
  }

  /// Refresh the recipes list safely
  Future<void> _refreshRecipes() async {
    final recipes = await fetchRecipes(); // Fetch asynchronously first
    if (!mounted) return;
    setState(() {
      // Update state synchronously
      _recipesFuture = Future.value(recipes);
    });
  }

  /// Open recipe detail page and refresh recipes after returning
  Future<void> _openRecipeDetail(Recipe recipe) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeDetailPage(recipe: recipe)),
    );
    await _refreshRecipes();
  }

  /// Open categories page
  void _openCategoriesPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesPage()),
    );
  }

  /// Open create recipe page and refresh recipes after creation
  Future<void> _createNewRecipe() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRecipePage()),
    );

    if (result != null && result is Recipe) {
      await _refreshRecipes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Categories',
            onPressed: _openCategoriesPage,
          ),
        ],
      ),
      body: FutureBuilder<List<Recipe>>(
        future: _recipesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final recipes = snapshot.data ?? [];
          if (recipes.isEmpty) {
            return const Center(child: Text('No recipes available'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: recipes.length,
            itemBuilder: (_, index) {
              final recipe = recipes[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: Text(
                    recipe.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text('Servings: ${recipe.servings}'), // Display servings
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _openRecipeDetail(recipe),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewRecipe,
        tooltip: 'Create Recipe',
        child: const Icon(Icons.add),
      ),
    );
  }
}