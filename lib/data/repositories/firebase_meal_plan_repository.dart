import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/ingredient.dart';
import '../../core/constants/unit.dart';
import '../../core/constants/meal_time.dart';
import 'group_repository.dart';

class FirebaseMealPlanRepository {
  final CollectionReference _mealPlans =
      FirebaseFirestore.instance.collection('mealPlans');

  static final Map<String, List<MealPlan>> _cache = {};

  static void invalidateCache() => _cache.clear();

  Future<String?> _getGroupId() async {
    return GroupRepository.instance.getCurrentGroupId();
  }

  /// Save a new meal plan to Firestore (replaces any existing plan)
  Future<String> saveMealPlan(MealPlan mealPlan) async {
    final groupId = await _getGroupId();
    if (groupId == null) throw Exception('Pas de groupe assigné. Contactez l\'administrateur.');
    final data = mealPlan.toFirestore();
    data['groupId'] = groupId;

    // If the plan already has an ID, just update it
    if (mealPlan.id.isNotEmpty) {
      await _mealPlans.doc(mealPlan.id).set({
        ...data,
        'id': mealPlan.id,
      });
      invalidateCache();
      return mealPlan.id;
    }

    // For new plans, delete all existing meal plans for this group first
    final existingPlans = await _mealPlans
        .where('groupId', isEqualTo: groupId)
        .get();
    for (var doc in existingPlans.docs) {
      await doc.reference.delete();
    }

    // Create the new plan
    final docRef = _mealPlans.doc();
    await docRef.set({
      ...data,
      'id': docRef.id,
    });
    invalidateCache();
    return docRef.id;
  }

  /// Fetch all meal plans
  Future<List<MealPlan>> getAllMealPlans() async {
    final groupId = await _getGroupId();
    if (groupId == null) return [];
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    final snapshot = await _mealPlans
        .where('groupId', isEqualTo: groupId)
        .get();

    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final aDate = (a.data() as Map<String, dynamic>)['createdAt'] as String? ?? '';
        final bDate = (b.data() as Map<String, dynamic>)['createdAt'] as String? ?? '';
        return bDate.compareTo(aDate); // descending
      });

    final plans = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

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

        return Meal(
          recipe: recipe,
          date: DateTime.parse(mealData['date'] as String),
          type: mealType,
          totalServings: (mealData['totalServings'] as num?)?.toInt() ?? 1,
          userServings: userServingsMap,
          recipeMultiplier: (mealData['recipeMultiplier'] as num?)?.toInt() ?? 1,
          isLeftoverMeal: mealData['isLeftoverMeal'] as bool? ?? false,
          userSelected: mealData['userSelected'] as bool? ?? false,
        );
      }).toList();

      return MealPlan(
        id: doc.id,
        startDate: DateTime.parse(data['startDate']),
        durationDays: data['durationDays'],
        createdAt: DateTime.parse(data['createdAt']),
        pantryItems: ((data['pantryItems'] as List<dynamic>?) ?? []).map((d) {
          final map = d as Map<String, dynamic>;
          final unitName = map['unit'] as String? ?? '';
          final unit = Unit.values.firstWhere((u) => u.name == unitName, orElse: () => Unit.piece);
          return RecipeIngredient(
            ingredient: Ingredient(id: '', name: map['name'] ?? ''),
            quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
            unit: unit,
          );
        }).toList(),
        selectedCategories: (data['selectedCategories'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        leftoverUserOrder: (data['leftoverUserOrder'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        meals: meals,
      );
    }).toList();

    _cache[groupId] = plans;
    return plans;
  }

  /// Fetch a specific meal plan by ID
  Future<MealPlan?> getMealPlanById(String id) async {
    final doc = await _mealPlans.doc(id).get();
    if (!doc.exists) return null;

    final data = doc.data() as Map<String, dynamic>;
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

      return Meal(
        recipe: recipe,
        date: DateTime.parse(mealData['date'] as String),
        type: mealType,
        totalServings: (mealData['totalServings'] as num?)?.toInt() ?? 1,
        userServings: userServingsMap,
        recipeMultiplier: (mealData['recipeMultiplier'] as num?)?.toInt() ?? 1,
        isLeftoverMeal: mealData['isLeftoverMeal'] as bool? ?? false,
        userSelected: mealData['userSelected'] as bool? ?? false,
      );
    }).toList();

    return MealPlan(
      id: doc.id,
      startDate: DateTime.parse(data['startDate']),
      durationDays: data['durationDays'],
      createdAt: DateTime.parse(data['createdAt']),
      pantryItems: ((data['pantryItems'] as List<dynamic>?) ?? []).map((d) {
        final map = d as Map<String, dynamic>;
        final unitName = map['unit'] as String? ?? '';
        final unit = Unit.values.firstWhere((u) => u.name == unitName, orElse: () => Unit.piece);
        return RecipeIngredient(
          ingredient: Ingredient(id: '', name: map['name'] ?? ''),
          quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
          unit: unit,
        );
      }).toList(),
      selectedCategories: (data['selectedCategories'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      leftoverUserOrder: (data['leftoverUserOrder'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      meals: meals,
    );
  }

  /// Delete a meal plan
  Future<void> deleteMealPlan(String id) async {
    await _mealPlans.doc(id).delete();
    invalidateCache();
  }

  /// Update all meal plans that contain this recipe with new details
  /// Returns the list of updated plans so the caller can perform additional actions (e.g. update shopping list)
  Future<List<MealPlan>> updatePlansForRecipe(Recipe updatedRecipe) async {
    final plans = await getAllMealPlans();
    final updatedPlans = <MealPlan>[];

    for (var plan in plans) {
      bool isModified = false;
      final newMeals = plan.meals.map((meal) {
        if (meal.recipe.id == updatedRecipe.id) {
          isModified = true;
          return meal.copyWith(recipe: updatedRecipe);
        }
        return meal;
      }).toList();

      if (isModified) {
        final updatedPlan = MealPlan(
          id: plan.id,
          startDate: plan.startDate,
          durationDays: plan.durationDays,
          meals: newMeals,
          createdAt: plan.createdAt,
          pantryItems: plan.pantryItems,
        );
        await saveMealPlan(updatedPlan);
        updatedPlans.add(updatedPlan);
      }
    }
    return updatedPlans;
  }
}
