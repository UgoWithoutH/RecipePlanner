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
import '../../data/services/seed_data_service.dart';

import '../../domain/entities/ingredient.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/usecases/meal_planning_service.dart';

import 'recipe_detail_page.dart';

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
        _generatedMealPlan = plans.first;
        _selectedMealDate = plans.first.startDate;
        _focusedDay = plans.first.startDate;
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
            ingredient: Ingredient(id: i['ingredientId'], name: 'ingredient'),
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

  /* ================= UI ================= */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _generatedMealPlan == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => Container(
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
                            onPickStartDate: _pickStartDate,
                            onPickDuration: _pickDuration,
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
                );
              },
              backgroundColor: const Color(0xFF6A5AE0),
              icon: const Icon(Icons.add),
              label: Text(
                'Nouveau plan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // === NOUVEAU HEADER AVEC SAFEAREA ===
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
                      if (_generatedMealPlan == null) ...[
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
    return TableCalendar(
      firstDay: _generatedMealPlan!.startDate,
      lastDay: _generatedMealPlan!.startDate.add(
        Duration(days: _generatedMealPlan!.durationDays - 1),
      ),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(day, _selectedMealDate),
      onDaySelected: (day, focused) {
        setState(() {
          _selectedMealDate = day;
          _focusedDay = focused;
        });
      },
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
      calendarStyle: const CalendarStyle(
        selectedDecoration: BoxDecoration(
          color: Colors.deepPurple,
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

    if (mealsOfDay.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Aucun repas pour ce jour',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    final lunchMeals = mealsOfDay
        .where((m) => m.type == MealType.lunch)
        .toList();
    final dinnerMeals = mealsOfDay
        .where((m) => m.type == MealType.dinner)
        .toList();

    Widget buildMealCard(Meal meal) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          leading: meal.isLeftoverMeal
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
          title: Row(
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                meal.recipe.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
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
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${meal.totalServings} pers',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.deepPurple,
              ),
            ),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecipeDetailPage(recipe: meal.recipe),
              ),
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lunchMeals.isNotEmpty) ...[
            Text(
              'MIDI',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            ...lunchMeals.map(buildMealCard),
          ],
          if (dinnerMeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'SOIR',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            ...dinnerMeals.map(buildMealCard),
          ],
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A5AE0), Color(0xFF4FC3F7)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Créer un plan de repas',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ModernSelectorCard(
                icon: Icons.date_range,
                title: 'Date',
                value: selectedStartDate == null
                    ? 'Choisir'
                    : selectedStartDate!.toString().split(' ')[0],
                onTap: onPickStartDate,
              ),
              const SizedBox(width: 12),
              ModernSelectorCard(
                icon: Icons.timer,
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
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
