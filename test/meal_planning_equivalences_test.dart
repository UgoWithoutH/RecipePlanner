import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_planner/core/constants/ingredient_equivalence.dart';
import 'package:recipe_planner/core/constants/unit.dart';
import 'package:recipe_planner/domain/entities/ingredient.dart';
import 'package:recipe_planner/domain/entities/meal_plan.dart';
import 'package:recipe_planner/domain/entities/recipe.dart';
import 'package:recipe_planner/domain/entities/recipe_ingredient.dart';
import 'package:recipe_planner/domain/entities/user.dart';
import 'package:recipe_planner/domain/entities/user_recipe_serving.dart';
import 'package:recipe_planner/domain/usecases/meal_planning_service.dart';

RecipeIngredient ri(String name, double q, Unit u) => RecipeIngredient(
    ingredient: Ingredient(id: name, name: name), quantity: q, unit: u);

List<Recipe> buildRecipes() {
  final defs = <String, List<RecipeIngredient>>{
    'r1': [ri('Lardons', 1, Unit.piece), ri('Pâtes', 300, Unit.g)],
    'r2': [ri('Poulet', 1, Unit.piece), ri('Riz', 250, Unit.g)],
    'r3': [ri('Oeufs', 4, Unit.piece), ri('Farine', 150, Unit.g)],
    'r4': [ri('Tomates', 6, Unit.piece), ri('Huile', 2, Unit.tablespoon)],
    'r5': [ri('Saumon', 400, Unit.g), ri('Riz', 0.2, Unit.kg)],
    'r6': [ri('Farine', 0.25, Unit.kg), ri('Lait', 500, Unit.ml)],
    'r7': [ri('Bœuf', 500, Unit.g), ri('Carottes', 400, Unit.g)],
    'r8': [ri('Pâtes', 0.4, Unit.kg), ri('Tomates', 4, Unit.piece)],
  };
  return [
    for (final e in defs.entries)
      Recipe(
        id: e.key,
        title: e.key,
        description: '',
        preparationTime: 10,
        cookingTime: 20,
        servings: 4,
        ingredients: e.value,
        instructions: const [],
        categoryIds: const [],
        createdAt: DateTime(2026, 1, 1),
      ),
  ];
}

String fingerprint(MealPlan p) => p.meals
    .map((m) => '${m.recipe.id}x${m.recipeMultiplier}${m.isLeftoverMeal ? "L" : ""}')
    .join(',');

Future<MealPlan> run(List<RecipeIngredient> pantry,
    {int days = 7, List<String>? only}) {
  final users = [const User(id: 'u1', name: 'A'), const User(id: 'u2', name: 'B')];
  final recipes = [
    for (final r in buildRecipes())
      if (only == null || only.contains(r.id)) r,
  ];
  final servings = [
    for (final r in recipes)
      for (final u in users)
        UserRecipeServing(
            userId: u.id,
            recipeId: r.id,
            userName: u.name,
            recipeTitle: r.title,
            lunchServings: 1,
            dinnerServings: 1),
  ];
  return MealPlanningService.generateMealPlan(
    recipes: recipes,
    servings: servings,
    users: users,
    startDate: DateTime(2026, 11, 20),
    durationDays: days,
    pantryItems: pantry,
  );
}

void main() {
  const pouletPack = {
    'Poulet': [
      IngredientEquivalence(unitCode: 'piece', amount: 500, targetCode: 'g'),
    ],
  };
  const lardonsPack = {
    'Lardons': [
      IngredientEquivalence(unitCode: 'piece', amount: 200, targetCode: 'g'),
    ],
  };

  setUp(() {
    UnitRegistry.configure(
        units: Unit.defaults, conversions: UnitConversion.defaults);
    IngredientEquivalences.configure({});
  });
  tearDown(() => IngredientEquivalences.configure({}));

  test('a pantry in g favors a recipe using the ingredient in pieces once an equivalence exists', () async {
    final pantry = [ri('Poulet', 500, Unit.g)];
    const only = ['r1', 'r2'];

    final without = await run(pantry, days: 1, only: only);
    IngredientEquivalences.configure(pouletPack);
    final withEquivalence = await run(pantry, days: 1, only: only);

    expect(without.meals.last.recipe.id, 'r1');
    expect(withEquivalence.meals.last.recipe.id, 'r2');
  });

  test('an unrelated equivalence does not change the plan', () async {
    final base = await run([ri('Riz', 500, Unit.g)]);
    IngredientEquivalences.configure(lardonsPack);
    final other = await run([ri('Riz', 500, Unit.g)]);
    expect(fingerprint(other), fingerprint(base));
  });
}
