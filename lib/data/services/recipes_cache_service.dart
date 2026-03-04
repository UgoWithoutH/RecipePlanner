import 'package:cloud_firestore/cloud_firestore.dart';

import 'recipes_cache_data_1.dart';
import 'recipes_cache_data_2.dart';
import 'recipes_cache_data_3.dart';

/// Seeds the global `recipes_cache` Firestore collection with ~500
/// pre-defined everyday recipes. Safe to call on every launch: if the
/// collection already contains at least one document the function returns
/// immediately without writing anything.
Future<void> seedRecipesCache() async {
  final firestore = FirebaseFirestore.instance;

  // Guard: skip if already seeded.
  final existing =
      await firestore.collection('recipes_cache').limit(1).get();
  if (existing.docs.isNotEmpty) return;

  final allRecipes = [
    ...recipeCacheData1,
    ...recipeCacheData2,
    ...recipeCacheData3,
  ];

  final now = DateTime.now().toIso8601String();

  // Use batched writes (max 500 per batch).
  const batchSize = 400;
  for (var offset = 0; offset < allRecipes.length; offset += batchSize) {
    final batch = firestore.batch();
    final chunk = allRecipes.skip(offset).take(batchSize);

    for (final r in chunk) {
      final ingredients = (r['i'] as List).map((i) {
        return {
          'name': i[0],
          'quantity': (i[1] as num).toDouble(),
          'unit': i[2],
          'type': i[3],
        };
      }).toList();

      final docRef = firestore.collection('recipes_cache').doc();
      batch.set(docRef, {
        'title': r['t'],
        'description': r['d'],
        'preparationTime': r['p'],
        'cookingTime': r['c'],
        'servings': r['s'],
        'categories': List<String>.from(r['cats'] as List),
        'ingredients': ingredients,
        'instructions': List<String>.from(r['inst'] as List),
        'createdAt': now,
        'isFavorite': false,
        'rating': 0.0,
        'addExtraMeal': false,
      });
    }

    await batch.commit();
  }
}
