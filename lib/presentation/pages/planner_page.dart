import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:numberpicker/numberpicker.dart';

import '../../core/constants/unit.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_meal_history_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_user_repository.dart';

import '../../domain/entities/ingredient.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/usecases/meal_planning_service.dart';

import 'recipe_detail_page.dart';
import '../widgets/recipe_selector.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final FirebaseUserRepository _userRepo = FirebaseUserRepository();
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();
  final FirebaseMealPlanRepository _mealPlanRepo = FirebaseMealPlanRepository();
  final FirebaseMealHistoryRepository _historyRepo =
      FirebaseMealHistoryRepository();

  int _maxHistoryDays = 30; // Default value, recalculated based on recipe count

  DateTime? _selectedStartDate;
  int? _selectedDuration;
  bool _isLoading = false;

  MealPlan? _generatedMealPlan;
  Map<DateTime, List<Meal>> _mealHistory = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedMealDate;
  CalendarFormat? _calendarFormat;

  @override
  void initState() {
    super.initState();
    _loadMostRecentMealPlanAndHistory();
  }

  Future<void> _loadMostRecentMealPlanAndHistory() async {
    setState(() => _isLoading = true);
    try {
      // Load recipes first to calculate history days
      final allRecipes = await _loadRecipes();
      _maxHistoryDays = allRecipes.length; // Dynamic history based on recipe count
      
      final plans = await _mealPlanRepo.getAllMealPlans();
      Map<String, Recipe> recipeMap = {for (var recipe in allRecipes) recipe.id: recipe};
      if (plans.isNotEmpty) {
        plans.sort((a, b) => b.startDate.compareTo(a.startDate));
        final loadedPlan = plans.first;
        // Replace partial recipes with full ones
        final mealsWithFullRecipes = loadedPlan.meals.map((meal) {
          final fullRecipe = recipeMap[meal.recipe.id];
          if (fullRecipe != null) {
            return Meal(
              recipe: fullRecipe,
              date: meal.date,
              type: meal.type,
              totalServings: meal.totalServings,
              userServings: meal.userServings,
              recipeMultiplier: meal.recipeMultiplier,
              isLeftoverMeal: meal.isLeftoverMeal,
            );
          }
          return meal;
        }).toList();
        _generatedMealPlan = MealPlan(
          id: loadedPlan.id,
          startDate: loadedPlan.startDate,
          durationDays: loadedPlan.durationDays,
          meals: mealsWithFullRecipes,
          createdAt: loadedPlan.createdAt,
        );
        // Set today as selected if it is within the plan range
        final today = DateTime.now();
        final planStart = _generatedMealPlan!.startDate;
        final planEnd = planStart.add(
          Duration(days: _generatedMealPlan!.durationDays - 1),
        );
        if (!today.isBefore(planStart) && !today.isAfter(planEnd)) {
          _selectedMealDate = today;
          _focusedDay = today;
        } else {
          _selectedMealDate = planStart;
          _focusedDay = planStart;
        }
        _calendarFormat = null; // Reset to recalculate format
        // Update history from loaded plan
        await _historyRepo.updateHistoryFromPlan(
          _generatedMealPlan,
          _maxHistoryDays,
        );
      }
      // Load history into state
      final rawHistory = await _historyRepo.getHistory();
      // Replace partial recipes with full ones in history
      _mealHistory = rawHistory.map((date, meals) {
        final updatedMeals = meals.map((meal) {
          final fullRecipe = recipeMap[meal.recipe.id];
          if (fullRecipe != null) {
            return Meal(
              recipe: fullRecipe,
              date: meal.date,
              type: meal.type,
              totalServings: meal.totalServings,
              userServings: meal.userServings,
              recipeMultiplier: meal.recipeMultiplier,
              isLeftoverMeal: meal.isLeftoverMeal,
            );
          }
          return meal;
        }).toList();
        return MapEntry(date, updatedMeals);
      });
      setState(() {});
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickStartDate({VoidCallback? onDatePicked}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6A5AE0),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6A5AE0),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedStartDate = picked);
      if (onDatePicked != null) onDatePicked();
    }
  }

  void _pickDuration({VoidCallback? onUpdated}) {
    int tempDuration = _selectedDuration ?? 7;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Sélectionner la durée (jours)'),
          content: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NumberPicker(
                  value: tempDuration,
                  minValue: 1,
                  maxValue: 365,
                  infiniteLoop: true,
                  onChanged: (value) {
                    setStateDialog(() {
                      tempDuration = value;
                    });
                  },
                  selectedTextStyle: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurpleAccent,
                  ),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _selectedDuration = tempDuration);
                    if (onUpdated != null) onUpdated();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Valider'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchPlanning() async {
    if (_selectedStartDate == null || _selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une date et une durée'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final recipes = await _loadRecipes();
      _maxHistoryDays = recipes.length; // Update history days based on recipe count
      
      final users = await _userRepo.getUsers();
      final servings = await _loadServings();

      // Filter historical meals to only include the last N days (N = recipe count)
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: _maxHistoryDays));
      final filteredHistoryMeals = _mealHistory.entries
          .where((entry) => !entry.key.isBefore(cutoffDate))
          .expand((entry) => entry.value)
          .toList();

      final plan = MealPlanningService.generateMealPlan(
        recipes: recipes,
        servings: servings,
        users: users,
        startDate: _selectedStartDate!,
        durationDays: _selectedDuration!,
        recentMeals: filteredHistoryMeals,
      );

      setState(() {
        _generatedMealPlan = plan;
        _selectedMealDate = plan.startDate;
        _focusedDay = plan.startDate;
        _calendarFormat = null; // Reset to recalculate format
      });

      // Automatic plan saving
      final savedId = await _saveMealPlan(plan);

      // Update the plan with the saved ID
      setState(() {
        _generatedMealPlan = MealPlan(
          id: savedId,
          startDate: plan.startDate,
          durationDays: plan.durationDays,
          meals: plan.meals,
          createdAt: plan.createdAt,
        );
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Recipe>> _loadRecipes() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('recipes')
        .get();

    return Future.wait(
      snapshot.docs.map((doc) async {
        final data = doc.data();
        final ingredientsData = data['ingredients'] as List<dynamic>? ?? [];

        final ingredients = ingredientsData.map((i) {
          return RecipeIngredient(
            ingredient: Ingredient(
              id: i['ingredientId'] ?? '',
              name: i['ingredientName'] ?? 'Unknown ingredient',
            ),
            quantity: (i['quantity'] as num).toDouble(),
            unit: Unit.values.firstWhere(
              (u) => u.label == i['unit'],
              orElse: () => Unit.g,
            ),
            notes: i['notes'],
          );
        }).toList();

        return Recipe(
          id: doc.id,
          title: data['title'] ?? '',
          description: data['description'] ?? '',
          preparationTime: data['preparationTime'] ?? 0,
          cookingTime: data['cookingTime'] ?? 0,
          servings: data['servings'] ?? 1,
          category: data['category'] ?? '',
          ingredients: ingredients,
          instructions: List<String>.from(data['instructions'] ?? []),
          createdAt:
              DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
          isFavorite: data['isFavorite'] ?? false,
          rating: (data['rating'] as num?)?.toDouble() ?? 0,
          addExtraMeal: data['addExtraMeal'] ?? false,
        );
      }),
    );
  }

  Future<List<UserRecipeServing>> _loadServings() async {
    final users = await _userRepo.getUsers();
    final all = <UserRecipeServing>[];
    for (final user in users) {
      final stream = _userServingRepo.watchForUser(user.id);
      all.addAll(await stream.first);
    }
    return all;
  }

  Future<String> _saveMealPlan(MealPlan plan) async {
    setState(() => _isLoading = true);
    try {
      final savedId = await _mealPlanRepo.saveMealPlan(plan);
      if (!mounted) return savedId;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Plan sauvegardé')));
      return savedId;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMeal(Meal mealToDelete) async {
    if (_generatedMealPlan == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Supprimer ce repas ?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Voulez-vous retirer "${mealToDelete.recipe.title}" du plan ?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Supprimer', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to delete
      final indexToDelete = updatedMeals.indexWhere(
        (m) =>
            m.recipe.id == mealToDelete.recipe.id &&
            m.date == mealToDelete.date &&
            m.type == mealToDelete.type,
      );

      if (indexToDelete == -1) return;

      // If this is the first occurrence of a recipe with addExtraMeal (not a leftover)
      if (mealToDelete.recipe.addExtraMeal && !mealToDelete.isLeftoverMeal) {
        // Also remove the leftover from the next day
        final nextDay = mealToDelete.date.add(const Duration(days: 1));
        updatedMeals.removeWhere(
          (m) =>
              m.recipe.id == mealToDelete.recipe.id &&
              m.date.year == nextDay.year &&
              m.date.month == nextDay.month &&
              m.date.day == nextDay.day &&
              m.isLeftoverMeal,
        );
      }

      // If this is a leftover of a recipe with addExtraMeal
      if (mealToDelete.isLeftoverMeal && mealToDelete.recipe.addExtraMeal) {
        // Find the first occurrence (non-leftover) and update it to remove addExtraMeal flag
        final firstOccurrenceIndex = updatedMeals.indexWhere(
          (m) =>
              m.recipe.id == mealToDelete.recipe.id &&
              !m.isLeftoverMeal &&
              m.date.isBefore(mealToDelete.date),
        );

        if (firstOccurrenceIndex != -1) {
          final firstMeal = updatedMeals[firstOccurrenceIndex];

          // Create a copy of the recipe with addExtraMeal set to false
          final updatedRecipe = Recipe(
            id: firstMeal.recipe.id,
            title: firstMeal.recipe.title,
            description: firstMeal.recipe.description,
            preparationTime: firstMeal.recipe.preparationTime,
            cookingTime: firstMeal.recipe.cookingTime,
            servings: firstMeal.recipe.servings,
            category: firstMeal.recipe.category,
            ingredients: firstMeal.recipe.ingredients,
            instructions: firstMeal.recipe.instructions,
            createdAt: firstMeal.recipe.createdAt,
            isFavorite: firstMeal.recipe.isFavorite,
            rating: firstMeal.recipe.rating,
            addExtraMeal: false, // Remove the flag
          );

          // Update the meal with the new recipe
          updatedMeals[firstOccurrenceIndex] = Meal(
            recipe: updatedRecipe,
            date: firstMeal.date,
            type: firstMeal.type,
            totalServings: firstMeal.totalServings,
            userServings: firstMeal.userServings,
            recipeMultiplier: firstMeal.recipeMultiplier,
            isLeftoverMeal: firstMeal.isLeftoverMeal,
          );
        }
      }

      // Delete the main meal
      updatedMeals.removeAt(indexToDelete);

      // Update the plan
      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
      );

      // Save to database
      await _mealPlanRepo.saveMealPlan(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Repas supprimé', style: GoogleFonts.poppins()),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMealRecipe(Meal mealToUpdate, Recipe newRecipe) async {
    setState(() => _isLoading = true);
    try {
      // Check if the meal belongs to history
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final mealDate = DateTime(mealToUpdate.date.year, mealToUpdate.date.month, mealToUpdate.date.day);
      final isHistory = mealDate.isBefore(today);

      if (isHistory) {
        // Edit the meal in history
        final historyMeals = _mealHistory[mealDate] ?? [];
        final indexToUpdate = historyMeals.indexWhere(
          (m) =>
              m.recipe.id == mealToUpdate.recipe.id &&
              m.date == mealToUpdate.date &&
              m.type == mealToUpdate.type,
        );
        if (indexToUpdate == -1) return;

        // Replace the meal with the new one
        historyMeals[indexToUpdate] = Meal(
          recipe: newRecipe,
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          totalServings: newRecipe.servings,
          userServings: {},
          recipeMultiplier: 1,
          isLeftoverMeal: false,
          userSelected: true,
        );

        // Update local history
        _mealHistory[mealDate] = historyMeals;

        // Persist the change in Firestore
        await _historyRepo.addDayToHistory(mealDate, historyMeals);

        setState(() {});

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Recette historique modifiée', style: GoogleFonts.poppins()),
          ),
        );
        return;
      }

      // ...existing logic for the generated plan...
      if (_generatedMealPlan == null) return;
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to update
      final indexToUpdate = updatedMeals.indexWhere(
        (m) =>
            m.recipe.id == mealToUpdate.recipe.id &&
            m.date == mealToUpdate.date &&
            m.type == mealToUpdate.type,
      );

      if (indexToUpdate == -1) return;

      // --- CLEANUP OLD RECIPE LOGIC (Same as delete) ---

      // If previous was generating a leftover, remove that leftover
      if (mealToUpdate.recipe.addExtraMeal && !mealToUpdate.isLeftoverMeal) {
        final nextDay = mealToUpdate.date.add(const Duration(days: 1));
        updatedMeals.removeWhere(
          (m) =>
              m.recipe.id == mealToUpdate.recipe.id &&
              m.date.year == nextDay.year &&
              m.date.month == nextDay.month &&
              m.date.day == nextDay.day &&
              m.isLeftoverMeal,
        );
      }

      // If previous WAS a leftover, unflag the original
      if (mealToUpdate.isLeftoverMeal && mealToUpdate.recipe.addExtraMeal) {
        final firstOccurrenceIndex = updatedMeals.indexWhere(
          (m) =>
              m.recipe.id == mealToUpdate.recipe.id &&
              !m.isLeftoverMeal &&
              m.date.isBefore(mealToUpdate.date),
        );

        if (firstOccurrenceIndex != -1) {
          final firstMeal = updatedMeals[firstOccurrenceIndex];
          final updatedOriginRecipe = Recipe(
            id: firstMeal.recipe.id,
            title: firstMeal.recipe.title,
            description: firstMeal.recipe.description,
            preparationTime: firstMeal.recipe.preparationTime,
            cookingTime: firstMeal.recipe.cookingTime,
            servings: firstMeal.recipe.servings,
            category: firstMeal.recipe.category,
            ingredients: firstMeal.recipe.ingredients,
            instructions: firstMeal.recipe.instructions,
            createdAt: firstMeal.recipe.createdAt,
            isFavorite: firstMeal.recipe.isFavorite,
            rating: firstMeal.recipe.rating,
            addExtraMeal: false, // Remove flag
          );

          updatedMeals[firstOccurrenceIndex] = Meal(
            recipe: updatedOriginRecipe,
            date: firstMeal.date,
            type: firstMeal.type,
            totalServings: firstMeal.totalServings,
            userServings: firstMeal.userServings,
            recipeMultiplier: firstMeal.recipeMultiplier,
            isLeftoverMeal: firstMeal.isLeftoverMeal,
          );
        }
      }

      // --- UPDATE CURRENT SLOT ---

      updatedMeals[indexToUpdate] = Meal(
        recipe: newRecipe,
        date: mealToUpdate.date,
        type: mealToUpdate.type,
        totalServings: newRecipe.servings,
        userServings: {},
        recipeMultiplier: 1,
        isLeftoverMeal: false,
        userSelected: true,
      );

      // --- SAVE ---

      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
      );

      await _mealPlanRepo.saveMealPlan(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Recette modifiée', style: GoogleFonts.poppins()),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMealToPlan(
    Recipe recipe,
    DateTime date,
    MealType type,
  ) async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final mealDate = DateTime(date.year, date.month, date.day);
      final newMeal = Meal(
        recipe: recipe,
        date: date,
        type: type,
        totalServings: recipe.servings,
        userServings: {},
        recipeMultiplier: 1,
        isLeftoverMeal: false,
        userSelected: true,
      );

      if (mealDate.isBefore(today)) {
        // Add to history
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        historyMeals.add(newMeal);
        _mealHistory[mealDate] = historyMeals;
        await _historyRepo.addDayToHistory(mealDate, historyMeals);
        setState(() {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Repas historique ajouté', style: GoogleFonts.poppins())),
        );
        return;
      }

      // Add to the generated plan (existing behavior)
      if (_generatedMealPlan == null) return;
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);
      updatedMeals.add(newMeal);
      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
      );
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      setState(() {
        _generatedMealPlan = updatedPlan;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Repas ajouté', style: GoogleFonts.poppins())),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRecipeSelector({
    Meal? mealToUpdate,
    DateTime? date,
    MealType? type,
    bool requireConfirmation = true,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: RecipeSelector(
          onRecipeSelected: (newRecipe) async {
            // Check if it's a historical meal (past date, without time)
            bool isHistory = false;
            if (mealToUpdate != null) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final mealDate = DateTime(
                mealToUpdate.date.year,
                mealToUpdate.date.month,
                mealToUpdate.date.day,
              );
              isHistory = mealDate.isBefore(today);
            }
            if (mealToUpdate != null && isHistory && requireConfirmation) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Modifier un repas historique'),
                  content: Text(
                    "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Oui, modifier'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              Navigator.pop(context); // Close modal after confirmation
              _changeMealRecipe(mealToUpdate, newRecipe);
              return;
            }
            Navigator.pop(context); // Close modal (normal case)
            if (mealToUpdate != null) {
              _changeMealRecipe(mealToUpdate, newRecipe);
            } else if (date != null && type != null) {
              _addMealToPlan(newRecipe, date, type);
            }
          },
        ),
      ),
    );
  }

  /* ================= UI ================= */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _generatedMealPlan == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 16, right: 16),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => StatefulBuilder(
                        builder: (builderContext, setModalState) => Container(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(
                              builderContext,
                            ).viewInsets.bottom,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _ModernPlannerHeader(
                                  selectedStartDate: _selectedStartDate,
                                  selectedDuration: _selectedDuration,
                                  onPickStartDate: () {
                                    _pickStartDate(onDatePicked: () => setModalState(() {}));
                                  },
                                  onPickDuration: () {
                                    _pickDuration(
                                      onUpdated: () => setModalState(() {}),
                                    );
                                  },
                                  onLaunchPlanning: () {
                                    Navigator.pop(context);
                                    _launchPlanning();
                                  },
                                  isLoading: _isLoading,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6A5AE0).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Nouveau plan',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFEFFC), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      'Planificateur de repas',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_generatedMealPlan == null && !_isLoading) ...[
                        const SizedBox(height: 40),
                        Center(
                          child: _ModernPlannerHeader(
                            selectedStartDate: _selectedStartDate,
                            selectedDuration: _selectedDuration,
                            onPickStartDate: _pickStartDate,
                            onPickDuration: _pickDuration,
                            onLaunchPlanning: _launchPlanning,
                            isLoading: _isLoading,
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                      if (_generatedMealPlan != null) ...[
                        _buildModernCalendar(),
                        const SizedBox(height: 24),
                        _buildMealDetails(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildModernCalendar() {
    // Automatically choose calendar format based on plan duration (only on first load)
    if (_calendarFormat == null) {
      final startDate = _generatedMealPlan!.startDate;
      final durationDays = _generatedMealPlan!.durationDays;
      final endDate = startDate.add(Duration(days: durationDays - 1));

      // Count how many calendar weeks are spanned by checking for Mondays in the range
      // (excluding the start date itself)
      bool crossesIntoNewWeek = false;
      DateTime currentDate = startDate.add(const Duration(days: 1));

      while (currentDate.isBefore(endDate) ||
          currentDate.isAtSameMomentAs(endDate)) {
        if (currentDate.weekday == DateTime.monday) {
          crossesIntoNewWeek = true;
          break;
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }

      if (durationDays <= 7 && !crossesIntoNewWeek) {
        // 7 days or less within the same calendar week
        _calendarFormat = CalendarFormat.week;
      } else if (durationDays <= 14) {
        // 8-14 days or 7 days spanning 2 calendar weeks
        _calendarFormat = CalendarFormat.twoWeeks;
      } else {
        _calendarFormat = CalendarFormat.month;
      }
    }

    // Calculate the min/max range between history and plan
    DateTime planStart = _generatedMealPlan!.startDate;
    DateTime planEnd = planStart.add(
      Duration(days: _generatedMealPlan!.durationDays - 1),
    );
    final historyDates = _mealHistory.keys.toList();
    DateTime? historyMin = historyDates.isNotEmpty
        ? historyDates.reduce((a, b) => a.isBefore(b) ? a : b)
        : null;
    DateTime? historyMax = historyDates.isNotEmpty
        ? historyDates.reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    final firstDay = historyMin != null && historyMin.isBefore(planStart)
        ? historyMin
        : planStart;
    final lastDay = historyMax != null && historyMax.isAfter(planEnd)
        ? historyMax
        : planEnd;

    return Material(
      type: MaterialType.transparency,
      child: TableCalendar(
        startingDayOfWeek: StartingDayOfWeek.monday,
        locale: 'fr_FR',
        firstDay: firstDay,
        lastDay: lastDay,
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat!,
        availableCalendarFormats: const {
          CalendarFormat.week: 'Semaine',
          CalendarFormat.twoWeeks: '2 semaines',
          CalendarFormat.month: 'Mois',
        },
        selectedDayPredicate: (day) => isSameDay(day, _selectedMealDate),
        onDaySelected: (day, focused) {
          setState(() {
            _selectedMealDate = day;
            _focusedDay = focused;
          });
        },
        onFormatChanged: (format) {
          setState(() {
            _calendarFormat = format;
          });
        },
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          formatButtonShowsNext: false,
          titleCentered: true,
          formatButtonTextStyle: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6A5AE0),
          ),
          formatButtonDecoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6A5AE0)),
            borderRadius: BorderRadius.circular(12),
          ),
          decoration: const BoxDecoration(color: Colors.transparent),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          decoration: BoxDecoration(color: Colors.transparent),
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration: BoxDecoration(
            color: Color(0xFF6A5AE0),
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
          ),
          defaultDecoration: BoxDecoration(shape: BoxShape.circle),
          weekendDecoration: BoxDecoration(shape: BoxShape.circle),
          outsideDecoration: BoxDecoration(shape: BoxShape.circle),
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            // If the day is in history, color the background with a circle of the same size as the selected day
            final isHistory = _mealHistory.keys.any(
              (d) =>
                  d.year == day.year &&
                  d.month == day.month &&
                  d.day == day.day,
            );
            if (isHistory) {
              return Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${day.day}',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
  }

  Widget _buildMealDetails() {
    if (_selectedMealDate == null) return const SizedBox();

    // If the selected date is in history, show historical meals
    final historyMeals = _mealHistory.entries
        .firstWhere(
          (entry) =>
              entry.key.year == _selectedMealDate!.year &&
              entry.key.month == _selectedMealDate!.month &&
              entry.key.day == _selectedMealDate!.day,
          orElse: () => MapEntry(_selectedMealDate!, <Meal>[]),
        )
        .value;

    final isPastDay = _selectedMealDate!.isBefore(DateTime.now());
    final mealsOfDay = isPastDay && historyMeals.isNotEmpty
        ? historyMeals
        : (_generatedMealPlan?.meals.where((meal) {
                final d = meal.date;
                return d.year == _selectedMealDate!.year &&
                    d.month == _selectedMealDate!.month &&
                    d.day == _selectedMealDate!.day;
              }).toList() ??
              []);

    final lunchMeals = mealsOfDay
        .where((m) => m.type == MealType.lunch)
        .toList();
    final dinnerMeals = mealsOfDay
        .where((m) => m.type == MealType.dinner)
        .toList();

    Widget buildMealCard(Meal meal) {
      // Color used for both the separator and the action icon/button
      final actionColor = Colors.grey.shade400;

      return Card(
        color: Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main content (clickable to open recipe)
              Expanded(
                child: InkWell(
                  onTap: () {
                    // Compute the multiplier for addExtraMeal (fixed)
                    int? ingredientMultiplier;
                    if (meal.recipe.addExtraMeal && _generatedMealPlan != null) {
                      final nextDay = meal.date.add(const Duration(days: 1));
                      final sameRecipeNextDay = _generatedMealPlan!.meals.any((m) =>
                        m.recipe.id == meal.recipe.id &&
                        m.date.year == nextDay.year &&
                        m.date.month == nextDay.month &&
                        m.date.day == nextDay.day &&
                        m.type == meal.type &&
                        m.isLeftoverMeal
                      );
                      if (sameRecipeNextDay) {
                        ingredientMultiplier = 2;
                      }
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailPage(
                          recipe: meal.recipe,
                          ingredientMultiplier: ingredientMultiplier,
                          showAddExtraMealBadge: false,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon
                        meal.isLeftoverMeal
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.restaurant,
                                  color: Colors.orange,
                                  size: 24,
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.restaurant_menu,
                                  color: Colors.green,
                                  size: 24,
                                ),
                              ),
                        const SizedBox(width: 12),
                        // Content
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left: Title + Description + Badges
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Title with multiplier
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            meal.recipe.title,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (meal.recipeMultiplier > 1 &&
                                            !meal.isLeftoverMeal)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(
                                                0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.green,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Text(
                                              'x${meal.recipeMultiplier}',
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.green[800],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Description
                                    Text(
                                      meal.recipe.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                    // Info badges
                                    if (meal.isLeftoverMeal) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            size: 16,
                                            color: Colors.orange[700],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Restes du repas précédent',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.orange[700],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (meal.recipe.addExtraMeal &&
                                        !meal.isLeftoverMeal) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            size: 16,
                                            color: Colors.green[700],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'À cuisiner pour 2 repas',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.green[700],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Right: Servings badge
                              // Reduced margin since we have a separator now
                              Container(
                                margin: const EdgeInsets.only(
                                  left: 8,
                                  right: 16,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6A5AE0,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${meal.totalServings} pers',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF6A5AE0),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Vertical Divider
              Container(width: 2, color: actionColor),
              // Swap/Change Meal Button
              InkWell(
                onTap: () async {
                  // Check if it's a historical meal
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final mealDate = DateTime(
                    meal.date.year,
                    meal.date.month,
                    meal.date.day,
                  );
                  final isHistory = mealDate.isBefore(today);
                  if (isHistory) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Modifier un repas historique'),
                        content: Text(
                          "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Oui, modifier'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }
                  _showRecipeSelector(mealToUpdate: meal, requireConfirmation: false);
                },
                child: Container(
                  width: 50,
                  alignment: Alignment.center,
                  child: Icon(Icons.swap_horiz, color: actionColor, size: 28),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildEmptySlot(MealType mealType) {
      return Card(
        color: Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          onTap: () async {
            if (_selectedMealDate != null) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final mealDate = DateTime(
                _selectedMealDate!.year,
                _selectedMealDate!.month,
                _selectedMealDate!.day,
              );
              final isHistory = mealDate.isBefore(today);
              if (isHistory) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Ajouter un repas historique'),
                    content: Text(
                      "Ce jour fait partie de l'historique. Voulez-vous vraiment ajouter un repas ?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annuler'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Oui, ajouter'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              _showRecipeSelector(date: _selectedMealDate!, type: mealType);
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: Colors.grey[600], size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Aucun repas planifié',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LUNCH Section
          Text(
            'MIDI',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
          const SizedBox(height: 8),
          if (lunchMeals.isNotEmpty)
            ...lunchMeals.map(buildMealCard)
          else
            buildEmptySlot(MealType.lunch),

          const SizedBox(height: 16),

          // DINNER Section
          Text(
            'SOIR',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
          const SizedBox(height: 8),
          if (dinnerMeals.isNotEmpty)
            ...dinnerMeals.map(buildMealCard)
          else
            buildEmptySlot(MealType.dinner),
        ],
      ),
    );
  }
}

/* ================= COMPONENTS ================= */

class _ModernPlannerHeader extends StatelessWidget {
  final DateTime? selectedStartDate;
  final int? selectedDuration;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickDuration;
  final VoidCallback onLaunchPlanning;
  final bool isLoading;

  const _ModernPlannerHeader({
    required this.selectedStartDate,
    required this.selectedDuration,
    required this.onPickStartDate,
    required this.onPickDuration,
    required this.onLaunchPlanning,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Créer un plan de repas',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ModernSelectorCard(
                icon: Icons.date_range_rounded,
                title: 'Date de début',
                value: selectedStartDate == null
                    ? 'Choisir'
                    : '${selectedStartDate!.day}/${selectedStartDate!.month}',
                onTap: onPickStartDate,
              ),
              const SizedBox(width: 12),
              ModernSelectorCard(
                icon: Icons.timer_rounded,
                title: 'Durée',
                value: selectedDuration == null
                    ? 'Choisir'
                    : '$selectedDuration jours',
                onTap: onPickDuration,
              ),
            ],
          ),
          const SizedBox(height: 24),
          ModernGradientButton(
            label: 'Générer le plan',
            icon: Icons.auto_awesome,
            onTap: isLoading ? null : onLaunchPlanning,
          ),
        ],
      ),
    );
  }
}

class ModernSelectorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const ModernSelectorCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA), // Light greyish blue
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF6A5AE0), size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D2D2D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModernGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const ModernGradientButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF6A5AE0),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5AE0).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
