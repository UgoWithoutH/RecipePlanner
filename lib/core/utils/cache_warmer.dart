import '../../data/repositories/firebase_category_repository.dart';
import '../../data/repositories/firebase_ingredient_repository.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_pantry_repository.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../data/repositories/firebase_stats_repository.dart';
import '../../data/repositories/group_repository.dart';
import 'ingredient_name_cache.dart';

/// Warms all in-memory caches in parallel right after a successful login,
/// so data is ready before the user navigates to any page.
///
/// Also provides [clearAll] which is called on sign-out to prevent stale
/// data from leaking between users on the same device.
class CacheWarmer {
  static Future<void> warmAll() async {
    await Future.wait([
      FirebaseCategoryRepository().getCategories(),
      FirebaseIngredientTypeRepository().getTypes(),
      FirebaseRecipeRepository().fetchAllRecipes(),
      FirebaseStatsRepository.instance.getRecipeUsageCounts(),
      FirebasePantryRepository.instance.getAll(),
      FirebaseShoppingListRepository().getGroupShoppingList(),
      FirebaseMealPlanRepository().getAllMealPlans(),
      FirebaseIngredientRepository().getAllIngredients(),
    ]);
  }

  static void clearAll() {
    GroupRepository.instance.clearCache();
    FirebaseCategoryRepository.invalidateCache();
    FirebaseIngredientTypeRepository.invalidateCache();
    FirebaseRecipeRepository.invalidateCache();
    FirebaseStatsRepository.instance.invalidateCache();
    FirebasePantryRepository.invalidateCache();
    FirebaseShoppingListRepository.invalidateCache();
    FirebaseMealPlanRepository.invalidateCache();
    FirebaseIngredientRepository.invalidateCache();
    IngredientNameCache.instance.clear();
  }
}
