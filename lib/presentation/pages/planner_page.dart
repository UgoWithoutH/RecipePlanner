import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/unit.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_meal_history_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/notification_settings_repository.dart';
import '../../data/services/notification_service.dart';

import '../../domain/entities/ingredient.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/usecases/meal_planning_service.dart';
import '../../domain/usecases/shopping_list_generator.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/group_repository.dart';

import 'recipe_detail_page.dart';
import 'meal_plan_notifications_page.dart';
import '../widgets/recipe_selector.dart';
import '../widgets/pantry_input_dialog.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();
  final FirebaseMealPlanRepository _mealPlanRepo = FirebaseMealPlanRepository();
  final FirebaseMealHistoryRepository _historyRepo =
      FirebaseMealHistoryRepository();

  int _maxHistoryDays = 30; // Default value, recalculated based on recipe count

  DateTime? _selectedStartDate = DateTime.now();
  int? _selectedDuration = 7;
  Set<String> _selectedCategories = {}; // category IDs
  List<RecipeIngredient> _pantryIngredients = [];
  
  // Stores ID -> {name, color}
  Map<String, Map<String, dynamic>> _categoryDataById = {};
  
  bool _isLoading = false;

  MealPlan? _generatedMealPlan;
  Map<DateTime, List<Meal>> _mealHistory = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedMealDate;
  CalendarFormat? _calendarFormat;

  /// ID de la recette en cours de chargement avant navigation (null = aucune)
  String? _loadingRecipeId;

  /// Banned recipes per slot for the auto-change feature.
  /// Key: slot key (date_mealType), Value: set of banned recipe IDs.
  final Map<String, Set<String>> _autoChangeBannedRecipes = {};

  static const _kPrefKeyCategories = 'selected_category_ids';
  static const _kPrefKeyDuration = 'planner_duration_days';

  @override
  void initState() {
    super.initState();
    _loadAllCategories();
    _loadSavedPreferences();
    _loadMostRecentMealPlanAndHistory();
  }

  Future<void> _loadAllCategories() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('groupId', isEqualTo: groupId)
        .get();
    
    final allCategories = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['name'] as String? ?? '').trim(),
        'color': data['color'] is int ? data['color'] as int : 0xFF6A5AE0,
      };
    }).where((e) => (e['name'] as String).isNotEmpty).toList();

    if (mounted) {
      setState(() {
        _categoryDataById = {
          for (final e in allCategories) e['id'] as String: e
        };
      });
    }
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load categories
    final savedCats = prefs.getStringList(_kPrefKeyCategories);
    if (savedCats != null && savedCats.isNotEmpty && mounted) {
      setState(() => _selectedCategories = savedCats.toSet());
    }

    // Load duration
    final savedDuration = prefs.getInt(_kPrefKeyDuration);
    if (savedDuration != null && mounted) {
      setState(() => _selectedDuration = savedDuration);
    }
  }

  Future<void> _saveCategories(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKeyCategories, ids.toList());
  }

  Future<void> _saveDuration(int duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefKeyDuration, duration);
  }

  Future<void> _loadMostRecentMealPlanAndHistory() async {
    setState(() => _isLoading = true);
    try {
      // Load recipe count to calculate the history window size
      final allRecipes = await _loadRecipes();
      _maxHistoryDays = allRecipes.length;

      final plans = await _mealPlanRepo.getAllMealPlans();
      if (plans.isNotEmpty) {
        plans.sort((a, b) => b.startDate.compareTo(a.startDate));
        final loadedPlan = plans.first;
        // The plan already contains all card-display data (description, category…)
        // persisted in Firestore — no recipeMap enrichment needed.
        _generatedMealPlan = loadedPlan;
        
        // Restore context from the plan
        if (loadedPlan.selectedCategories.isNotEmpty) {
          _selectedCategories = loadedPlan.selectedCategories.toSet();
        }
        if (loadedPlan.pantryItems.isNotEmpty) {
          _pantryIngredients = List.from(loadedPlan.pantryItems);
        }

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
        // Planifie silencieusement les notifications (pour tous les utilisateurs)
        _autoScheduleNotifications(loadedPlan).ignore();
      }
      // Load history into state (stubs are fine here; detail page lazy-loads)
      final rawHistory = await _historyRepo.getHistory();
      _mealHistory = rawHistory;
      setState(() {});
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickStartDate({VoidCallback? onDatePicked}) async {
    DateTime tempSelectedDate = _selectedStartDate ?? DateTime.now();
    DateTime focusedDay = tempSelectedDate;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Sélectionnez une date de début',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 380, // Hauteur fixe pour éviter les sauts lors du changement de mois
                    child: TableCalendar(
                      shouldFillViewport: true,
                      locale: 'fr_FR',
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: focusedDay,
                      currentDay: DateTime.now(),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        leftChevronIcon:
                            const Icon(Icons.chevron_left, color: Color(0xFF6A5AE0)),
                        rightChevronIcon:
                            const Icon(Icons.chevron_right, color: Color(0xFF6A5AE0)),
                      ),
                      calendarStyle: const CalendarStyle(
                        selectedDecoration: BoxDecoration(
                          color: Color(0xFF6A5AE0),
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Color(0xFF6A5AE0),
                          shape: BoxShape.circle,
                        ), 
                        todayTextStyle: TextStyle(color: Colors.white),
                      ),
                      selectedDayPredicate: (day) =>
                          isSameDay(tempSelectedDate, day),
                      onDaySelected: (selectedDay, focused) {
                        setStateSheet(() {
                          tempSelectedDate = selectedDay;
                          focusedDay = focused;
                        });
                      },
                      onPageChanged: (focused) {
                        setStateSheet(() {
                          focusedDay = focused;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _selectedStartDate = tempSelectedDate);
                        if (onDatePicked != null) onDatePicked();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A5AE0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Valider',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickCategories({VoidCallback? onUpdated}) async {
    // Load categories from the categories collection (name + ID)
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('groupId', isEqualTo: groupId)
        .get();
    
    final allCategories = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['name'] as String? ?? '').trim(),
        'color': data['color'] is int ? data['color'] as int : 0xFF6A5AE0,
      };
    }).where((e) => (e['name'] as String).isNotEmpty).toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    // Update local data map
    final dataById = <String, Map<String, dynamic>>{
      for (final e in allCategories) e['id'] as String: e
    };

    if (!mounted) return;

    final validCategoryIds = allCategories.map((e) => e['id'] as String).toSet();
    final tempSelected = Set<String>.from(_selectedCategories.where((id) => validCategoryIds.contains(id)));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isAllSelected = tempSelected.length == validCategoryIds.length;
          final isNoneSelected = tempSelected.isEmpty;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // --- Header ---
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0).withOpacity(0.05),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.category_rounded, color: Color(0xFF6A5AE0), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filtrer par catégorie',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              Text(
                                'Sélectionnez vos préférences',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),

                  // --- Quick Actions ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isNoneSelected ? null : () => setStateDialog(() => tempSelected.clear()),
                            icon: const Icon(Icons.clear_all_rounded, size: 18),
                            label: const Text('Tout décocher'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isAllSelected ? null : () => setStateDialog(() => tempSelected.addAll(validCategoryIds)),
                            icon: const Icon(Icons.select_all_rounded, size: 18),
                            label: const Text('Tout cocher'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6A5AE0),
                              side: const BorderSide(color: Color(0xFF6A5AE0)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // --- Scrollable Content ---
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: allCategories.map((entry) {
                          final id = entry['id'] as String;
                          final name = entry['name'] as String;
                          final colorVal = entry['color'] as int;
                          final baseColor = Color(colorVal);

                          final isSelected = tempSelected.contains(id);
                          
                          // Improve contrast for text
                          final hsl = HSLColor.fromColor(baseColor);
                          final startLightness = hsl.lightness;
                          final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                          final textColor = hsl.withLightness(textLightness).toColor();

                          return InkWell(
                            onTap: () {
                              setStateDialog(() {
                                if (isSelected) {
                                  tempSelected.remove(id);
                                } else {
                                  tempSelected.add(id);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? baseColor.withOpacity(0.35) 
                                    : baseColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected 
                                      ? baseColor.withOpacity(0.5) 
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // --- Bottom Validation Bar ---
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A5AE0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          tempSelected.isEmpty 
                              ? 'Aucun filtre (Tout voir)' 
                              : isAllSelected
                                  ? 'Toutes'
                                  : 'Valider (${tempSelected.length})',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        setState(() {
          _selectedCategories = tempSelected;
          _categoryDataById.addAll(dataById);
        });
      }
      await _saveCategories(tempSelected);
      if (onUpdated != null) onUpdated();
    }
  }

  Future<void> _pickPantryItems({VoidCallback? onUpdated}) async {
    final result = await showDialog<List<RecipeIngredient>>(
      context: context,
      builder: (context) => PantryInputDialog(initialItems: _pantryIngredients),
    );

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _pantryIngredients = result;
      });
      if (onUpdated != null) {
        onUpdated();
      }
    }
  }

  void _pickDuration({VoidCallback? onUpdated}) {
    int tempDuration = _selectedDuration ?? 7;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Durée du planning',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Display value
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        tempDuration.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6A5AE0),
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tempDuration > 1 ? 'jours' : 'jour',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF6A5AE0),
                      inactiveTrackColor: Colors.grey[200],
                      thumbColor: const Color(0xFF6A5AE0),
                      overlayColor: const Color(0xFF6A5AE0).withOpacity(0.2),
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: tempDuration.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: (val) {
                        setStateSheet(() => tempDuration = val.round());
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Quick presets
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [3, 5, 7, 10, 14].map((days) {
                       final isSelected = tempDuration == days;
                       return InkWell(
                         onTap: () => setStateSheet(() => tempDuration = days),
                         borderRadius: BorderRadius.circular(12),
                         child: AnimatedContainer(
                           duration: const Duration(milliseconds: 200),
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                           decoration: BoxDecoration(
                             color: isSelected ? const Color(0xFF6A5AE0) : Colors.grey[100],
                             borderRadius: BorderRadius.circular(12),
                             border: Border.all(
                               color: isSelected ? const Color(0xFF6A5AE0) : Colors.transparent
                             ),
                           ),
                           child: Text(
                             '$days j',
                             style: GoogleFonts.poppins(
                               fontWeight: FontWeight.w600,
                               color: isSelected ? Colors.white : Colors.grey[700],
                             ),
                           ),
                         ),
                       );
                    }).toList(),
                  ),

                  const SizedBox(height: 32),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                         setState(() => _selectedDuration = tempDuration);
                         _saveDuration(tempDuration);
                         if (onUpdated != null) onUpdated();
                         Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A5AE0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Valider',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _launchPlanning() async {
    if (_selectedStartDate == null || _selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'Veuillez sélectionner une date et une durée',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF6A5AE0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    // New plan — clear all auto-change bans
    _autoChangeBannedRecipes.clear();
    try {
      final allRecipes = await _loadRecipes();
      // History duration is always based on the total number of recipes (all categories)
      _maxHistoryDays = allRecipes.length;

      // Apply category filter for planning only (not for history duration)
      // Only consider categories that exist in our loaded map (ignores deleted categories)
      final validSelectedCategories = _selectedCategories.where((id) => _categoryDataById.containsKey(id)).toSet();

      final recipes = validSelectedCategories.isEmpty
          ? allRecipes
          : allRecipes.where((r) => r.categoryIds.any((c) => validSelectedCategories.contains(c))).toList();

      if (recipes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette trouvée pour les catégories sélectionnées.',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.9), // Slightly different or same? Let's use same theme color.
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              elevation: 4,
            ),
          );
        }
        return;
      }

      final servings = await _loadServings();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Résoudre les noms d'ingrédients (stockés séparément dans Firestore)
      // Les recettes ont ingredient.name = '' par défaut après fetchAllRecipes()
      final allIngredientIds = recipes
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final recipesWithNames = recipes.map((recipe) {
        final resolvedIngredients = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolvedIngredients);
      }).toList();

      // Filter historical meals to only include the last N days (N = total recipe count)
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: _maxHistoryDays));
      final currentUserIds = servings.map((s) => s.userId).toSet();
      final filteredHistoryMeals = _mealHistory.entries
          .where((entry) => !entry.key.isBefore(cutoffDate))
          .expand((entry) => entry.value)
          // Discard meals whose userServings belong to stale/deleted users.
          // This prevents leftover injection from old seed data (e.g. userA/userB)
          // when the current user set has changed.
          .where((meal) => meal.userServings.isEmpty ||
              meal.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      final plan = MealPlanningService.generateMealPlan(
        recipes: recipesWithNames,
        servings: servings,
        users: users,
        startDate: _selectedStartDate!,
        durationDays: _selectedDuration!,
        recentMeals: filteredHistoryMeals,
        pantryItems: _pantryIngredients,
        selectedCategories: _selectedCategories.toList(),
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
          pantryItems: plan.pantryItems,
          selectedCategories: plan.selectedCategories,
        );
      });

      // Planifie silencieusement les notifications pour ce nouveau plan
      _autoScheduleNotifications(_generatedMealPlan!).ignore();

    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Recipe>> _loadRecipes() async {
    return FirebaseRecipeRepository().fetchAllRecipes();
  }

  /// Planifie silencieusement les notifications locales pour [plan] en utilisant
  /// les préférences sauvegardées de l'utilisateur courant.
  /// Appelée à chaque chargement/génération de plan — remplace les notifs existantes.
  Future<void> _autoScheduleNotifications(MealPlan plan) async {
    try {
      final settings = await NotificationSettingsRepository().load();
      final notifService = NotificationService();
      final granted = await notifService.requestPermissions();
      if (!granted) return;

      final now = DateTime.now();
      final effectiveDays = settings.effectiveNotificationDaysForPlan(
          plan.id, plan.durationDays);

      // Jours activés ET dont la notification est dans le futur
      final activeDays = <int>{};
      for (int i = 0; i < plan.durationDays; i++) {
        if (!effectiveDays[i]) continue;
        final planDay = plan.startDate.add(Duration(days: i));
        final notifyDay = planDay.add(Duration(days: settings.offsetDays));
        final notifyDateTime = DateTime(
          notifyDay.year, notifyDay.month, notifyDay.day,
          settings.time.hour, settings.time.minute,
        );
        if (notifyDateTime.isAfter(now)) activeDays.add(i);
      }

      if (activeDays.isEmpty) return;

      await notifService.scheduleMealPlanNotifications(
        plan: plan,
        notificationTime: settings.time,
        activeDays: activeDays,
        offsetDays: settings.offsetDays,
      );
    } catch (_) {
      // Silencieux — ne doit pas bloquer l'UI
    }
  }

  String _slotKey(DateTime date, MealType type) =>
      '${date.year}-${date.month}-${date.day}_${type.name}';

  /// Automatically picks a new recipe for [mealToChange] using the planning
  /// algorithm, accumulating banned recipes on repeated presses.
  Future<void> _autoChangeMealRecipe(Meal mealToChange) async {
    if (_generatedMealPlan == null) return;
    setState(() => _isLoading = true);
    try {
      final slotKey = _slotKey(mealToChange.date, mealToChange.type);

      // Accumulate bans for this slot
      final banned = _autoChangeBannedRecipes.putIfAbsent(slotKey, () => {});
      final wasAlreadyBanned = banned.contains(mealToChange.recipe.id);
      banned.add(mealToChange.recipe.id);

      final allRecipes = await _loadRecipes();
      final servings = await _loadServings();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Exclude banned recipes so the algo can't pick them
      final candidateRecipes = allRecipes
          .where((r) => !banned.contains(r.id))
          .toList();

      // All recipes have been seen — clear the ban cache and notify user
      if (candidateRecipes.isEmpty) {
        banned.clear(); // Reset so the user can shuffle again from scratch
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Toutes les recettes ont été proposées. Le cache a été réinitialisé.',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF6A5AE0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );
        return;
      }

      // If this is the first occurrence of an addExtraMeal recipe, check whether
      // the leftover (second occurrence) is still present in the plan and warn the user.
      // Only show the dialog the first time (not on repeated shuffles after "Annuler").
      if (!wasAlreadyBanned && mealToChange.recipe.addExtraMeal && !mealToChange.isLeftoverMeal) {
        final nextDay = mealToChange.date.add(const Duration(days: 1));
        final leftoverExists = _generatedMealPlan!.meals.any((m) =>
            m.recipe.id == mealToChange.recipe.id &&
            m.date.year == nextDay.year &&
            m.date.month == nextDay.month &&
            m.date.day == nextDay.day &&
            m.isLeftoverMeal);

        if (leftoverExists) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.info_outline, color: Color(0xFF6A5AE0), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Recette cuisinée pour 2 repas',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Cette recette est prévue pour 2 repas (aujourd\'hui + lendemain). '
                'Remplacer supprimera également le repas du lendemain.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                  ),
                  child: Text('Remplacer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
          if (confirmed != true) {
            // User cancelled -- remove from banned so the dialog shows again next time
            banned.remove(mealToChange.recipe.id);
            return;
          }
          setState(() => _isLoading = true);
        }
      }

      // Run the planning algorithm for a 1-day window starting on the meal's date.
      // Pass all other plan slots as recentMeals so the algo diversifies relative
      // to everything already placed (past + future), using the shuffled slot as pivot.
      final currentUserIds = users.map((u) => u.id).toSet();
      final filteredHistory = _mealHistory.entries
          .expand((e) => e.value)
          .where((m) => m.userServings.isEmpty ||
              m.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      final otherPlanMeals = _generatedMealPlan!.meals.where((m) =>
          !(m.date.year == mealToChange.date.year &&
            m.date.month == mealToChange.date.month &&
            m.date.day == mealToChange.date.day &&
            m.type == mealToChange.type)).toList();

      // Exclude banned addExtraMeal meals from recentMeals so the algo's
      // "historical leftover injection" block cannot reinstate a banned recipe
      // into the shuffled slot (it runs before scoring and ignores candidateRecipes).
      final recentMealsForAlgo = [...filteredHistory, ...otherPlanMeals]
          .where((m) => !(banned.contains(m.recipe.id) && m.recipe.addExtraMeal))
          .toList();

      final tempPlan = MealPlanningService.generateMealPlan(
        recipes: candidateRecipes,
        servings: servings,
        users: users,
        startDate: mealToChange.date,
        durationDays: 1,
        recentMeals: recentMealsForAlgo,
        pantryItems: _pantryIngredients,
        selectedCategories: _selectedCategories.toList(),
        referenceDate: mealToChange.date,
      );

      // Pick the meal for the correct type
      final newMeal = tempPlan.meals.where((m) => m.type == mealToChange.type).firstOrNull;
      if (newMeal == null) return;

      // Clear bans for all OTHER slots; keep accumulating for this slot
      _autoChangeBannedRecipes.removeWhere((key, _) => key != slotKey);

      setState(() => _isLoading = false);
      await _changeMealRecipe(mealToChange, newMeal.recipe, showSnackbar: false);

      // If the new recipe has addExtraMeal=true, handle leftover logic.
      if (newMeal.recipe.addExtraMeal && _generatedMealPlan != null) {
        // Check if the previous day already has the same recipe (non-leftover).
        // In that case, the current slot should become a leftover of the previous day.
        final prevDay = mealToChange.date.subtract(const Duration(days: 1));
        final prevDayHasSameRecipe = _generatedMealPlan!.meals.any((m) =>
            m.recipe.id == newMeal.recipe.id &&
            m.date.year == prevDay.year &&
            m.date.month == prevDay.month &&
            m.date.day == prevDay.day &&
            m.type == mealToChange.type &&
            !m.isLeftoverMeal);

        if (prevDayHasSameRecipe) {
          // Mark the current slot as a leftover of the previous day's meal.
          final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);
          final currentIndex = updatedMeals.indexWhere((m) =>
              m.recipe.id == newMeal.recipe.id &&
              m.date.year == mealToChange.date.year &&
              m.date.month == mealToChange.date.month &&
              m.date.day == mealToChange.date.day &&
              m.type == mealToChange.type);
          if (currentIndex != -1) {
            updatedMeals[currentIndex] = Meal(
              recipe: newMeal.recipe,
              date: mealToChange.date,
              type: mealToChange.type,
              totalServings: updatedMeals[currentIndex].totalServings,
              userServings: updatedMeals[currentIndex].userServings,
              recipeMultiplier: updatedMeals[currentIndex].recipeMultiplier,
              isLeftoverMeal: true,
            );
            final updatedPlan = MealPlan(
              id: _generatedMealPlan!.id,
              startDate: _generatedMealPlan!.startDate,
              durationDays: _generatedMealPlan!.durationDays,
              meals: updatedMeals,
              createdAt: _generatedMealPlan!.createdAt,
              pantryItems: _generatedMealPlan!.pantryItems,
              selectedCategories: _generatedMealPlan!.selectedCategories,
            );
            await _mealPlanRepo.saveMealPlan(updatedPlan);
            await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
            setState(() => _generatedMealPlan = updatedPlan);
          }
        } else {
          // No previous-day same recipe — create a leftover on the next day if empty.
          final nextDay = mealToChange.date.add(const Duration(days: 1));
          final nextDaySlotOccupied = _generatedMealPlan!.meals.any((m) =>
              m.date.year == nextDay.year &&
              m.date.month == nextDay.month &&
              m.date.day == nextDay.day &&
              m.type == mealToChange.type);

          if (!nextDaySlotOccupied) {
            final leftover = Meal(
              recipe: newMeal.recipe,
              date: nextDay,
              type: mealToChange.type,
              totalServings: newMeal.totalServings,
              userServings: newMeal.userServings,
              recipeMultiplier: newMeal.recipeMultiplier,
              isLeftoverMeal: true,
            );
            final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals)..add(leftover);
            final updatedPlan = MealPlan(
              id: _generatedMealPlan!.id,
              startDate: _generatedMealPlan!.startDate,
              durationDays: _generatedMealPlan!.durationDays,
              meals: updatedMeals,
              createdAt: _generatedMealPlan!.createdAt,
              pantryItems: _generatedMealPlan!.pantryItems,
              selectedCategories: _generatedMealPlan!.selectedCategories,
            );
            await _mealPlanRepo.saveMealPlan(updatedPlan);
            await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
            setState(() => _generatedMealPlan = updatedPlan);
          }
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Navigue vers RecipeDetailPage avec l'ID de la recette.
  /// Auto-fills an empty meal slot by picking a recipe with the planning algorithm.
  Future<void> _autoFillEmptySlot(DateTime date, MealType type) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allRecipes = await _loadRecipes();
      final servings = await _loadServings();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Apply category filter (same as _launchPlanning)
      final validSelectedCategories = _selectedCategories
          .where((id) => _categoryDataById.containsKey(id))
          .toSet();
      final filteredRecipes = validSelectedCategories.isEmpty
          ? allRecipes
          : allRecipes
              .where((r) => r.categoryIds.any((c) => validSelectedCategories.contains(c)))
              .toList();

      if (filteredRecipes.isEmpty) return;

      final currentUserIds = servings.map((s) => s.userId).toSet();
      final filteredHistory = _mealHistory.entries
          .expand((e) => e.value)
          .where((m) => m.userServings.isEmpty ||
              m.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      final otherPlanMeals = _generatedMealPlan?.meals
          .where((m) => !(m.date.year == date.year &&
              m.date.month == date.month &&
              m.date.day == date.day &&
              m.type == type))
          .toList() ??
          [];

      final tempPlan = MealPlanningService.generateMealPlan(
        recipes: filteredRecipes,
        servings: servings,
        users: users,
        startDate: date,
        durationDays: 1,
        recentMeals: [...filteredHistory, ...otherPlanMeals],
        pantryItems: _pantryIngredients,
        selectedCategories: _selectedCategories.toList(),
        referenceDate: date,
      );

      final newMeal = tempPlan.meals.where((m) => m.type == type).firstOrNull;
      if (newMeal == null) return;

      setState(() => _isLoading = false);
      await _addMealToPlan(newMeal.recipe, date, type);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openRecipeDetail(Meal meal) {
    // Calcul du multiplicateur pour les restes
    int? ingredientMultiplier;
    // On utilise meal.recipe.addExtraMeal si disponible, sinon on suppose false temporairement
    // Le détail chargera la vraie valeur, mais pour le multiplicateur ici on fait au mieux.
    if (meal.recipe.addExtraMeal && _generatedMealPlan != null) {
        final nextDay = meal.date.add(const Duration(days: 1));
        // Check if same recipe is used next day as a leftover
        // Note: This logic depends on the current plan state in memory
        final sameRecipeNextDay = _generatedMealPlan!.meals.any((m) {
          final isSameId = m.recipe.id == meal.recipe.id;
          final isNextDay = m.date.year == nextDay.year && 
                            m.date.month == nextDay.month && 
                            m.date.day == nextDay.day;
          // We assume if it's the same recipe next day, it's a leftover/extra meal
          return isSameId && isNextDay;
        });
        
        if (sameRecipeNextDay) {
          ingredientMultiplier = 2;
        }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: meal.recipe.id,
          initialRecipe: meal.recipe,
          ingredientMultiplier: ingredientMultiplier,
          showAddExtraMealBadge: false,
        ),
      ),
    ).then((_) {
      // Refresh planner data when returning from detail, as recipe might have been edited
      _loadMostRecentMealPlanAndHistory();
    });
  }

  Future<List<UserRecipeServing>> _loadServings() async {
    return _userServingRepo.fetchAllGroupServings();
  }

  Future<String> _saveMealPlan(MealPlan plan) async {
    setState(() => _isLoading = true);
    try {
      final savedId = await _mealPlanRepo.saveMealPlan(plan);
      
      // Update shopping list (pass pantryItems so they are subtracted from the list)
      final planForShoppingList = MealPlan(
        id: savedId,
        startDate: plan.startDate,
        durationDays: plan.durationDays,
        meals: plan.meals,
        createdAt: plan.createdAt,
        pantryItems: plan.pantryItems,
        selectedCategories: plan.selectedCategories,
      );
      
      await ShoppingListGenerator().generateAndSaveShoppingList(planForShoppingList);

      if (!mounted) return savedId;
      // Removed the saved snackbar confirmation
      return savedId;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMeal(Meal mealToDelete) async {
    if (_generatedMealPlan == null) return;

    // Vérifie si une deuxième occurrence (restes) existe le lendemain
    final nextDay = mealToDelete.date.add(const Duration(days: 1));
    final hasLeftover = mealToDelete.recipe.addExtraMeal &&
        !mealToDelete.isLeftoverMeal &&
        _generatedMealPlan!.meals.any((m) =>
            m.recipe.id == mealToDelete.recipe.id &&
            m.date.year == nextDay.year &&
            m.date.month == nextDay.month &&
            m.date.day == nextDay.day &&
            m.isLeftoverMeal);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: Color(0xFF6A5AE0), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Supprimer ce repas ?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voulez-vous retirer "${mealToDelete.recipe.title}" du plan ?',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
            ),
            if (hasLeftover) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cette recette est prévue en deux fois : le repas du lendemain (restes) sera également retiré du plan.',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A5AE0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to delete (slot = date + type + isLeftoverMeal).
      final indexToDelete = updatedMeals.indexWhere(
        (m) =>
            m.date.year == mealToDelete.date.year &&
            m.date.month == mealToDelete.date.month &&
            m.date.day == mealToDelete.date.day &&
            m.type == mealToDelete.type &&
            m.isLeftoverMeal == mealToDelete.isLeftoverMeal,
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

      // Delete the main meal
      updatedMeals.removeAt(indexToDelete);

      // Update the plan
      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
      );

      // Save to database
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Repas supprimé', style: GoogleFonts.poppins(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMealRecipe(Meal mealToUpdate, Recipe newRecipe, {bool showSnackbar = true}) async {
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
              m.date.year == mealToUpdate.date.year &&
              m.date.month == mealToUpdate.date.month &&
              m.date.day == mealToUpdate.date.day &&
              m.type == mealToUpdate.type &&
              m.recipe.id == mealToUpdate.recipe.id,
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
        if (showSnackbar)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Recette historique modifiée', style: GoogleFonts.poppins(color: Colors.white))),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );
        return;
      }

      // ...existing logic for the generated plan...
      if (_generatedMealPlan == null) return;
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);

      // Find the index of the meal to update.
      // Identify the slot by (date, type, isLeftoverMeal) — not by recipe.id —
      // so the lookup is robust even when the plan has been reloaded from Firestore.
      final indexToUpdate = updatedMeals.indexWhere(
        (m) =>
            m.date.year == mealToUpdate.date.year &&
            m.date.month == mealToUpdate.date.month &&
            m.date.day == mealToUpdate.date.day &&
            m.type == mealToUpdate.type &&
            m.isLeftoverMeal == mealToUpdate.isLeftoverMeal,
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
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
      );

      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      if (!mounted) return;
      if (showSnackbar)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Recette modifiée', style: GoogleFonts.poppins(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
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
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Repas historique ajouté', style: GoogleFonts.poppins(color: Colors.white))),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
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
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
      );
      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
      setState(() {
        _generatedMealPlan = updatedPlan;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Repas ajouté', style: GoogleFonts.poppins(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 4,
        ),
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
  }) async {
    // Pre-load recipe count to compute a snug initial sheet height
    final snap = await FirebaseFirestore.instance.collection('recipes').get();
    if (!mounted) return;
    final recipeCount = snap.docs.length;

    // header ≈ 305 px (outer title + RecipeSelector header + filters), each item ≈ 82 px
    const double headerPx = 305;
    const double itemPx = 82;
    const double minFraction = 0.50;
    const double maxFraction = 0.95;
    final screenH = MediaQuery.of(context).size.height;
    final contentH = headerPx + recipeCount * itemPx + 24;
    final initial = (contentH / screenH).clamp(minFraction, maxFraction);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          DraggableScrollableSheet(
            initialChildSize: initial,
            minChildSize: 0.3,
            maxChildSize: maxFraction,
            builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choisir une recette',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black45),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: RecipeSelector(
                scrollController: scrollController,
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history, color: Colors.orange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Repas historique',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(foregroundColor: Colors.black54),
                      child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A5AE0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        elevation: 0,
                      ),
                      child: Text('Oui, modifier', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
              // Vérifie si c'est une première occurrence addExtraMeal avec un reste le lendemain
              if (mealToUpdate.recipe.addExtraMeal &&
                  !mealToUpdate.isLeftoverMeal &&
                  _generatedMealPlan != null) {
                final nextDay = mealToUpdate.date.add(const Duration(days: 1));
                final leftoverExists = _generatedMealPlan!.meals.any((m) =>
                    m.recipe.id == mealToUpdate.recipe.id &&
                    m.date.year == nextDay.year &&
                    m.date.month == nextDay.month &&
                    m.date.day == nextDay.day &&
                    m.isLeftoverMeal);
                if (leftoverExists) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A5AE0).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.info_outline, color: Color(0xFF6A5AE0), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Recette cuisinée pour 2 repas',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'Cette recette est prévue pour 2 repas (aujourd\'hui + lendemain). '
                        'Remplacer supprimera également le repas du lendemain.',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(foregroundColor: Colors.black54),
                          child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6A5AE0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            elevation: 0,
                          ),
                          child: Text('Remplacer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
              }
              _changeMealRecipe(mealToUpdate, newRecipe);
            } else if (date != null && type != null) {
              _addMealToPlan(newRecipe, date, type);
            }
          },
        ),
            ),
          ],
        ),
      ),
          ), // DraggableScrollableSheet
        ], // Stack children
      ), // Stack
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
                                Row(
                                  children: [
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 40,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300],
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Colors.black45),
                                      onPressed: () => Navigator.pop(builderContext),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _ModernPlannerHeader(
                                  selectedStartDate: _selectedStartDate,
                                  selectedDuration: _selectedDuration,
                                  selectedCategories: _selectedCategories,
                                  categoryDataById: _categoryDataById,
                                  pantryIngredients: _pantryIngredients,
                                  onPickStartDate: () {
                                    _pickStartDate(onDatePicked: () => setModalState(() {}));
                                  },
                                  onPickDuration: () {
                                    _pickDuration(
                                      onUpdated: () => setModalState(() {}),
                                    );
                                  },
                                  onPickCategories: () {
                                    _pickCategories(onUpdated: () => setModalState(() {}));
                                  },
                                  onPickPantry: () {
                                    _pickPantryItems(onUpdated: () => setModalState(() {}));
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
                    padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Planificateur de repas',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Tooltip(
                            message: 'Notifications du plan',
                            child: Material(
                              color: const Color(0xFF6A5AE0),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MealPlanNotificationsPage(
                                        mealPlan: _generatedMealPlan,
                                      ),
                                    ),
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.notifications_outlined,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
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
                            selectedCategories: _selectedCategories,
                            categoryDataById: _categoryDataById,
                            pantryIngredients: _pantryIngredients,
                            onPickStartDate: () {
                              _pickStartDate(onDatePicked: () => setState(() {}));
                            },
                            onPickDuration: () {
                              _pickDuration(onUpdated: () => setState(() {}));
                            },
                            onPickCategories: () {
                              _pickCategories(onUpdated: () => setState(() {}));
                            },
                            onPickPantry: () {
                              _pickPantryItems(onUpdated: () => setState(() {}));
                            },
                            onLaunchPlanning: _launchPlanning,
                            isLoading: _isLoading,
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                      if (_generatedMealPlan != null) ...[
                        const SizedBox(height: 16),
                        _buildPlanMetadata(),
                        const SizedBox(height: 12),
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

  Widget _buildPlanMetadata() {
    if (_generatedMealPlan == null) return const SizedBox();

    // Use _selectedCategories if populated, otherwise use what's in the plan directly
    final categoryIds = _selectedCategories.isNotEmpty 
        ? _selectedCategories
        : _generatedMealPlan!.selectedCategories;

    final categories = categoryIds.map((id) => _categoryDataById[id]).where((c) => c != null).toList();
    
    // Use _pantryIngredients if populated, or from plan
    final pantryItems = _pantryIngredients.isNotEmpty 
        ? _pantryIngredients 
        : _generatedMealPlan!.pantryItems;

    if (categories.isEmpty && pantryItems.isEmpty) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: ExpansionTile(
              title: Text(
                'Paramètres du plan',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              subtitle: Text(
                'Voir les catégories et ingrédients utilisés',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A5AE0).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF6A5AE0)),
              ),
              shape: const Border(), 
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              tilePadding: EdgeInsets.zero,
              children: [
          
              if (categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Catégories filtrées :',
                  style: GoogleFonts.poppins(
                    fontSize: 12, 
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600]
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    final name = cat!['name'] as String;
                    final colorVal = cat['color'] as int;
                    final baseColor = Color(colorVal);

                    // Use the new HSL contrast logic we standardized earlier
                    final hsl = HSLColor.fromColor(baseColor);
                    final startLightness = hsl.lightness;
                    final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                    final textColor = hsl.withLightness(textLightness).toColor();

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: baseColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (pantryItems.isNotEmpty) ...[
               Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ingrédients du frigo pris en compte :',
                  style: GoogleFonts.poppins(
                    fontSize: 12, 
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600]
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...pantryItems.take(5).map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.kitchen, size: 14, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit.label} ${item.ingredient.name}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (pantryItems.length > 5)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '+ ${pantryItems.length - 5} autres',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
        ],
      ),
    ));
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

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        
        DateTime? newDate;
        if (details.primaryVelocity! < 0) {
          // Swipe Left -> Next Day
          newDate = _selectedMealDate!.add(const Duration(days: 1));
        } else if (details.primaryVelocity! > 0) {
          // Swipe Right -> Previous Day
          newDate = _selectedMealDate!.subtract(const Duration(days: 1));
        }
        
        if (newDate != null) {
          // Verify bounds (start of day comparison)
          final newDateDay = DateTime(newDate.year, newDate.month, newDate.day);
          final firstDayStart = DateTime(firstDay.year, firstDay.month, firstDay.day);
          final lastDayStart = DateTime(lastDay.year, lastDay.month, lastDay.day);

          if (!newDateDay.isBefore(firstDayStart) && !newDateDay.isAfter(lastDayStart)) {
            setState(() {
              _selectedMealDate = newDate;
              _focusedDay = newDate!;
            });
          }
        }
      },
      child: Material(
      type: MaterialType.transparency,
      child: TableCalendar(
        startingDayOfWeek: StartingDayOfWeek.monday,
        locale: 'fr_FR',
        firstDay: firstDay,
        lastDay: lastDay,
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat!,
        availableGestures: AvailableGestures.none, // Disable internal gestures to use custom swipe
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
          // Force all text to be black/dark and bold for better visibility
          defaultTextStyle: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, fontSize: 15),
          weekendTextStyle: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, fontSize: 15),
          outsideTextStyle: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, fontSize: 15),
          selectedTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          todayTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          disabledTextStyle: TextStyle(color: Colors.grey), // Keep truly disabled days grey
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
      ), // Close Material
    ); // Close GestureDetector
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(_selectedMealDate!.year, _selectedMealDate!.month, _selectedMealDate!.day);
    final isPastDay = selectedDay.isBefore(today);
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
      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            // ── Main content (tap to open recipe) ──
            InkWell(
              onTap: () => _openRecipeDetail(meal),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon
                        meal.isLeftoverMeal
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restaurant, color: Colors.orange, size: 24),
                              )
                            : Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restaurant_menu, color: Colors.green, size: 24),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + multiplier badge
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      meal.recipe.title,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                  ),
                                  if (meal.recipeMultiplier > 1 && !meal.isLeftoverMeal)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green, width: 1.5),
                                      ),
                                      child: Text(
                                        'x${meal.recipeMultiplier}',
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green[800]),
                                      ),
                                    ),
                                  // Servings badge
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6A5AE0).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${meal.totalServings} pers',
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF6A5AE0), fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                meal.recipe.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 13),
                              ),
                              // Badges
                              if (meal.isLeftoverMeal) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                                    const SizedBox(width: 4),
                                    Text('Restes du repas précédent',
                                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.orange[700], fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ],
                              if (meal.recipe.addExtraMeal && !meal.isLeftoverMeal &&
                                  (_generatedMealPlan?.meals.any((m) {
                                    final nextDay = meal.date.add(const Duration(days: 1));
                                    return m.recipe.id == meal.recipe.id && m.date.year == nextDay.year && m.date.month == nextDay.month && m.date.day == nextDay.day && m.isLeftoverMeal;
                                  }) ?? false)) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Text('À cuisiner pour 2 repas',
                                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.green[700], fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingRecipeId == meal.recipe.id)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
            // ── Action bar ──
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    if (!isPastDay) ...[
                      Expanded(
                        child: InkWell(
                          onTap: () => _autoChangeMealRecipe(meal),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.autorenew, color: Colors.grey.shade500, size: 20),
                                const SizedBox(height: 3),
                                Text('Aléatoire', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: Colors.grey.shade200),
                    ],
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final mealDate = DateTime(meal.date.year, meal.date.month, meal.date.day);
                          final isHistory = mealDate.isBefore(today);
                          if (isHistory) {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.history, color: Colors.orange, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Repas historique',
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    style: TextButton.styleFrom(foregroundColor: Colors.black54),
                                    child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6A5AE0),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                      elevation: 0,
                                    ),
                                    child: Text('Oui, modifier', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                          } else {
                            _autoChangeBannedRecipes.clear();
                          }
                          _showRecipeSelector(mealToUpdate: meal, requireConfirmation: false);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                              const SizedBox(height: 3),
                              Text('Chercher', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: Colors.grey.shade200),
                    Expanded(
                      child: InkWell(
                        onTap: () => _deleteMeal(meal),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                              const SizedBox(height: 3),
                              Text('Supprimer', style: GoogleFonts.poppins(fontSize: 10, color: Colors.red.shade300, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    Widget buildEmptySlot(MealType mealType) {
      Future<void> onManualTap() async {
        if (_selectedMealDate == null) return;
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Repas historique',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: Text(
                "Ce jour fait partie de l'historique. Voulez-vous vraiment ajouter un repas ?",
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                  ),
                  child: Text('Oui, ajouter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
        _showRecipeSelector(date: _selectedMealDate!, type: mealType);
      }

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            // ── Main content ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.restaurant_menu, color: Colors.grey[400], size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucun repas planifié',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Action bar ──
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    if (!isPastDay) ...[
                      Expanded(
                        child: InkWell(
                          onTap: () => _autoFillEmptySlot(_selectedMealDate!, mealType),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.autorenew, color: Colors.grey.shade500, size: 20),
                                const SizedBox(height: 3),
                                Text('Aléatoire', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: Colors.grey.shade200),
                    ],
                    Expanded(
                      child: InkWell(
                        onTap: onManualTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                              const SizedBox(height: 3),
                              Text('Chercher', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        
        // Calculate bounds (same as in calendar) to prevent out of bounds error
        DateTime planStart = _generatedMealPlan?.startDate ?? DateTime.now();
        DateTime planEnd = planStart.add(
          Duration(days: (_generatedMealPlan?.durationDays ?? 1) - 1),
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

        DateTime? newDate;
        if (details.primaryVelocity! < 0) {
          // Swipe Left -> Next Day
          newDate = _selectedMealDate!.add(const Duration(days: 1));
        } else if (details.primaryVelocity! > 0) {
          // Swipe Right -> Previous Day
          newDate = _selectedMealDate!.subtract(const Duration(days: 1));
        }

        if (newDate != null) {
          // Verify bounds (start of day comparison)
          final newDateDay = DateTime(newDate.year, newDate.month, newDate.day);
          final firstDayStart = DateTime(firstDay.year, firstDay.month, firstDay.day);
          final lastDayStart = DateTime(lastDay.year, lastDay.month, lastDay.day);

          if (!newDateDay.isBefore(firstDayStart) && !newDateDay.isAfter(lastDayStart)) {
             setState(() {
               _selectedMealDate = newDate;
               _focusedDay = newDate!;
             });
          }
        }
      },
      child: Padding(
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
    ), // Close Padding
    ); // Close GestureDetector
  }
}

/* ================= COMPONENTS ================= */

class _ModernPlannerHeader extends StatelessWidget {
  final DateTime? selectedStartDate;
  final int? selectedDuration;
  final Set<String> selectedCategories;
  
  // ID -> {id, name, color}
  final Map<String, Map<String, dynamic>> categoryDataById;
  
  // Use explicit list instead of count
  final List<RecipeIngredient> pantryIngredients;

  final VoidCallback onPickStartDate;
  final VoidCallback onPickDuration;
  final VoidCallback onPickCategories;
  final VoidCallback onPickPantry;
  final VoidCallback onLaunchPlanning;
  final bool isLoading;

  const _ModernPlannerHeader({
    required this.selectedStartDate,
    required this.selectedDuration,
    required this.selectedCategories,
    required this.categoryDataById,
    required this.pantryIngredients, // Changed
    required this.onPickStartDate,
    required this.onPickDuration,
    required this.onPickCategories,
    required this.onPickPantry,
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
          const SizedBox(height: 12),
          InkWell(
            onTap: onPickCategories,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selectedCategories.isNotEmpty
                      ? const Color(0xFF6A5AE0).withOpacity(0.5)
                      : Colors.grey.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.category_rounded, color: Color(0xFF6A5AE0), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Catégories',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final validCategories = selectedCategories.where((id) {
                                final cat = categoryDataById[id];
                                return cat != null;
                            }).toList();

                            // If empty (no filter) or equal to total known categories (all selected)
                            if (validCategories.isEmpty || (categoryDataById.isNotEmpty && validCategories.length == categoryDataById.length)) {
                              return Text(
                                'Toutes',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2D2D2D),
                                ),
                              );
                            }

                            return Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: validCategories.map((id) {
                                final cat = categoryDataById[id];
                                final name = cat?['name'] as String? ?? 'Unknown';
                                final colorVal = cat?['color'] as int? ?? 0xFF6A5AE0;
                                final color = Color(colorVal);

                                // Contrast logic
                                final hsl = HSLColor.fromColor(color);
                                final textLightness =
                                    hsl.lightness > 0.4 ? 0.4 : hsl.lightness;
                                final textColor =
                                    hsl.withLightness(textLightness).toColor();

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    name,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onPickPantry,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: pantryIngredients.isNotEmpty
                      ? const Color(0xFF6A5AE0).withOpacity(0.5)
                      : Colors.grey.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.kitchen, color: Color(0xFF6A5AE0), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ingrédients disponibles',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        if (pantryIngredients.isEmpty)
                          Text(
                            'Aucun (Optionnel)',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2D2D2D),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: pantryIngredients.map((item) {
                              return Container(
                                padding: const EdgeInsets.symmetric( horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                                ),
                                child: Text(
                                  '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit.label} ${item.ingredient.name}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[800],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                ],
              ),
            ),
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
