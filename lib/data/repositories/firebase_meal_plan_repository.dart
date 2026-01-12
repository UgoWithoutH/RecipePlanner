import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';

class FirebaseMealPlanRepository {
  final CollectionReference _mealPlans =
      FirebaseFirestore.instance.collection('mealPlans');

  /// Save a new meal plan to Firestore
  Future<String> saveMealPlan(MealPlan mealPlan) async {
    final data = mealPlan.toFirestore();

    final docRef = _mealPlans.doc();
    await docRef.set({
      ...data,
      'id': docRef.id,
    });

    return docRef.id;
  }

  /// Fetch all meal plans
  Future<List<MealPlan>> getAllMealPlans() async {
    final snapshot = await _mealPlans.orderBy('createdAt', descending: true).get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final mealsData = (data['meals'] as List<dynamic>?) ?? [];
      final meals = mealsData.map((m) {
        final mealData = m as Map<String, dynamic>;

        final recipeId = mealData['recipeId'] as String? ?? '';
        final recipeName = mealData['recipeName'] as String? ?? '';

        final recipe = Recipe(
          id: recipeId,
          title: recipeName,
          description: '',
          preparationTime: (mealData['preparationTime'] as num?)?.toInt() ?? 0,
          cookingTime: (mealData['cookingTime'] as num?)?.toInt() ?? 0,
          servings: 1,
          ingredients: const [],
          instructions: const [],
          category: '',
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

        return Meal(
          recipe: recipe,
          date: DateTime.parse(mealData['date'] as String),
          type: mealType,
          totalServings: (mealData['totalServings'] as num?)?.toInt() ?? 1,
          userServings: userServingsMap,
        );
      }).toList();

      return MealPlan(
        id: doc.id,
        startDate: DateTime.parse(data['startDate']),
        durationDays: data['durationDays'],
        createdAt: DateTime.parse(data['createdAt']),
        meals: meals,
      );
    }).toList();
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
        description: '',
        preparationTime: (mealData['preparationTime'] as num?)?.toInt() ?? 0,
        cookingTime: (mealData['cookingTime'] as num?)?.toInt() ?? 0,
        servings: 1,
        ingredients: const [],
        instructions: const [],
        category: '',
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

      return Meal(
        recipe: recipe,
        date: DateTime.parse(mealData['date'] as String),
        type: mealType,
        totalServings: (mealData['totalServings'] as num?)?.toInt() ?? 1,
        userServings: userServingsMap,
      );
    }).toList();

    return MealPlan(
      id: doc.id,
      startDate: DateTime.parse(data['startDate']),
      durationDays: data['durationDays'],
      createdAt: DateTime.parse(data['createdAt']),
      meals: meals,
    );
  }

  /// Delete a meal plan
  Future<void> deleteMealPlan(String id) async {
    await _mealPlans.doc(id).delete();
  }
}
