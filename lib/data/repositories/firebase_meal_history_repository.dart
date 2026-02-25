import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:recipe_planner/domain/entities/recipe.dart' show Recipe;
import '../../domain/entities/meal_plan.dart';

class FirebaseMealHistoryRepository {
  final CollectionReference _history =
      FirebaseFirestore.instance.collection('mealPlanHistory');

  /// Add meals to history for a specific date
  /// Each day is stored as a separate document with the date as ID
  Future<void> addDayToHistory(DateTime date, List<Meal> mealsForDay) async {
    if (mealsForDay.isEmpty) return;

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
      'recipeAddExtraMeal': m.recipe.addExtraMeal,
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
      'date': '${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}',
      'meals': mealsData,
    });
  }

  /// Get all history days, ordered by date descending (most recent first)
  Future<Map<DateTime, List<Meal>>> getHistory() async {
    final snapshot = await _history.orderBy('date', descending: true).get();
    
    final Map<DateTime, List<Meal>> history = {};
    
    for (var doc in snapshot.docs) {
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
          addExtraMeal: mealData['recipeAddExtraMeal'] as bool? ?? false,
          ingredients: const [],
          instructions: const [],
          createdAt: DateTime.now(),
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

  /// Remove history days older than the specified number of days
  Future<void> cleanOldHistory(int maxDays) async {
    // Retrieve all history days, sorted by ascending date
    final snapshot = await _history.orderBy('date', descending: false).get();
    final docs = snapshot.docs;
    // If there are more than maxDays, delete the oldest ones
    if (docs.length > maxDays) {
      final toDelete = docs.take(docs.length - maxDays);
      for (var doc in toDelete) {
        await doc.reference.delete();
      }
    }
  }

  /// Update history from the current meal plan
  /// Adds past days from the plan to history, respects maxDays limit
  Future<void> updateHistoryFromPlan(MealPlan? plan, int maxDays) async {
    if (plan == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Get all meals from the plan that are before today
    final pastMeals = plan.meals.where((meal) {
      final mealDate = DateTime(meal.date.year, meal.date.month, meal.date.day);
      return mealDate.isBefore(today);
    }).toList();
    
    if (pastMeals.isEmpty) return;
    
    // Group meals by date
    final Map<DateTime, List<Meal>> mealsByDate = {};
    for (var meal in pastMeals) {
      final dateKey = DateTime(meal.date.year, meal.date.month, meal.date.day);
      mealsByDate.putIfAbsent(dateKey, () => []).add(meal);
    }
    
    // Get existing history to check what's already saved
    final existingHistory = await getHistory();
    
    // Add new days to history (only if not already present)
    for (var entry in mealsByDate.entries) {
      final dateKey = entry.key;
      final isAlreadyInHistory = existingHistory.keys.any((historyDate) {
        return historyDate.year == dateKey.year &&
               historyDate.month == dateKey.month &&
               historyDate.day == dateKey.day;
      });
      
      if (!isAlreadyInHistory) {
        await addDayToHistory(dateKey, entry.value);
      }
    }
    
    // Clean up old history to respect maxDays limit
    await cleanOldHistory(maxDays);
  }

  /// Check if a specific date is already in history
  Future<bool> isDateInHistory(DateTime date) async {
    final dateKey = _formatDateKey(date);
    final doc = await _history.doc(dateKey).get();
    return doc.exists;
  }

  /// Get the number of days currently in history
  Future<int> getHistoryDaysCount() async {
    final snapshot = await _history.get();
    return snapshot.docs.length;
  }

  /// Format date as a string key for document IDs (YYYY-MM-DD)
  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
