import '../../domain/entities/recipe.dart';

abstract class RecipeRepository {
  Future<void> createRecipe(Recipe recipe);

  Future<void> updateRecipe(Recipe recipe);

  Future<void> deleteRecipe(String id);

  Future<List<Recipe>> fetchRecipesByTitle(String title);
}