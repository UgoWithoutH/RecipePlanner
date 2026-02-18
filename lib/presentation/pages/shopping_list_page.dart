import 'package:flutter/material.dart';
import 'package:recipe_planner/data/repositories/firebase_meal_plan_repository.dart' show FirebaseMealPlanRepository;
import 'package:recipe_planner/data/repositories/firebase_recipe_repository.dart' show FirebaseRecipeRepository;
import 'package:recipe_planner/domain/entities/meal_plan.dart' show MealPlan, Meal;

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  MealPlan? _mealPlan;
  bool _isLoading = true;
  bool _loadingRecipes = false;
  List<Meal>? _mealsWithFullRecipes;

  @override
  void initState() {
    super.initState();
    _loadMealPlan();
  }

  Future<void> _loadMealPlan() async {
    setState(() {
      _isLoading = true;
      _loadingRecipes = false;
      _mealsWithFullRecipes = null;
    });
    final repo = FirebaseMealPlanRepository();
    final plans = await repo.getAllMealPlans();
    if (plans.isNotEmpty) {
      plans.sort((a, b) => b.startDate.compareTo(a.startDate));
      setState(() {
        _mealPlan = plans.first;
        _isLoading = false;
      });
      // Charger les recettes complètes pour chaque repas
      _loadFullRecipesForMeals();
    } else {
      setState(() {
        _mealPlan = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFullRecipesForMeals() async {
    if (_mealPlan == null) return;
    setState(() => _loadingRecipes = true);
    final recipeRepo = _importRecipeRepo();
    final List<Meal> meals = [];
    for (final meal in _mealPlan!.meals) {
      final fullRecipe = await recipeRepo.fetchRecipeById(meal.recipe.id);
      if (fullRecipe != null) {
        meals.add(meal.copyWith(recipe: fullRecipe));
      } else {
        meals.add(meal);
      }
    }
    setState(() {
      _mealsWithFullRecipes = meals;
      _loadingRecipes = false;
    });
  }

  FirebaseRecipeRepository _importRecipeRepo() {
    return FirebaseRecipeRepository();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _loadingRecipes) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_mealPlan == null) {
      return const Scaffold(
        body: Center(child: Text('Aucun plan de repas trouvé.')),
      );
    }
    final ingredientTotals = <String, _IngredientTotal>{};
    final meals = _mealsWithFullRecipes ?? _mealPlan!.meals;
    for (final meal in meals) {
      for (final ingredient in meal.recipe.ingredients) {
        final key = ingredient.ingredient.id;
        if (!ingredientTotals.containsKey(key)) {
          ingredientTotals[key] = _IngredientTotal(
            name: ingredient.ingredient.name,
            unit: ingredient.unit.label,
            quantity: 0,
          );
        }
        ingredientTotals[key]!.quantity += ingredient.quantity;
      }
    }
    final items = ingredientTotals.values.toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste de courses'),
      ),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(item.name),
            trailing: Text('${item.quantity} ${item.unit}'),
          );
        },
      ),
    );
  }
}

class _IngredientTotal {
  final String name;
  final String unit;
  double quantity;

  _IngredientTotal({
    required this.name,
    required this.unit,
    required this.quantity,
  });
}
