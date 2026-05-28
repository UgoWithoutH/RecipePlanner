import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:recipe_planner/domain/entities/recipe.dart' show Recipe;
import '../../domain/entities/meal_plan.dart';
import '../../core/constants/meal_time.dart';
import '../../core/utils/ingredient_name_cache.dart';
import 'firebase_pantry_repository.dart';
import 'firebase_recipe_repository.dart';
import 'firebase_stats_repository.dart';
import 'group_repository.dart';

class FirebaseMealHistoryRepository {
  final CollectionReference _history =
      FirebaseFirestore.instance.collection('mealPlanHistory');

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    return groupId;
  }

  String _docKey(String groupId, String dateKey) => '${groupId}_$dateKey';

  /// Add meals to history for a specific date
  /// Each day is stored as a separate document with the date as ID
  /// If [previousMeals] is provided, only the diff (removed/added) is reflected
  /// in usageCount — avoids double-counting when updating an existing day.
  Future<void> addDayToHistory(DateTime date, List<Meal> mealsForDay, {List<Meal>? previousMeals}) async {
    if (mealsForDay.isEmpty) return;

    final groupId = await _getGroupId();

    // Normalize the date locally (remove the time)
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final dateKey = _formatDateKey(normalizedDate);
    final mealsData = mealsForDay.map((m) => {
      'recipeId': m.recipe.id,
      'recipeName': m.recipe.title,
      'recipeDescription': m.recipe.description,
      'recipeCategory': m.recipe.categoryIds.isNotEmpty ? m.recipe.categoryIds.first : '',
      'recipeCategoryIds': m.recipe.categoryIds,
      'recipeServings': m.recipe.servings,
      'recipeRating': m.recipe.rating,
      'preparationTime': m.recipe.preparationTime,
      'cookingTime': m.recipe.cookingTime,
      // Store the date as a string YYYY-MM-DD without time
      'date': '${m.date.year}-${m.date.month.toString().padLeft(2, '0')}-${m.date.day.toString().padLeft(2, '0')}',
      'type': m.type.toString().split('.').last,
      'totalServings': m.totalServings,
      'userServings': m.userServings,
      'recipeMultiplier': m.recipeMultiplier,
      'isLeftoverMeal': m.isLeftoverMeal,
    }).toList();

    await _history.doc(dateKey).set({
      'groupId': groupId,
      'date': '${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}',
      'meals': mealsData,
    });

    // Calcule le diff pour usageCount :
    // - Si previousMeals est fourni → décrémenter les recettes supprimées, incrémenter les nouvelles
    // - Sinon (premier ajout) → incrémenter toutes les recettes du jour
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    if (previousMeals != null) {
      // Recettes retirées (dans previous mais plus dans new)
      final removedMeals = previousMeals.where((prev) =>
          !prev.isLeftoverMeal &&
          !mealsForDay.any((m) =>
              m.recipe.id == prev.recipe.id &&
              m.type == prev.type &&
              m.isLeftoverMeal == prev.isLeftoverMeal));
      for (final m in removedMeals) {
        batch.update(
          db.collection('recipes').doc(m.recipe.id),
          {'usageCount': FieldValue.increment(-1)},
        );
        for (final ing in m.recipe.ingredients) {
          if (ing.ingredient.id.isNotEmpty) {
            batch.update(
              db.collection('ingredients').doc(ing.ingredient.id),
              {'usageCount': FieldValue.increment(-1)},
            );
          }
        }
      }
      // Recettes ajoutées (dans new mais pas dans previous)
      final addedMeals = mealsForDay.where((m) =>
          !m.isLeftoverMeal &&
          !previousMeals.any((prev) =>
              prev.recipe.id == m.recipe.id &&
              prev.type == m.type &&
              prev.isLeftoverMeal == m.isLeftoverMeal));
      for (final m in addedMeals) {
        batch.update(
          db.collection('recipes').doc(m.recipe.id),
          {'usageCount': FieldValue.increment(1)},
        );
        for (final ing in m.recipe.ingredients) {
          if (ing.ingredient.id.isNotEmpty) {
            batch.update(
              db.collection('ingredients').doc(ing.ingredient.id),
              {'usageCount': FieldValue.increment(1)},
            );
          }
        }
      }
    } else {
      // Premier ajout — incrémenter toutes les recettes du jour
      for (final m in mealsForDay) {
        if (m.isLeftoverMeal) continue;
        batch.update(
          db.collection('recipes').doc(m.recipe.id),
          {'usageCount': FieldValue.increment(1)},
        );
        for (final ing in m.recipe.ingredients) {
          if (ing.ingredient.id.isNotEmpty) {
            batch.update(
              db.collection('ingredients').doc(ing.ingredient.id),
              {'usageCount': FieldValue.increment(1)},
            );
          }
        }
      }
    }

    await batch.commit();
    FirebaseStatsRepository.instance.invalidateCache();
  }

  /// Get all history days, ordered by date descending (most recent first)
  Future<Map<DateTime, List<Meal>>> getHistory() async {
    final groupId = await _getGroupId();
    final snapshot = await _history
        .where('groupId', isEqualTo: groupId)
        .get();
    return _parseHistoryDocs(snapshot.docs);
  }

  /// Parse a list of Firestore history docs into a [DateTime → List<Meal>] map.
  /// Extracted to avoid re-reading Firestore when the snapshot is already loaded.
  Map<DateTime, List<Meal>> _parseHistoryDocs(List<dynamic> docs) {
    final Map<DateTime, List<Meal>> history = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final parsedDate = DateTime.parse(data['date'] as String);
      // Normalize the date locally without time to avoid timezone issues
      final date = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      final mealsData = (data['meals'] as List<dynamic>?) ?? [];

      final meals = mealsData.map((m) {
        final mealData = m as Map<String, dynamic>;
        final recipeId = mealData['recipeId'] as String? ?? '';
        final recipeName = mealData['recipeName'] as String? ?? '';
        final recipe = Recipe(
          id: recipeId,
          title: recipeName,
          description: mealData['recipeDescription'] as String? ?? '',
          preparationTime: (mealData['preparationTime'] as num?)?.toInt() ?? 0,
          cookingTime: (mealData['cookingTime'] as num?)?.toInt() ?? 0,
          servings: (mealData['recipeServings'] as num?)?.toInt() ?? 1,
          categoryIds: (mealData['recipeCategoryIds'] as List?)?.map((e) => e.toString()).toList() ??
              ((mealData['recipeCategory'] as String?)?.isNotEmpty == true
                  ? [mealData['recipeCategory'] as String]
                  : []),
          rating: (mealData['recipeRating'] as num?)?.toDouble() ?? 0.0,
          ingredients: const [],
          instructions: const [],
          createdAt: DateTime.now(),
          mealTime: MealTime.fromString(mealData['mealTime'] as String?),
        );
        final typeStr = mealData['type'] as String? ?? 'lunch';
        final mealType = MealType.values.firstWhere(
          (t) => t.toString().split('.').last == typeStr,
          orElse: () => MealType.lunch,
        );
        final userServingsMap = <String, int>{};
        final rawUserServings = mealData['userServings'] as Map<String, dynamic>?;
        if (rawUserServings != null) {
          rawUserServings.forEach((k, v) {
            userServingsMap[k] = (v as num).toInt();
          });
        }
        // Store the date as a date without time (YYYY-MM-DD)
        final dateStr = mealData['date'] as String;
        final dateParts = dateStr.split('-');
        final date = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
        );
        return Meal(
          recipe: recipe,
          date: date,
          type: mealType,
          totalServings: (mealData['totalServings'] as num?)?.toInt() ?? 1,
          userServings: userServingsMap,
          recipeMultiplier: (mealData['recipeMultiplier'] as num?)?.toInt() ?? 1,
          isLeftoverMeal: mealData['isLeftoverMeal'] as bool? ?? false,
          userSelected: mealData['userSelected'] as bool? ?? false,
        );
      }).toList();

      history[date] = meals;
    }

    return history;
  }

  /// Remove history days older than [maxDays], reusing [docs] already loaded
  /// from Firestore to avoid an extra read.
  Future<void> _cleanOldHistoryFromDocs(List<dynamic> docs, int maxDays) async {
    final sorted = docs.toList()
      ..sort((a, b) {
        final aDate = (a.data() as Map<String, dynamic>)['date'] as String? ?? '';
        final bDate = (b.data() as Map<String, dynamic>)['date'] as String? ?? '';
        return aDate.compareTo(bDate); // ascending, oldest first
      });
    if (sorted.length > maxDays) {
      final toDelete = sorted.take(sorted.length - maxDays);
      for (final doc in toDelete) {
        await doc.reference.delete();
      }
    }
  }

  /// Remove history days older than the specified number of days
  Future<void> cleanOldHistory(int maxDays) async {
    final groupId = await _getGroupId();
    final snapshot = await _history
        .where('groupId', isEqualTo: groupId)
        .get();
    await _cleanOldHistoryFromDocs(snapshot.docs, maxDays);
  }

  /// Update history from the current meal plan.
  /// Adds past days from the plan to history, respects maxDays limit.
  /// Returns the final history map (avoids a redundant [getHistory] call by
  /// the caller — the snapshot is read only once internally).
  Future<Map<DateTime, List<Meal>>> updateHistoryFromPlan(MealPlan? plan, int maxDays) async {
    final groupId = await _getGroupId();

    // Single read of the entire history collection for this group.
    final snapshot = await _history
        .where('groupId', isEqualTo: groupId)
        .get();
    final existingHistory = _parseHistoryDocs(snapshot.docs);

    if (plan == null) return existingHistory;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Get all meals from the plan that are before today
    final pastMeals = plan.meals.where((meal) {
      final mealDate = DateTime(meal.date.year, meal.date.month, meal.date.day);
      return mealDate.isBefore(today);
    }).toList();
    
    if (pastMeals.isEmpty) return existingHistory;

    // Group meals by date
    final Map<DateTime, List<Meal>> mealsByDate = {};
    for (var meal in pastMeals) {
      final dateKey = DateTime(meal.date.year, meal.date.month, meal.date.day);
      mealsByDate.putIfAbsent(dateKey, () => []).add(meal);
    }

    // Add new days to history (only if not already present)
    bool addedNew = false;
    for (var entry in mealsByDate.entries) {
      final dateKey = entry.key;
      final isAlreadyInHistory = existingHistory.keys.any((historyDate) {
        return historyDate.year == dateKey.year &&
               historyDate.month == dateKey.month &&
               historyDate.day == dateKey.day;
      });

      if (!isAlreadyInHistory) {
        // Enrichir les repas avec les ingrédients complets AVANT d'appeler
        // addDayToHistory, afin que usageCount des ingrédients soit bien incrémenté.
        // Les repas chargés depuis le plan ont ingredients: [] par défaut.
        final enrichedMeals = <Meal>[];
        for (final meal in entry.value) {
          if (meal.isLeftoverMeal) {
            enrichedMeals.add(meal);
            continue;
          }
          final fullRecipe = await FirebaseRecipeRepository().fetchRecipeById(meal.recipe.id);
          if (fullRecipe != null && fullRecipe.ingredients.isNotEmpty) {
            final ids = fullRecipe.ingredients
                .map((i) => i.ingredient.id)
                .where((id) => id.isNotEmpty)
                .toList();
            final nameMap = await IngredientNameCache.instance.fetchNamesForIds(ids);
            final resolved = fullRecipe.copyWith(
              ingredients: fullRecipe.ingredients.map((ri) {
                final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
                return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
              }).toList(),
            );
            enrichedMeals.add(meal.copyWith(recipe: resolved));
          } else {
            enrichedMeals.add(meal);
          }
        }

        // Sauvegarder en historique avec les repas enrichis (ingrédients présents)
        await addDayToHistory(dateKey, enrichedMeals);
        existingHistory[dateKey] = enrichedMeals;
        addedNew = true;

        // Déduire les ingrédients consommés du frigo/placard
        final nonLeftovers = enrichedMeals.where((m) => !m.isLeftoverMeal).toList();
        if (nonLeftovers.isNotEmpty) {
          await FirebasePantryRepository.instance.deductFromMeals(nonLeftovers);
        }
      }
    }

    // Clean up old history to respect maxDays limit.
    // Si de nouvelles entrées ont été ajoutées, on relit pour avoir le bon compte.
    // Sinon on réutilise le snapshot déjà chargé (cas courant, 0 lectures supplémentaires).
    if (addedNew) {
      final updatedSnap = await _history
          .where('groupId', isEqualTo: groupId)
          .get();
      await _cleanOldHistoryFromDocs(updatedSnap.docs, maxDays);
    } else {
      await _cleanOldHistoryFromDocs(snapshot.docs, maxDays);
    }

    return existingHistory;
  }

  /// Supprime tout l'historique du groupe
  Future<void> clearAllHistory() async {
    final groupId = await _getGroupId();
    final snapshot = await _history
        .where('groupId', isEqualTo: groupId)
        .get();

    final db = FirebaseFirestore.instance;

    // Collecter les recipeIds uniques (non-leftovers) présents dans l'historique
    final recipeIdsSeen = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final mealsData = (data['meals'] as List<dynamic>?) ?? [];
      for (final m in mealsData) {
        final mealData = m as Map<String, dynamic>;
        if (mealData['isLeftoverMeal'] as bool? ?? false) continue;
        final recipeId = mealData['recipeId'] as String? ?? '';
        if (recipeId.isNotEmpty) recipeIdsSeen.add(recipeId);
      }
    }

    // Collecter les ingredientIds via les recettes complètes
    final ingredientIdsSeen = <String>{};
    for (final recipeId in recipeIdsSeen) {
      try {
        final recipeDoc = await db.collection('recipes').doc(recipeId).get();
        if (!recipeDoc.exists) continue;
        final ingredients = (recipeDoc.data()?['ingredients'] as List<dynamic>?) ?? [];
        for (final ing in ingredients) {
          final ingId = (ing as Map<String, dynamic>)['ingredientId'] as String? ?? '';
          if (ingId.isNotEmpty) ingredientIdsSeen.add(ingId);
        }
      } catch (_) {}
    }

    // Supprimer les docs d'historique et remettre usageCount à 0
    // On utilise set(0) et non increment(-1) pour éviter de passer en négatif
    // si les stats ont été réinitialisées manuellement avant la suppression.
    final batch = db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final recipeId in recipeIdsSeen) {
      batch.update(db.collection('recipes').doc(recipeId), {'usageCount': 0});
    }
    for (final ingId in ingredientIdsSeen) {
      batch.update(db.collection('ingredients').doc(ingId), {'usageCount': 0});
    }
    await batch.commit();

    FirebaseStatsRepository.instance.invalidateCache();
  }

  /// Supprime un jour entier de l'historique et décrémente usageCount
  Future<void> deleteDayFromHistory(DateTime date, {List<Meal>? mealsBeingDeleted}) async {
    final dateKey = _formatDateKey(
      DateTime(date.year, date.month, date.day),
    );
    await _history.doc(dateKey).delete();

    if (mealsBeingDeleted != null && mealsBeingDeleted.isNotEmpty) {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final m in mealsBeingDeleted) {
        if (m.isLeftoverMeal) continue;
        batch.update(
          db.collection('recipes').doc(m.recipe.id),
          {'usageCount': FieldValue.increment(-1)},
        );
        for (final ing in m.recipe.ingredients) {
          if (ing.ingredient.id.isNotEmpty) {
            batch.update(
              db.collection('ingredients').doc(ing.ingredient.id),
              {'usageCount': FieldValue.increment(-1)},
            );
          }
        }
      }
      await batch.commit();
      FirebaseStatsRepository.instance.invalidateCache();
    }
  }

  /// Check if a specific date is already in history
  Future<bool> isDateInHistory(DateTime date) async {
    final groupId = await _getGroupId();
    final dateKey = _formatDateKey(date);
    final doc = await _history.doc(_docKey(groupId, dateKey)).get();
    return doc.exists;
  }

  /// Get the number of days currently in history
  Future<int> getHistoryDaysCount() async {
    final groupId = await _getGroupId();
    final snapshot = await _history
        .where('groupId', isEqualTo: groupId)
        .get();
    return snapshot.docs.length;
  }

  /// Format date as a string key for document IDs (YYYY-MM-DD)
  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
