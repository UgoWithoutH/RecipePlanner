import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart' show Unit;
import '../../domain/entities/ingredient.dart' show Ingredient;
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'recipe_repository.dart';
import 'group_repository.dart';

class FirebaseRecipeRepository implements RecipeRepository {
  final CollectionReference _recipes = FirebaseFirestore.instance.collection(
    'recipes',
  );

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    return groupId;
  }

  /// Fetch a single recipe by its ID
  Future<Recipe?> fetchRecipeById(String id) async {
    if (id.isEmpty) return null;
    // Try to find document by stored 'id' field first
    final query = await _recipes.where('id', isEqualTo: id).limit(1).get();
    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data() as Map<String, dynamic>;
      final ingredients = (data['ingredients'] as List<dynamic>? ?? []).map((
        i,
      ) {
        return RecipeIngredient(
          ingredient: Ingredient(id: i['ingredientId'], name: ''),
          quantity: (i['quantity'] as num).toDouble(),
          unit: Unit.values.firstWhere(
            (u) => u.label == i['unit'],
            orElse: () => Unit.g,
          ),
          notes: i['notes'],
        );
      }).toList();
      return Recipe(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
        cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
        servings: (data['servings'] as num?)?.toInt() ?? 1,
        categoryIds: (data['categoryIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            (data['category'] != null && (data['category'] as String).isNotEmpty
                ? [data['category'] as String]
                : []),
        ingredients: ingredients,
        instructions: List<String>.from(data['instructions'] ?? []),
        createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        isFavorite: data['isFavorite'] ?? false,
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        url: data['url'],
      );
    }
    // Fallback: try by doc id
    final docRef = _recipes.doc(id);
    final snapshot = await docRef.get();
    if (snapshot.exists) {
      final data = snapshot.data() as Map<String, dynamic>;
      final ingredients = (data['ingredients'] as List<dynamic>? ?? []).map((
        i,
      ) {
        return RecipeIngredient(
          ingredient: Ingredient(id: i['ingredientId'], name: ''),
          quantity: (i['quantity'] as num).toDouble(),
          unit: Unit.values.firstWhere(
            (u) => u.label == i['unit'],
            orElse: () => Unit.g,
          ),
          notes: i['notes'],
        );
      }).toList();
      return Recipe(
        id: snapshot.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
        cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
        servings: (data['servings'] as num?)?.toInt() ?? 1,
        categoryIds: (data['categoryIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            (data['category'] != null && (data['category'] as String).isNotEmpty
                ? [data['category'] as String]
                : []),
        ingredients: ingredients,
        instructions: List<String>.from(data['instructions'] ?? []),
        createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        isFavorite: data['isFavorite'] ?? false,
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        url: data['url'],
      );
    }
    return null;
  }

  @override
  /// Create a new recipe and return its Firestore document ID
  Future<String> createRecipe(Recipe recipe) async {
    final groupId = await _getGroupId();
    final data = _recipeToMap(recipe);

    final docRef = _recipes.doc(); // generates a new unique ID
    // Ensure the stored document contains the generated ID (avoid empty id stored)
    data['id'] = docRef.id;
    data['groupId'] = groupId;
    await docRef.set(data);

    return docRef.id;
  }

  /// Update an existing recipe in Firestore
  @override
  Future<void> updateRecipe(Recipe recipe) async {
    final data = _recipeToMap(recipe);

    // Find the document by recipe ID
    final query = await _recipes
        .where('id', isEqualTo: recipe.id)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update(data);
      return;
    }

    // Fallback: maybe the document doesn't have an 'id' field set but
    // the recipe.id actually matches the document ID. Try updating by doc id.
    if (recipe.id.isNotEmpty) {
      final docRef = _recipes.doc(recipe.id);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.update(data);
        return;
      }
    }

    throw Exception('Recipe with id ${recipe.id} not found');
  }

  /// Delete a recipe by its ID
  @override
  Future<void> deleteRecipe(String id) async {
    if (id.isEmpty) {
      throw Exception('Recipe id is empty');
    }
    final docRef = _recipes.doc(id);
    final snapshot = await docRef.get();
    if (snapshot.exists) {
      await docRef.delete();
      return;
    }
    throw Exception('Recipe with id $id not found');
  }

  /// Fetch recipes by their title (used to check for duplicates)
  @override
  Future<List<Recipe>> fetchRecipesByTitle(String title) async {
    final groupId = await _getGroupId();
    final query = await _recipes
        .where('groupId', isEqualTo: groupId)
        .where('title', isEqualTo: title)
        .get();

    return query.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final ingredients = (data['ingredients'] as List<dynamic>? ?? []).map((
        i,
      ) {
        return RecipeIngredient(
          ingredient: Ingredient(
            id: i['ingredientId'],
            name: '',
          ), // name can be fetched via cache
          quantity: (i['quantity'] as num).toDouble(),
          unit: Unit.values.firstWhere(
            (u) => u.label == i['unit'],
            orElse: () => Unit.g,
          ),
          notes: i['notes'],
        );
      }).toList();

      return Recipe(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
        cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
        servings: (data['servings'] as num?)?.toInt() ?? 1,
        categoryIds: (data['categoryIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            (data['category'] != null && (data['category'] as String).isNotEmpty
                ? [data['category'] as String]
                : []),
        ingredients: ingredients,
        instructions: List<String>.from(data['instructions'] ?? []),
        createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        isFavorite: data['isFavorite'] ?? false,
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  /// Fetch all recipes ordered by creation date
  @override
  Future<List<Recipe>> fetchAllRecipes() async {
    final groupId = await _getGroupId();
    final snapshot = await _recipes
        .where('groupId', isEqualTo: groupId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final ingredients = (data['ingredients'] as List<dynamic>? ?? []).map((
        i,
      ) {
        return RecipeIngredient(
          ingredient: Ingredient(id: i['ingredientId'], name: ''),
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
        categoryIds: (data['categoryIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            (data['category'] != null && (data['category'] as String).isNotEmpty
                ? [data['category'] as String]
                : []),
        ingredients: ingredients,
        instructions: List<String>.from(data['instructions'] ?? []),
        createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
        isFavorite: data['isFavorite'] ?? false,
        rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  Map<String, dynamic> _recipeToMap(Recipe recipe) {
    return {
      'id': recipe.id,
      'title': recipe.title,
      'description': recipe.description,
      'preparationTime': recipe.preparationTime,
      'cookingTime': recipe.cookingTime,
      'servings': recipe.servings,
      'categoryIds': recipe.categoryIds,
      'category': recipe.categoryIds.isNotEmpty ? recipe.categoryIds.first : '',
      'rating': recipe.rating,
      'createdAt': recipe.createdAt.toUtc().toIso8601String(),
      'isFavorite': recipe.isFavorite,
      'instructions': recipe.instructions,
      'ingredients': recipe.ingredients
          .map(
            (RecipeIngredient i) => {
              'ingredientId': i.ingredient.id,
              'quantity': i.quantity,
              'unit': i.unit.label,
              'notes': i.notes,
            },
          )
          .toList(),
      'url': (recipe.url != null && recipe.url!.trim().isNotEmpty)
          ? recipe.url
          : null,
    };
  }
}
