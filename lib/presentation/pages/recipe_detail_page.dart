import 'package:flutter/material.dart';
import '../../domain/entities/recipe.dart';
import 'create_recipe_page.dart';
import '../../data/repositories/firebase_recipe_repository.dart';

class RecipeDetailPage extends StatefulWidget {
  final Recipe recipe;

  const RecipeDetailPage({
    super.key,
    required this.recipe,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Recipe _recipe;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    // Initialize with the recipe passed from the list
    _recipe = widget.recipe;
  }

  /// Deletes the current recipe from Firestore
  /// Shows a confirmation dialog before deletion
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
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loader overlay
    setState(() {
      _isDeleting = true;
    });

    try {
      final repo = FirebaseRecipeRepository();
      await repo.deleteRecipe(_recipe.id);

      // Return to the previous screen (recipe list)
      if (mounted) {
        Navigator.pop(context, true); // indicate deletion
      }
    } catch (e) {
      // Hide loader and show error
      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting recipe: $e'),
        ),
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
          // Edit button
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
                setState(() {
                  _recipe = updatedRecipe;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Recipe updated successfully'),
                  ),
                );
              }
            },
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Recipe',
            onPressed: _isDeleting ? null : _deleteRecipe,
          ),
        ],
      ),

      body: Stack(
        children: [
          // Main content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipe.description,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    const Icon(
                      Icons.category,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _recipe.category,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    const Icon(
                      Icons.timer,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text('Prep: ${_recipe.preparationTime} min'),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.restaurant,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text('Cook: ${_recipe.cookingTime} min'),
                  ],
                ),

                const SizedBox(height: 24),

                const Text(
                  'Ingredients',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

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

                const Text(
                  'Instructions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                ..._recipe.instructions.asMap().entries.map(
                  (entry) {
                    final index = entry.key;
                    final step = entry.value;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(step),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Loader overlay
          if (_isDeleting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}