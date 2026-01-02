import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart' show Unit;
import '../../domain/entities/ingredient.dart' show Ingredient;
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'recipe_repository.dart';

class FirebaseRecipeRepository implements RecipeRepository {
  final CollectionReference _recipes = FirebaseFirestore.instance.collection('recipes');

  /// Create a new recipe in Firestore
  @override
  Future<void> createRecipe(Recipe recipe) async {
    final data = _recipeToMap(recipe);
    await _recipes.add(data);
  }

  /// Update an existing recipe in Firestore
  @override
  Future<void> updateRecipe(Recipe recipe) async {
    final data = _recipeToMap(recipe);

    // Find the document by recipe ID
    final query = await _recipes.where('id', isEqualTo: recipe.id).limit(1).get();
    if (query.docs.isEmpty) throw Exception('Recipe with id ${recipe.id} not found');

    await query.docs.first.reference.update(data);
  }

  /// Delete a recipe by its ID
  Future<void> deleteRecipe(String id) async {
    // Find the document by recipe ID
    final query = await _recipes.where('id', isEqualTo: id).limit(1).get();
    if (query.docs.isEmpty) throw Exception('Recipe with id $id not found');

    await query.docs.first.reference.delete();
  }

  /// Fetch recipes by their title (used to check for duplicates)
  @override
  Future<List<Recipe>> fetchRecipesByTitle(String title) async {
    final query = await _recipes.where('title', isEqualTo: title).get();
    return query.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Recipe(
        id: data['id'],
        title: data['title'],
        description: data['description'],
        preparationTime: data['preparationTime'],
        cookingTime: data['cookingTime'],
        category: data['category'],
        ingredients: (data['ingredients'] as List<dynamic>).map((i) {
          return RecipeIngredient(
            ingredient: Ingredient(id: i['ingredientId'], name: ''), // name can be fetched via cache
            quantity: i['quantity'],
            unit: Unit.values.firstWhere((u) => u.label == i['unit']),
            notes: i['notes'],
          );
        }).toList(),
        instructions: List<String>.from(data['instructions']),
        createdAt: DateTime.parse(data['createdAt']),
        isFavorite: data['isFavorite'] ?? false,
        rating: data['rating'] ?? 0,
      );
    }).toList();
  }

  /// Convert a Recipe object into a Firestore map
  Map<String, dynamic> _recipeToMap(Recipe recipe) {
    return {
      'id': recipe.id,
      'title': recipe.title,
      'description': recipe.description,
      'preparationTime': recipe.preparationTime,
      'cookingTime': recipe.cookingTime,
      'category': recipe.category,
      'rating': recipe.rating,
      'createdAt': recipe.createdAt.toUtc().toIso8601String(),
      'isFavorite': recipe.isFavorite,
      'instructions': recipe.instructions,
      'ingredients': recipe.ingredients.map((RecipeIngredient i) => {
        'ingredientId': i.ingredient.id,
        'quantity': i.quantity,
        'unit': i.unit.label,
        'notes': i.notes,
      }).toList(),
    };
  }
}