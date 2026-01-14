import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:numberpicker/numberpicker.dart';

import '../../core/constants/unit.dart';
import '../../data/repositories/firebase_ingredient_repository.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
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
  final FirebaseIngredientRepository _ingredientRepo =
      FirebaseIngredientRepository();
  final FirebaseUserRepository _userRepo = FirebaseUserRepository();
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();
  final FirebaseMealPlanRepository _mealPlanRepo = FirebaseMealPlanRepository();

  DateTime? _selectedStartDate;
  int? _selectedDuration;
  bool _isLoading = false;

  MealPlan? _generatedMealPlan;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedMealDate;
  CalendarFormat? _calendarFormat;

  @override
  void initState() {
    super.initState();
    _loadMostRecentMealPlan();
  }

  Future<void> _loadMostRecentMealPlan() async {
    setState(() => _isLoading = true);
    try {
      final plans = await _mealPlanRepo.getAllMealPlans();
      if (plans.isNotEmpty) {
        plans.sort((a, b) => b.startDate.compareTo(a.startDate));
        final loadedPlan = plans.first;
        
        // Reload full recipe details from Firestore
        final allRecipes = await _loadRecipes();
        final recipeMap = {for (var recipe in allRecipes) recipe.id: recipe};
        
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
        
        setState(() {
          _generatedMealPlan = MealPlan(
            id: loadedPlan.id,
            startDate: loadedPlan.startDate,
            durationDays: loadedPlan.durationDays,
            meals: mealsWithFullRecipes,
            createdAt: loadedPlan.createdAt,
          );
          
          _selectedMealDate = _generatedMealPlan!.startDate;
          _focusedDay = _generatedMealPlan!.startDate;
          _calendarFormat = null; // Reset to recalculate format
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedStartDate = picked);
  }

  void _pickDuration() {
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
                    setState(() => _selectedDuration = tempDuration);
                    Navigator.pop(context);
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
      final users = await _userRepo.getUsers();
      final servings = await _loadServings();

      final plan = MealPlanningService.generateMealPlan(
        recipes: recipes,
        servings: servings,
        users: users,
        startDate: _selectedStartDate!,
        durationDays: _selectedDuration!,
      );

      setState(() {
        _generatedMealPlan = plan;
        _selectedMealDate = plan.startDate;
        _focusedDay = plan.startDate;
        _calendarFormat = null; // Reset to recalculate format
      });

      // Sauvegarde automatique du plan
      await _saveMealPlan(plan);
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

  Future<void> _saveMealPlan(MealPlan plan) async {
    setState(() => _isLoading = true);
    try {
      await _mealPlanRepo.saveMealPlan(plan);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Plan sauvegardé')));
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
      final indexToDelete = updatedMeals.indexWhere((m) =>
          m.recipe.id == mealToDelete.recipe.id &&
          m.date == mealToDelete.date &&
          m.type == mealToDelete.type);

      if (indexToDelete == -1) return;

      // If this is the first occurrence of a recipe with addExtraMeal (not a leftover)
      if (mealToDelete.recipe.addExtraMeal && !mealToDelete.isLeftoverMeal) {
        // Also remove the leftover from the next day
        final nextDay = mealToDelete.date.add(const Duration(days: 1));
        updatedMeals.removeWhere((m) =>
            m.recipe.id == mealToDelete.recipe.id &&
            m.date.year == nextDay.year &&
            m.date.month == nextDay.month &&
            m.date.day == nextDay.day &&
            m.isLeftoverMeal);
      }

      // If this is a leftover of a recipe with addExtraMeal
      if (mealToDelete.isLeftoverMeal && mealToDelete.recipe.addExtraMeal) {
        // Find the first occurrence (non-leftover) and update it to remove addExtraMeal flag
        final firstOccurrenceIndex = updatedMeals.indexWhere((m) =>
            m.recipe.id == mealToDelete.recipe.id &&
            !m.isLeftoverMeal &&
            m.date.isBefore(mealToDelete.date));

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
          content: Text(
            '✅ Repas supprimé',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMealRecipe(Meal mealToUpdate, Recipe newRecipe) async {
    if (_generatedMealPlan == null) return;

    setState(() => _isLoading = true);
    try {
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to update
      final indexToUpdate = updatedMeals.indexWhere((m) =>
          m.recipe.id == mealToUpdate.recipe.id &&
          m.date == mealToUpdate.date &&
          m.type == mealToUpdate.type);

      if (indexToUpdate == -1) return;

      // --- CLEANUP OLD RECIPE LOGIC (Same as delete) ---
      
      // If previous was generating a leftover, remove that leftover
      if (mealToUpdate.recipe.addExtraMeal && !mealToUpdate.isLeftoverMeal) {
        final nextDay = mealToUpdate.date.add(const Duration(days: 1));
        updatedMeals.removeWhere((m) =>
            m.recipe.id == mealToUpdate.recipe.id &&
            m.date.year == nextDay.year &&
            m.date.month == nextDay.month &&
            m.date.day == nextDay.day &&
            m.isLeftoverMeal);
      }

      // If previous WAS a leftover, unflag the original
      if (mealToUpdate.isLeftoverMeal && mealToUpdate.recipe.addExtraMeal) {
        final firstOccurrenceIndex = updatedMeals.indexWhere((m) =>
            m.recipe.id == mealToUpdate.recipe.id &&
            !m.isLeftoverMeal &&
            m.date.isBefore(mealToUpdate.date));

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
      
      // We are "swapping" the recipe. 
      // Resetting multiplier to 1 and isLeftover to false ensures a clean slate.
      // (Unless we want to keep logic, but new recipe might not have same servings).
      
      updatedMeals[indexToUpdate] = Meal(
        recipe: newRecipe,
        date: mealToUpdate.date,
        type: mealToUpdate.type,
        totalServings: newRecipe.servings, // Default to recipe servings or user servings logic? 
        // For simplicity, let's just use the recipe base servings or 
        // if we want to be smart, we'd recalculate based on user count but that's complex here.
        // Let's keep it simple: just the recipe.
        // Wait, 'totalServings' in Meal usually comes from aggregation.
        // Let's assume for now we take the recipe servings or keep the previous total?
        // Let's Recalculate based on users? 
        // Actually, let's just use newRecipe.servings as a baseline for the display.
        userServings: {}, // Reset user specific servings override? Or copy? Safe to reset.
        recipeMultiplier: 1,
        isLeftoverMeal: false,
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
          content: Text(
            '✅ Recette modifiée',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMealToPlan(Recipe recipe, DateTime date, MealType type) async {
    if (_generatedMealPlan == null) return;

    setState(() => _isLoading = true);
    try {
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      final newMeal = Meal(
        recipe: recipe,
        date: date,
        type: type,
        totalServings: recipe.servings,
        userServings: {},
        recipeMultiplier: 1,
        isLeftoverMeal: false,
      );

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
        SnackBar(
          content: Text(
            '✅ Repas ajouté',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRecipeSelector({Meal? mealToUpdate, DateTime? date, MealType? type}) {
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
          onRecipeSelected: (newRecipe) {
            Navigator.pop(context); // Close modal
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
                      builder: (context) => StatefulBuilder(
                        builder: (context, setModalState) => Container(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
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
                                  onPickStartDate: () async {
                                    await _pickStartDate();
                                    setModalState(() {});
                                  },
                                  onPickDuration: () {
                                    _pickDuration();
                                    setModalState(() {});
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
                        )
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
           // Background Gradient at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFEFFC), Colors.white], // Very subtle purple fading to white
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                // === NEW HEADER WITH SAFEAREA ===
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
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

    return TableCalendar(
      firstDay: _generatedMealPlan!.startDate,
      lastDay: _generatedMealPlan!.startDate.add(
        Duration(days: _generatedMealPlan!.durationDays - 1),
      ),
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
      ),
    );
  }

  Widget _buildMealDetails() {
    if (_generatedMealPlan == null || _selectedMealDate == null)
      return const SizedBox();

    final mealsOfDay = _generatedMealPlan!.meals.where((meal) {
      final d = meal.date;
      return d.year == _selectedMealDate!.year &&
          d.month == _selectedMealDate!.month &&
          d.day == _selectedMealDate!.day;
    }).toList();

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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailPage(recipe: meal.recipe),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                                        if (meal.recipeMultiplier > 1 && !meal.isLeftoverMeal)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.green, width: 1.5),
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
                                    if (meal.recipe.addExtraMeal && !meal.isLeftoverMeal) ...[
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
                                margin: const EdgeInsets.only(left: 8, right: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6A5AE0).withOpacity(0.15),
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
              Container(
                width: 2,
                color: actionColor,
              ),
              // Swap/Change Meal Button
              InkWell(
                onTap: () => _showRecipeSelector(mealToUpdate: meal),
                child: Container(
                  width: 50,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.swap_horiz,
                    color: actionColor,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildEmptySlot(MealType mealType) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.grey[50],
        child: InkWell(
          onTap: () {
            if (_selectedMealDate != null) {
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
                  child: Icon(
                    Icons.add,
                    color: Colors.grey[600],
                    size: 24,
                  ),
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
          // MIDI Section
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
          
          // SOIR Section
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
          )
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
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
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
            )
          ]
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
