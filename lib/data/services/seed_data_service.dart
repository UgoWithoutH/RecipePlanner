import '../../core/constants/unit.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds all test data for every group: ingredients, recipes, categories and user servings.
/// Users are NOT seeded here â€” they are managed manually in Firestore.
/// For each group, servings are created for every user in the group's `members` array.
Future<void> seedAllTestData() async {
  final firestore = FirebaseFirestore.instance;
  final groupsSnap = await firestore.collection('groups').get();
  for (final groupDoc in groupsSnap.docs) {
    final groupId = groupDoc.id;
    final memberUids = List<String>.from(groupDoc.data()['members'] ?? []);
    await seedAllToFirestore(groupId: groupId, memberUids: memberUids);
  }
}

/// Populates Firestore with recipes drawn from the global `recipes_cache`
/// collection. Creates UserRecipeServings for every user in the group.
/// Call [seedRecipesCache] before this function so that ingredient types,
/// categories and ingredients are already resolved for the group.
Future<List<Recipe>> seedAllToFirestore({
  required String groupId,
  required List<String> memberUids,
  int limit = 20,
}) async {
  final firestore = FirebaseFirestore.instance;
  final gid = groupId;

  // Fetch recipes from the global cache
  final cacheSnap = await firestore
      .collection('recipes_cache')
      .limit(limit)
      .get();
  if (cacheSnap.docs.isEmpty) return [];

  // Resolve existing categories for this group (lowercase name â†’ id)
  final catsSnap = await firestore
      .collection('categories')
      .where('groupId', isEqualTo: gid)
      .get();
  final Map<String, String> catNameToId = {};
  for (final doc in catsSnap.docs) {
    final name = (doc.data()['name'] as String? ?? '').toLowerCase();
    if (name.isNotEmpty) catNameToId[name] = doc.id;
  }

  // Resolve existing ingredients for this group (lowercase name â†’ id)
  final ingsSnap = await firestore
      .collection('ingredients')
      .where('groupId', isEqualTo: gid)
      .get();
  final Map<String, String> ingNameToId = {};
  for (final doc in ingsSnap.docs) {
    final name = (doc.data()['name'] as String? ?? '').toLowerCase();
    if (name.isNotEmpty) ingNameToId[name] = doc.id;
  }

  // Fetch user display names
  final Map<String, String> userNameMap = {};
  if (memberUids.isNotEmpty) {
    final usersSnap = await firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: memberUids)
        .get();
    for (final doc in usersSnap.docs) {
      userNameMap[doc.id] = (doc.data()['name'] as String? ?? doc.id);
    }
  }

  final now = DateTime.now();
  final List<Recipe> seededRecipes = [];

  for (int i = 0; i < cacheSnap.docs.length; i++) {
    final cacheData = cacheSnap.docs[i].data();

    final title = (cacheData['title'] as String? ?? '').toLowerCase();
    final description = cacheData['description'] as String? ?? '';
    final servings = (cacheData['servings'] as num?)?.toInt() ?? 4;
    final prepTime = (cacheData['preparationTime'] as num?)?.toInt() ?? 0;
    final cookTime = (cacheData['cookingTime'] as num?)?.toInt() ?? 0;
    final instructions =
        List<String>.from(cacheData['instructions'] as List? ?? []);
    final cacheCategories =
        List<String>.from(cacheData['categories'] as List? ?? []);

    // Resolve category IDs
    final resolvedCategoryIds = cacheCategories
        .map((c) => catNameToId[c.toLowerCase()])
        .whereType<String>()
        .toList();

    // Resolve ingredients
    final rawIngredients = cacheData['ingredients'] as List? ?? [];
    final List<RecipeIngredient> recipeIngredients = [];
    for (final rawIng in rawIngredients) {
      final ingName = (rawIng['name'] as String? ?? '').trim();
      if (ingName.isEmpty) continue;
      final qty = (rawIng['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitStr = rawIng['unit'] as String? ?? '';
      final unit = Unit.values.firstWhere(
        (u) => u.name == unitStr,
        orElse: () => Unit.piece,
      );
      final ingId = ingNameToId[ingName.toLowerCase()] ?? '';
      recipeIngredients.add(RecipeIngredient(
        ingredient: Ingredient(id: ingId, name: ingName),
        quantity: qty,
        unit: unit,
      ));
    }

    // Proportional reduction logic for user servings
    final List<Map<String, dynamic>> initialUserServings = [
      for (int u = 0; u < memberUids.length; u++)
        {
          'userId': memberUids[u],
          'portion': 1 + ((i + u) % 3),
          'date': now.toIso8601String(),
        }
    ];

    int totalPortions =
        initialUserServings.fold(0, (sum, s) => sum + (s['portion'] as int));
    int maxServings = servings;
    List<double> rawPortions = [
      for (final s in initialUserServings) s['portion'].toDouble()
    ];
    List<double> scaledPortions = rawPortions;
    if (totalPortions > maxServings) {
      scaledPortions =
          rawPortions.map((p) => p * maxServings / totalPortions).toList();
    }
    List<int> finalPortions = [for (final p in scaledPortions) p.floor()];
    List<double> fractions = [
      for (final p in scaledPortions) p - p.floor()
    ];
    int sumFinal = finalPortions.fold(0, (a, b) => a + b);
    int deficit = maxServings - sumFinal;
    if (deficit > 0) {
      List<int> indices =
          List.generate(finalPortions.length, (idx) => idx);
      indices.sort((a, b) => fractions[b].compareTo(fractions[a]));
      for (int k = 0; k < deficit && k < indices.length; k++) {
        finalPortions[indices[k]] += 1;
      }
    }

    // Build adjusted userServings
    final List<Map<String, dynamic>> userServings = [];
    for (int u = 0; u < memberUids.length; u++) {
      final portion = finalPortions[u];
      int lunchServings = portion > 1
          ? (portion ~/ 2).clamp(1, portion)
          : (portion > 0 ? 1 : 0);
      int dinnerServings = portion > 1
          ? (portion - lunchServings).clamp(1, portion)
          : (portion > 0 ? 1 : 0);
      userServings.add({
        'userId': memberUids[u],
        'portion': portion,
        'date': now.toIso8601String(),
        'lunchServings': lunchServings,
        'dinnerServings': dinnerServings,
      });
    }

    final categoryId =
        resolvedCategoryIds.isNotEmpty ? resolvedCategoryIds.first : '';
    final recipeRef = await firestore.collection('recipes').add({
      'title': title,
      'description': description,
      'servings': servings,
      'category': categoryId,
      'categoryIds': resolvedCategoryIds,
      'preparationTime': prepTime,
      'cookingTime': cookTime,
      'ingredients': recipeIngredients
          .map((ri) => {
                'ingredientId': ri.ingredient.id,
                'ingredientName': ri.ingredient.name,
                'quantity': ri.quantity,
                'unit': ri.unit.name,
                'notes': ri.notes,
              })
          .toList(),
      'instructions': instructions,
      'createdAt': now.toIso8601String(),
      'isFavorite': false,
      'rating': 0.0,
      'userServings': userServings,
      'url': '',
      'groupId': gid,
    });

    await firestore
        .collection('recipes')
        .doc(recipeRef.id)
        .update({'id': recipeRef.id});

    for (final serving in userServings) {
      final portion = serving['portion'] as int;
      final lunchServings = serving['lunchServings'] as int;
      final dinnerServings = serving['dinnerServings'] as int;

      final data = {
        'userId': serving['userId'],
        'userName': userNameMap[serving['userId']] ?? serving['userId'],
        'lunchServings': lunchServings,
        'dinnerServings': dinnerServings,
        'recipeId': recipeRef.id,
        'recipeTitle': title,
        'createdAt': Timestamp.now(),
      };

      // Recipe side
      await firestore
          .collection('recipes')
          .doc(recipeRef.id)
          .collection('userServings')
          .doc(serving['userId'])
          .set(data);

      // User side
      await firestore
          .collection('users')
          .doc(serving['userId'])
          .collection('recipeServings')
          .doc(recipeRef.id)
          .set(data);
    }

    seededRecipes.add(Recipe(
      id: recipeRef.id,
      title: title,
      description: description,
      servings: servings,
      categoryIds: resolvedCategoryIds,
      preparationTime: prepTime,
      cookingTime: cookTime,
      ingredients: recipeIngredients,
      instructions: instructions,
      createdAt: now,
      isFavorite: false,
      rating: 0.0,
    ));
  }

  return seededRecipes;
}
