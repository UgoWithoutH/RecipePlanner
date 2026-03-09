import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/group_repository.dart';
import 'recipes_cache_split/recipes_cache_data_1.dart';
import 'recipes_cache_split/recipes_cache_data_2.dart';
import 'recipes_cache_split/recipes_cache_data_3.dart';
import 'recipes_cache_split/recipes_cache_data_4.dart';
import 'recipes_cache_split/recipes_cache_data_5.dart';

// Couleurs connues pour les catégories (clé en minuscules)
const Map<String, int> _categoryColors = {
  'viande': 0xFFE57373,
  'végétarien': 0xFF81C784,
  'pâtes': 0xFFFFD54F,
  'asiatique': 0xFFFF8A65,
  'poisson': 0xFF4FC3F7,
  'salade': 0xFFAED581,
  'sandwich': 0xFFA1887F,
  'boisson': 0xFF4DB6AC
};

// Couleurs connues pour les types d'ingrédients (clé en minuscules)
const Map<String, int> _ingredientTypeColors = {
  'viande': 0xFFE57373,
  'légume': 0xFF81C784,
  'féculent': 0xFFFFD54F,
  'poisson': 0xFF4FC3F7,
  'produit laitier': 0xFFB39DDB,
  'condiment': 0xFFA1887F,
  'fruit': 0xFFFFB74D,
  'oeuf': 0xFF90CAF9,
  'herbe': 0xFF66BB6A,
  'autre': 0xFFB0BEC5,
};

const int _defaultColor = 0xFFB0BEC5;

/// Seeds the global `recipes_cache` Firestore collection with ~500
/// pre-defined everyday recipes, then ensures all ingredient types,
/// categories and ingredients referenced in the cache exist in the
/// current group's collections.
Future<void> seedRecipesCache() async {
  final firestore = FirebaseFirestore.instance;

  final allRecipes = [
    ...recipeCacheData1,
    ...recipeCacheData2,
    ...recipeCacheData3,
    ...recipeCacheData4,
    ...recipeCacheData5,
  ];

  // 1. Seed global recipes_cache if not already seeded.
  final existing =
      await firestore.collection('recipes_cache').limit(1).get();
  if (existing.docs.isEmpty) {
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
        });
      }

      await batch.commit();
    }
  }

  // 2. Seed entities (types, catégories, ingrédients) pour le groupe courant.
  final groupId = await GroupRepository.instance.getCurrentGroupId();
  if (groupId == null) return;
  await _seedEntitiesFromCache(firestore, allRecipes, groupId);
}

/// Crée dans Firestore, pour le groupe donné, tous les types d'ingrédients,
/// catégories et ingrédients référencés dans les recettes du cache, s'ils
/// n'existent pas encore (comparaison insensible à la casse).
Future<void> _seedEntitiesFromCache(
  FirebaseFirestore firestore,
  List<Map<String, dynamic>> allRecipes,
  String groupId,
) async {
  // ── Collecte des noms uniques ─────────────────────────────────────────────
  final Set<String> catNames = {};
  final Set<String> typeNames = {};
  // Clé : nom en minuscules → {name (casse originale), type (casse originale)}
  final Map<String, Map<String, String>> ingredientEntries = {};

  for (final r in allRecipes) {
    for (final cat in List<String>.from(r['cats'] as List)) {
      final trimmed = cat.trim();
      if (trimmed.isNotEmpty) catNames.add(trimmed);
    }
    for (final i in r['i'] as List) {
      final ingName = (i[0] as String).trim();
      final typeName = (i[3] as String).trim();
      if (typeName.isNotEmpty) typeNames.add(typeName);
      if (ingName.isNotEmpty &&
          !ingredientEntries.containsKey(ingName.toLowerCase())) {
        ingredientEntries[ingName.toLowerCase()] = {
          'name': ingName,
          'type': typeName,
        };
      }
    }
  }

  // ── Catégories ────────────────────────────────────────────────────────────
  final existingCatsSnap = await firestore
      .collection('categories')
      .where('groupId', isEqualTo: groupId)
      .get();
  final Map<String, String> existingCatIds = {};
  for (final doc in existingCatsSnap.docs) {
    final name = (doc.data()['name'] as String? ?? '').toLowerCase();
    if (name.isNotEmpty) existingCatIds[name] = doc.id;
  }

  for (final catName in catNames) {
    if (!existingCatIds.containsKey(catName.toLowerCase())) {
      final color =
          _categoryColors[catName.toLowerCase()] ?? _defaultColor;
      final ref = await firestore.collection('categories').add({
        'name': catName,
        'color': color,
        'groupId': groupId,
      });
      existingCatIds[catName.toLowerCase()] = ref.id;
    }
  }

  // ── Types d'ingrédients ───────────────────────────────────────────────────
  final existingTypesSnap = await firestore
      .collection('ingredient_types')
      .where('groupId', isEqualTo: groupId)
      .get();
  final Map<String, String> existingTypeIds = {};
  for (final doc in existingTypesSnap.docs) {
    final name = (doc.data()['name'] as String? ?? '').toLowerCase();
    if (name.isNotEmpty) existingTypeIds[name] = doc.id;
  }

  for (final typeName in typeNames) {
    if (!existingTypeIds.containsKey(typeName.toLowerCase())) {
      final color =
          _ingredientTypeColors[typeName.toLowerCase()] ?? _defaultColor;
      final ref = await firestore.collection('ingredient_types').add({
        'name': typeName,
        'color': color,
        'groupId': groupId,
      });
      existingTypeIds[typeName.toLowerCase()] = ref.id;
    }
  }

  // ── Ingrédients ───────────────────────────────────────────────────────────
  final existingIngsSnap = await firestore
      .collection('ingredients')
      .where('groupId', isEqualTo: groupId)
      .get();
  final Set<String> existingIngNames = {};
  for (final doc in existingIngsSnap.docs) {
    final name = (doc.data()['name'] as String? ?? '').toLowerCase();
    if (name.isNotEmpty) existingIngNames.add(name);
  }

  for (final entry in ingredientEntries.values) {
    if (!existingIngNames.contains(entry['name']!.toLowerCase())) {
      final typeId = existingTypeIds[entry['type']!.toLowerCase()];
      final data = <String, dynamic>{
        'name': entry['name'],
        'groupId': groupId,
      };
      if (typeId != null && typeId.isNotEmpty) data['typeId'] = typeId;
      await firestore.collection('ingredients').add(data);
    }
  }
}
