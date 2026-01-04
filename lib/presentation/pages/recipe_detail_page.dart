import 'package:flutter/material.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/entities/category.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_category_repository.dart';
import 'create_recipe_page.dart';

class RecipeDetailPage extends StatefulWidget {
  final Recipe recipe;

  const RecipeDetailPage({super.key, required this.recipe});

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Recipe _recipe;
  bool _isDeleting = false;

  // User servings
  List<UserRecipeServing> _userServings = [];
  bool _isLoadingServings = true;
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();

  // Categories
  List<Category> _categories = [];
  String? _categoryName;
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
    _loadUserServings();
    _loadCategories();
  }

  /// Load user portions for this recipe
  Future<void> _loadUserServings() async {
    if (_recipe.id.isEmpty) return; // safeguard

    try {
      final servings = await _userServingRepo.fetchServingsForRecipe(_recipe.id);
      if (mounted) {
        setState(() {
          _userServings = servings;
          _isLoadingServings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingServings = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading servings: $e')),
        );
      }
    }
  }

  /// Load categories to map ID -> Name
  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (!mounted) return;

      setState(() {
        _categories = categories;
        final cat = _categories.firstWhere(
          (c) => c.id == _recipe.category,
          orElse: () => Category(id: '', name: 'Unknown'),
        );
        _categoryName = cat.name;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _categoryName = _recipe.category);
      }
    }
  }

  /// Deletes the current recipe from Firestore
  Future<void> _deleteRecipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Recipe'),
        content: const Text('Are you sure you want to delete this recipe?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      final repo = FirebaseRecipeRepository();
      await repo.deleteRecipe(_recipe.id);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting recipe: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_recipe.title),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Recipe',
            onPressed: () async {
              final updatedRecipe = await Navigator.push<Recipe>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRecipePage(recipe: _recipe),
                ),
              );

              if (updatedRecipe != null) {
                setState(() => _recipe = updatedRecipe);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recipe updated successfully')),
                );
                _loadUserServings(); // reload in case servings were updated
                _loadCategories(); // reload category name
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Recipe',
            onPressed: _isDeleting ? null : _deleteRecipe,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                Text(
                  _recipe.description,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 16),

                // Category
                Row(
                  children: [
                    const Icon(Icons.category, size: 20, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      _categoryName ?? _recipe.category,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Prep time, Cook time, Servings
                Row(
                  children: [
                    const Icon(Icons.timer, size: 20, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Prep: ${_recipe.preparationTime} min'),
                    const SizedBox(width: 16),
                    const Icon(Icons.restaurant, size: 20, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Cook: ${_recipe.cookingTime} min'),
                    const SizedBox(width: 16),
                    const Icon(Icons.people, size: 20, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Servings: ${_recipe.servings}'),
                  ],
                ),
                const SizedBox(height: 24),

                // Ingredients
                const Text('Ingredients',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._recipe.ingredients.map(
                  (i) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(i.ingredient.name),
                      subtitle: i.notes != null ? Text(i.notes!) : null,
                      trailing: Text('${i.quantity} ${i.unit.label}'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Instructions
                const Text('Instructions',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._recipe.instructions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final step = entry.value;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text('${index + 1}',
                            style:
                                const TextStyle(color: Colors.white)),
                      ),
                      title: Text(step),
                    ),
                  );
                }),

                // -----------------------------
                // User Portions Section
                // -----------------------------
                const SizedBox(height: 24),
                const Text('User Portions',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                if (_isLoadingServings)
                  const Center(child: CircularProgressIndicator())
                else if (_userServings.isEmpty)
                  const Text('No servings recorded yet')
                else
                  Column(
                    children: _userServings.map((s) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(child: Text(s.userName)),
                              Text('Lunch: ${s.lunchServings}'),
                              const SizedBox(width: 16),
                              Text('Dinner: ${s.dinnerServings}'),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),

          // Loader overlay during deletion
          if (_isDeleting)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}