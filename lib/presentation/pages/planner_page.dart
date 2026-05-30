import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/auth_notifier.dart';
import '../providers/auth_state.dart';

import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_meal_history_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/notification_settings_repository.dart';
import '../../data/services/notification_service.dart';

import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/usecases/meal_planning_service.dart';
import '../../domain/usecases/shopping_list_generator.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../data/repositories/firebase_pantry_repository.dart';
import '../../data/repositories/firebase_pantry_snapshot_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/entities/pantry_item.dart';
import '../../core/utils/qty_format.dart';

import 'recipe_detail_page.dart';
import 'meal_plan_notifications_page.dart';
import 'admin_page.dart';
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
  final FirebaseRecipeRepository _recipeRepo = FirebaseRecipeRepository();

  int _maxHistoryDays = 30; // Default value, recalculated based on recipe count

  /// Cache des recettes pour la durée de la session (évite les lectures répétées).
  /// Invalidé uniquement si l'utilisateur ajoute/modifie/supprime une recette.
  List<Recipe>? _cachedRecipes;

  DateTime? _selectedStartDate = DateTime.now();
  int? _selectedDuration = 7;
  Set<String> _selectedCategories = {}; // category IDs
  List<RecipeIngredient> _pantryIngredients = [];
  Set<String> _urgentPantryNames = {};
  List<PantrySnapshotItem> _pantrySnapshot = [];
  
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

  /// Noms des membres du foyer (uid -> nom affiché)
  Map<String, String> _userNames = {};

  /// Banned recipes per slot for the auto-change feature.
  /// Key: slot key (date_mealType), Value: set of banned recipe IDs.
  final Map<String, Set<String>> _autoChangeBannedRecipes = {};

  /// Slots explicitly declared exhausted (algo returned null while in near-end
  /// of cycle, or the ban list covers all recipes). Used to enforce exhaustion
  /// across different shuffle contexts without over-banning on contextual failures.
  final Set<String> _algoExhaustedSlots = {};

  /// Multi-shuffle mode: true when the user is selecting slots to keep.
  bool _isMultiShuffleMode = false;

  /// Slots selected to be KEPT during multi-shuffle.
  /// Key: slot key (date_mealType_recipeId), identifies a specific Meal.
  final Set<String> _multiShuffleKeptSlots = {};

  /// Slot keys (date_mealType) verrouillés lors du dernier multi-shuffle.
  /// Persistés dans SharedPreferences et restaurés au prochain passage en mode multi-shuffle.
  Set<String> _persistedLockedSlotKeys = {};

  static const _kPrefKeyCategories = 'selected_category_ids';
  static const _kPrefKeyDuration = 'planner_duration_days';
  static const _kPrefKeyLockedSlots = 'multi_shuffle_locked_slots';

  @override
  void initState() {
    super.initState();
    _loadAllCategories();
    _loadSavedPreferences();
    _loadMostRecentMealPlanAndHistory();
    _loadPantryFromRepository();
  }

  Future<void> _loadPantryFromRepository() async {
    try {
      final items = await FirebasePantryRepository.instance.getAll();
      if (!mounted) return;
      setState(() {
        _pantryIngredients =
            items.map((i) => i.toRecipeIngredient()).toList();
        _urgentPantryNames = items
            .where((i) => i.isUrgent)
            .map((i) => i.name)
            .toSet();
      });
    } catch (_) {
      // Silently fall back to plan-stored items if repository is unavailable.
    }
  }

  Future<void> _loadAllCategories({bool forceRefresh = false}) async {
    if (!forceRefresh && _categoryDataById.isNotEmpty) return;
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

    // Load persisted locked slots (multi-shuffle)
    final savedLocked = prefs.getStringList(_kPrefKeyLockedSlots);
    if (savedLocked != null) {
      _persistedLockedSlotKeys = savedLocked.toSet();
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

  Future<void> _saveLockedSlots(Set<String> slotKeys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKeyLockedSlots, slotKeys.toList());
  }

  /// Charge les noms des utilisateurs du groupe dans [_userNames].
  /// Indépendant des autres chargements pour être résilient aux exceptions.
  Future<void> _loadUserNames() async {
    // Garde : si les noms sont déjà chargés, pas besoin de relire Firestore.
    if (_userNames.isNotEmpty) return;
    try {
      final realUsers = await FirebaseUserRepository().getUsers();
      for (final u in realUsers) {
        if (u.name.isNotEmpty) _userNames[u.id] = u.name;
      }
    } catch (_) {}
    // Fallback depuis les servings (userName stocké dans recipeServings)
    try {
      final servingsForNames = await _userServingRepo.fetchAllGroupServings();
      for (final s in servingsForNames) {
        if (s.userName.isNotEmpty && s.userName != s.userId) {
          // Toujours mettre à jour : les servings peuvent avoir un nom plus récent
          _userNames[s.userId] = s.userName;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMostRecentMealPlanAndHistory() async {
    setState(() => _isLoading = true);
    // Charger les noms en premier, indépendamment du reste — jamais bloqué
    await _loadUserNames();
    try {
      // Load recipe count to calculate the history window size
      final allRecipes = await _loadRecipes(forceRefresh: true);
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
        // Note: pantry items are loaded from the dedicated pantry repository
        // (_loadPantryFromRepository), not from the plan snapshot, so that
        // the header always reflects the current fridge/pantry state.

        // Set today as selected if it is within the plan range
        final today = DateTime.now();
        final planStart = _generatedMealPlan!.startDate;
        final planEnd = planStart.add(
          Duration(days: _generatedMealPlan!.durationDays - 1),
        );
        if (!today.isBefore(planStart) && !today.isAfter(planEnd)) {
          // Aujourd'hui est dans la plage du plan
          _selectedMealDate = today;
          _focusedDay = today;
        } else if (today.isAfter(planEnd)) {
          // Plan terminé - se positionner sur le dernier jour
          _selectedMealDate = planEnd;
          _focusedDay = planEnd;
        } else {
          // Plan pas encore démarré - se positionner sur le premier jour
          _selectedMealDate = planStart;
          _focusedDay = planStart;
        }
        _calendarFormat = null; // Reset to recalculate format
        // Update history from loaded plan.
        // La méthode retourne l'historique final — pas besoin de rappeler getHistory().
        final updatedHistory = await _historyRepo.updateHistoryFromPlan(
          _generatedMealPlan,
          _maxHistoryDays,
        );
        _mealHistory = updatedHistory;
        // Planifie silencieusement les notifications (pour tous les utilisateurs)
        _autoScheduleNotifications(loadedPlan).ignore();

        // Charger le snapshot frigo/placard figé de ce plan
        try {
          final snapshot = await FirebasePantrySnapshotRepository.instance.get();
          if (mounted) setState(() => _pantrySnapshot = snapshot);
        } catch (_) {}
      } else {
        // Pas de plan — charger uniquement l'historique
        _mealHistory = await _historyRepo.getHistory();
      }
      // History-only mode: if no plan loaded, initialise selected date from history
      if (_generatedMealPlan == null && _mealHistory.isNotEmpty && _selectedMealDate == null) {
        final sortedDates = _mealHistory.keys.toList()..sort((a, b) => b.compareTo(a));
        _selectedMealDate = sortedDates.first;
        _focusedDay = sortedDates.first;
        _calendarFormat = CalendarFormat.month;
      }
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
    // Réutilise le cache _categoryDataById si disponible — sinon lit Firestore.
    if (_categoryDataById.isEmpty) {
      await _loadAllCategories();
    }
    if (!mounted) return;

    final allCategories = _categoryDataById.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    // dataById est _categoryDataById lui-même (déjà à jour)
    final dataById = _categoryDataById;

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

  void _showPantrySnapshotDialog() {
    if (_pantrySnapshot.isEmpty) return;

    // Grouper par catégorie, urgents d'abord
    final urgent = _pantrySnapshot.where((i) => i.isUrgent).toList();
    final normal = _pantrySnapshot.where((i) => !i.isUrgent).toList();

    Map<String, List<PantrySnapshotItem>> _group(List<PantrySnapshotItem> items) {
      final m = <String, List<PantrySnapshotItem>>{};
      for (final i in items) {
        final k = i.typeName.isNotEmpty ? i.typeName : 'Autre';
        m.putIfAbsent(k, () => []).add(i);
      }
      for (final k in m.keys) {
        m[k]!.sort((a, b) => a.name.compareTo(b.name));
      }
      return m;
    }

    List<String> _sortedKeys(Map<String, List<PantrySnapshotItem>> g) =>
        g.keys.toList()
          ..sort((a, b) {
            if (a == 'Autre') return 1;
            if (b == 'Autre') return -1;
            return a.compareTo(b);
          });

    final urgentGroups = _group(urgent);
    final normalGroups = _group(normal);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Frigo / Placard de ce plan',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_pantrySnapshot.length} article${_pantrySnapshot.length > 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6A5AE0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Snapshot figé au moment de la génération du plan',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                      if (urgent.isNotEmpty) ...[
                      _buildSnapshotSuperLabel('🔥 Urgents', Colors.orange.shade700),
                      for (final key in _sortedKeys(urgentGroups)) ...[
                        _buildSnapshotCategoryLabel(key),
                        ...urgentGroups[key]!.map(_buildSnapshotItemRow),
                      ],
                      const SizedBox(height: 8),
                    ],
                    if (normal.isNotEmpty) ...[
                      if (urgent.isNotEmpty)
                        _buildSnapshotSuperLabel('Normaux', const Color(0xFF6A5AE0)),
                      for (final key in _sortedKeys(normalGroups)) ...[
                        _buildSnapshotCategoryLabel(key),
                        ...normalGroups[key]!.map(_buildSnapshotItemRow),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Affiche le contenu ACTUEL du pantry (utilisé depuis la modale nouveau plan).
  void _showCurrentPantryDialog() {
    final items = _pantryIngredients;
    if (items.isEmpty) return;

    final urgentNames = _urgentPantryNames;

    final urgentList = items.where((i) => urgentNames.contains(i.ingredient.name)).toList()
      ..sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name));
    final normalList = items.where((i) => !urgentNames.contains(i.ingredient.name)).toList()
      ..sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name));

    Widget buildRow(RecipeIngredient item, bool isUrgent) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          if (isUrgent)
            const Text('🔥', style: TextStyle(fontSize: 13))
          else
            Icon(Icons.circle, size: 6, color: Colors.grey[300]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.ingredient.name,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '${fmtQty(item.quantity)} ${item.unit.label}',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Frigo / Placard',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${items.length} article${items.length > 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6A5AE0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'État actuel du frigo/placard',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (urgentList.isNotEmpty) ...[
                      _buildSnapshotSuperLabel('🔥 Urgents', Colors.orange.shade700),
                      ...urgentList.map((i) => buildRow(i, true)),
                      const SizedBox(height: 8),
                    ],
                    if (normalList.isNotEmpty) ...[
                      if (urgentList.isNotEmpty)
                        _buildSnapshotSuperLabel('Normaux', const Color(0xFF6A5AE0)),
                      ...normalList.map((i) => buildRow(i, false)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnapshotSuperLabel(String label, Color color) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    ),
  );

  Widget _buildSnapshotCategoryLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
    child: Row(
      children: [
        Container(width: 3, height: 13, decoration: BoxDecoration(color: const Color(0xFF6A5AE0), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6A5AE0))),
      ],
    ),
  );

  Widget _buildSnapshotItemRow(PantrySnapshotItem item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Row(
      children: [
        if (item.isUrgent)
          const Text('🔥', style: TextStyle(fontSize: 13))
        else
          Icon(Icons.circle, size: 6, color: Colors.grey[300]),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.name,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          '${fmtQty(item.quantity)} ${item.unit.label}',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    ),
  );

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
      // Sync changes back to the pantry repository.
      _syncPantryToRepository(result).ignore();
      if (onUpdated != null) {
        onUpdated();
      }
    }
  }

  /// Replaces all pantry items in the repository with the provided list.
  Future<void> _syncPantryToRepository(List<RecipeIngredient> items) async {
    try {
      final repo = FirebasePantryRepository.instance;
      await repo.deleteAll();
      for (final ri in items) {
        await repo.save(PantryItem(
          id: '',
          name: ri.ingredient.name,
          ingredientId: ri.ingredient.id,
          quantity: ri.quantity,
          unit: ri.unit,
          isUrgent: false,
          updatedAt: DateTime.now(),
        ));
      }
    } catch (_) {
      // Sync is best-effort; do not disrupt the planning flow.
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

  Future<void> _deletePlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Supprimer le plan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Le plan de repas actuel sera supprimé définitivement. L\'historique ne sera pas affecté.',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _mealPlanRepo.deleteMealPlan(_generatedMealPlan!.id);
      await FirebasePantrySnapshotRepository.instance.delete();
      final historyDates = _mealHistory.keys.toList()..sort((a, b) => b.compareTo(a));
      setState(() {
        _generatedMealPlan = null;
        _pantrySnapshot = [];
        _calendarFormat = null;
        _selectedMealDate = historyDates.isNotEmpty ? historyDates.first : null;
        _focusedDay = historyDates.isNotEmpty ? historyDates.first : DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_toggle_off_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Supprimer l\'historique',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Tout l\'historique des repas passés sera supprimé définitivement.',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _historyRepo.clearAllHistory();
      setState(() {
        _mealHistory = {};
        if (_generatedMealPlan == null) {
          _selectedMealDate = null;
          _focusedDay = DateTime.now();
        } else {
          // Keep focusedDay within the plan range
          final planStart = _generatedMealPlan!.startDate;
          if (_focusedDay.isBefore(planStart)) {
            _focusedDay = planStart;
            _selectedMealDate = planStart;
          }
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    _algoExhaustedSlots.clear();
    try {
      final allRecipes = await _loadRecipes(forceRefresh: true);
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
      // Synchroniser _userNames depuis les servings via la méthode centralisée
      await _loadUserNames();
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
        urgentPantryIngredientNames: _urgentPantryNames,
        selectedCategories: _selectedCategories.toList(),
        leftoverUserOrder: _generatedMealPlan?.leftoverUserOrder ?? [],
      );

      setState(() {
        _generatedMealPlan = plan;
        _selectedMealDate = plan.startDate;
        _focusedDay = plan.startDate;
        _calendarFormat = null; // Reset to recalculate format
      });

      // Automatic plan saving
      final savedId = await _saveMealPlan(plan);

      // Figer le snapshot frigo/placard pour ce plan
      final currentPantryItems = await FirebasePantryRepository.instance.getAll();
      await FirebasePantrySnapshotRepository.instance.save(currentPantryItems);
      if (mounted) {
        setState(() {
          _pantrySnapshot = currentPantryItems
              .map(PantrySnapshotItem.fromPantryItem)
              .toList();
        });
      }

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
          leftoverUserOrder: plan.leftoverUserOrder,
        );
      });

      // Planifie silencieusement les notifications pour ce nouveau plan
      _autoScheduleNotifications(_generatedMealPlan!).ignore();

    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Recipe>> _loadRecipes({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedRecipes != null) return _cachedRecipes!;
    _cachedRecipes = await FirebaseRecipeRepository().fetchAllRecipes();
    return _cachedRecipes!;
  }

  /// Invalide le cache recettes (à appeler après ajout/modification/suppression).
  void _invalidateRecipeCache() => _cachedRecipes = null;

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
    } catch (e, st) {
      // Ne doit pas bloquer l'UI — loggé en debug pour diagnostic
      debugPrint('[Notifications] Erreur : $e\n$st');
    }
  }

  String _slotKey(DateTime date, MealType type) =>
      '${date.year}-${date.month}-${date.day}_${type.name}';

  /// Clé unique pour identifier un Meal spécifique dans le multi-shuffle.
  String _mealKey(Meal meal) =>
      '${meal.date.year}-${meal.date.month}-${meal.date.day}_${meal.type.name}_${meal.recipe.id}_${meal.isLeftoverMeal}';

  /// Lance le multi-shuffle : pour chaque slot non gardé, applique un shuffle
  /// avec accumulation de bans (même logique que le shuffle unitaire).
  Future<void> _launchMultiShuffle() async {
    if (_generatedMealPlan == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Slots libres = futurs non-leftover non verrouillés par l'utilisateur.
    final freeSlotKeys = <String>{};
    for (final m in _generatedMealPlan!.meals) {
      if (m.isLeftoverMeal) continue;
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (mealDay.isBefore(today)) continue;
      final sk = _slotKey(m.date, m.type);
      if (!_multiShuffleKeptSlots.contains(sk)) freeSlotKeys.add(sk);
    }

    // Persister les slots verrouillés futurs (tout sauf les slots libres).
    final futureLockedKeys = _generatedMealPlan!.meals
        .where((m) =>
            !m.isLeftoverMeal &&
            !DateTime(m.date.year, m.date.month, m.date.day).isBefore(today))
        .map((m) => _slotKey(m.date, m.type))
        .where((sk) => !freeSlotKeys.contains(sk))
        .toSet();
    _persistedLockedSlotKeys = futureLockedKeys;
    _saveLockedSlots(futureLockedKeys);

    setState(() {
      _isMultiShuffleMode = false;
      _multiShuffleKeptSlots.clear();
    });

    await _shuffleFreeSlots(freeSlotKeys, isMultiShuffle: true);
  }

  /// Code commun au shuffle unitaire et au shuffle multiple.
  /// [freeSlotKeys] : slot keys (format date_type) des slots à re-générer.
  /// Tous les autres slots futurs non-leftover sont traités comme verrouillés.
  ///
  /// PASSE 1 : pour chaque slot libre (en ordre), l'algo tourne avec le ban
  ///   propre à CE slot uniquement → chaque slot a son propre cycle indépendant.
  ///   Les slots déjà traités sont passés comme contexte pour le suivant.
  /// PASSE 2 : plan final avec tous les repas (verrouillés + nouvelles recettes)
  ///   comme userSelectedMeals → calcule correctement les cascades de restes.
  Future<void> _shuffleFreeSlots(
    Set<String> freeSlotKeys, {
    bool suppressDialogs = false,
    bool isMultiShuffle = false,
  }) async {
    if (_generatedMealPlan == null || freeSlotKeys.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    debugPrint('[SHUFFLE] ===== _shuffleFreeSlots START =====');
    debugPrint('[SHUFFLE] freeSlotKeys (${freeSlotKeys.length}): $freeSlotKeys');

    // Bannir la recette courante de chaque slot libre dans son ban par slot.
    for (final m in _generatedMealPlan!.meals) {
      if (m.isLeftoverMeal) continue;
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (mealDay.isBefore(today)) continue;
      final sk = _slotKey(m.date, m.type);
      if (!freeSlotKeys.contains(sk)) continue;
      _autoChangeBannedRecipes.putIfAbsent(sk, () => {}).add(m.recipe.id);
    }

    // Log ban state AFTER banning current recipes.
    for (final sk in freeSlotKeys) {
      final banned = _autoChangeBannedRecipes[sk] ?? {};
      debugPrint('[SHUFFLE] BAN state for $sk : ${banned.length} banned = $banned');
    }

    // Repas verrouillés = passés + tous les slots futurs non libres.
    final lockedMeals = _generatedMealPlan!.meals.where((m) {
      if (m.isLeftoverMeal) return false;
      final mealDay = DateTime(m.date.year, m.date.month, m.date.day);
      if (mealDay.isBefore(today)) return true;
      return !freeSlotKeys.contains(_slotKey(m.date, m.type));
    }).toList();

    setState(() => _isLoading = true);
    try {
      final recipesRaw = await _loadRecipes();
      final allServings = await _loadServings();
      await _loadUserNames();
      final users = allServings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Résolution des noms d'ingrédients pour la similarité.
      final allIngredientIds = recipesRaw
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final recipesWithNames = recipesRaw.map((recipe) {
        final resolved = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolved);
      }).toList();

      // Filtre catégorie.
      final validSelectedCategories =
          _selectedCategories.where((id) => _categoryDataById.containsKey(id)).toSet();
      final allCategoryRecipes = validSelectedCategories.isEmpty
          ? recipesWithNames
          : recipesWithNames
              .where((r) => r.categoryIds.any((c) => validSelectedCategories.contains(c)))
              .toList();

      debugPrint('[SHUFFLE] allCategoryRecipes count: ${allCategoryRecipes.length}');

      // Vérification d'épuisement PER-SLOT.
      final exhaustedSlotLabels = <String>[];
      for (int di = 0; di < _generatedMealPlan!.durationDays; di++) {
        final day = _generatedMealPlan!.startDate.add(Duration(days: di));
        if (DateTime(day.year, day.month, day.day).isBefore(today)) continue;
        for (final type in [MealType.lunch, MealType.dinner]) {
          final sk = _slotKey(day, type);
          if (!freeSlotKeys.contains(sk)) continue;
          final slotBanned = _autoChangeBannedRecipes[sk] ?? {};
          final slotIsExhausted = _algoExhaustedSlots.contains(sk) ||
              (allCategoryRecipes.isNotEmpty &&
                  allCategoryRecipes.every((r) => slotBanned.contains(r.id)));
          if (slotIsExhausted) {
            final dayLabel =
                '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
            final typeLabel = type == MealType.lunch ? 'déjeuner' : 'dîner';
            exhaustedSlotLabels.add('$typeLabel du $dayLabel');
          }
        }
      }
      debugPrint('[SHUFFLE] exhaustedSlots (${exhaustedSlotLabels.length}/${freeSlotKeys.length}): $exhaustedSlotLabels');

      // Si TOUS les slots libres sont épuisés, retourner tôt (rien à faire).
      // Si seulement CERTAINS sont épuisés, passe 1 les traitera via failedSlotMeals.
      if (exhaustedSlotLabels.length == freeSlotKeys.length) {
        debugPrint('[SHUFFLE] All slots exhausted → reset bans and early return');
        // Réinitialiser les bans pour ces slots : le cycle repart depuis le début.
        // On reban uniquement la recette actuelle de chaque slot (pour ne pas
        // reproposer immédiatement ce qui est déjà affiché).
        for (final sk in freeSlotKeys) {
          final currentMeal = _generatedMealPlan!.meals
              .where((m) => !m.isLeftoverMeal && _slotKey(m.date, m.type) == sk)
              .firstOrNull;
          _autoChangeBannedRecipes[sk] = currentMeal != null ? {currentMeal.recipe.id} : {};
        }
        _algoExhaustedSlots.removeAll(freeSlotKeys);
        if (!suppressDialogs && mounted) {
          final slotsLabel = exhaustedSlotLabels.length == 1
              ? exhaustedSlotLabels.first
              : exhaustedSlotLabels.join(', ');
          final message = exhaustedSlotLabels.length == 1
              ? 'Toutes les recettes ont été proposées pour $slotsLabel. Les propositions reprennent depuis le début.'
              : 'Toutes les recettes ont été proposées pour : $slotsLabel. Les propositions reprennent depuis le début.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.refresh_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFF6A5AE0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
        return; // Plan inchangé, cycle réinitialisé.
      }

      // Historique pour le contexte de diversité.
      final cutoffDate = now.subtract(Duration(days: _maxHistoryDays));
      final currentUserIds = allServings.map((s) => s.userId).toSet();
      final filteredHistoryMeals = _mealHistory.entries
          .where((entry) => !entry.key.isBefore(cutoffDate))
          .expand((entry) => entry.value)
          .where((meal) =>
              meal.userServings.isEmpty ||
              meal.userServings.keys.any((uid) => currentUserIds.contains(uid)))
          .toList();

      // ── PASSE 1 : sélection per-slot ──────────────────────────────────────
      // Chaque slot utilise UNIQUEMENT son propre ban → les bans des autres
      // slots ne pollent pas son pool. Les slots déjà traités dans cette passe
      // sont passés comme contexte cumulatif (userSelectedMeals) pour le suivant.

      // Slots actuellement VIDES dans le plan (futurs, non libres) : ils ne
      // doivent pas être remplis par l'algo en passe 2, sauf s'ils deviennent
      // un reste légitime de l'une des nouvelles recettes sélectionnées.
      final currentlyEmptyFutureSlotKeys = <String>{};
      for (int di = 0; di < _generatedMealPlan!.durationDays; di++) {
        final day = _generatedMealPlan!.startDate.add(Duration(days: di));
        if (DateTime(day.year, day.month, day.day).isBefore(today)) continue;
        for (final type in [MealType.lunch, MealType.dinner]) {
          final sk = _slotKey(day, type);
          if (freeSlotKeys.contains(sk)) continue;
          final hasMeal = _generatedMealPlan!.meals.any(
              (m) => _slotKey(m.date, m.type) == sk);
          if (!hasMeal) currentlyEmptyFutureSlotKeys.add(sk);
        }
      }

      final freeMeals = _generatedMealPlan!.meals
          .where((m) => !m.isLeftoverMeal && freeSlotKeys.contains(_slotKey(m.date, m.type)))
          .toList()
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          if (d != 0) return d;
          return a.type.index.compareTo(b.type.index);
        });

      final selectedNewMeals = <Meal>[];
      final unfilledLabels = <String>[]; // épuisement des bans
      final contextualFailedLabels = <String>[]; // algo null (contrainte contextuelle)
      final wasteConstrainedLabels = <String>[]; // algo null (no-waste strict en multi-shuffle)
      // Repas actuels des slots libres qui n'ont pas pu être changés (épuisés ou
      // algo sans résultat) → traités comme verrouillés en passe 2 pour ne pas
      // être remplacés par un repas aléatoire.
      final failedSlotMeals = <Meal>[];
      // Slots qui étaient des restes dans l'ancien plan mais dont la nouvelle recette
      // ne produit pas de restes → à laisser vides dans le plan final.
      final slotsToLeaveEmpty = <String>{};

      for (final mealToChange in freeMeals) {
        final sk = _slotKey(mealToChange.date, mealToChange.type);
        final slotBanned = _autoChangeBannedRecipes[sk] ?? {};

        // Slots de restes directement causés par l'ancienne recette de CE slot.
        // On scanne TOUS les slots futurs triés (la chaîne peut sauter un slot,
        // ex : dîner occupé par une autre recette mais déjeuner +1j est quand
        // même un reste de la recette shufflée).
        // On s'arrête dès qu'on croise une NOUVELLE occurrence non-reste de la
        // même recette (début d'une autre chaîne indépendante).
        final oldLeftoverSlotKeys = <String>{};
        {
          final shuffledSlotKey = sk;
          final targetRecipeId = mealToChange.recipe.id;
          // Trier les repas futurs par date+type (lunch avant dinner).
          final futureMeals = _generatedMealPlan!.meals.where((m) {
            final msk = _slotKey(m.date, m.type);
            if (msk == shuffledSlotKey) return false;
            // Les restes d'un slot lunch vont toujours au lunch suivant (slot+2),
            // idem pour dinner. On ne considère donc que le même type de repas
            // pour éviter de confondre deux chaînes independantes du même plat
            // (ex : poulet au dîner J-1 produit un reste au dîner J, tandis que
            // poulet au déjeuner J produit un reste au déjeuner J+1).
            if (m.type != mealToChange.type) return false;
            final mDay = DateTime(m.date.year, m.date.month, m.date.day);
            final sDay = DateTime(mealToChange.date.year, mealToChange.date.month, mealToChange.date.day);
            if (mDay.isBefore(sDay)) return false;
            if (mDay.isAtSameMomentAs(sDay)) return false; // même jour → pas futur
            return true;
          }).toList()
            ..sort((a, b) {
              final da = DateTime(a.date.year, a.date.month, a.date.day);
              final db = DateTime(b.date.year, b.date.month, b.date.day);
              final cmp = da.compareTo(db);
              if (cmp != 0) return cmp;
              // lunch (0) avant dinner (1)
              return a.type.index.compareTo(b.type.index);
            });
          for (final m in futureMeals) {
            if (m.recipe.id != targetRecipeId) continue;
            if (!m.isLeftoverMeal) break; // nouvelle occurrence indépendante
            oldLeftoverSlotKeys.add(_slotKey(m.date, m.type));
          }
        }

        // Contexte : repas verrouillés + slots libres déjà déterminés.
        final allLockedForSlot = [
          ...lockedMeals.map((m) => m.copyWith(userSelected: true)),
          ...selectedNewMeals.map((m) => m.copyWith(userSelected: true)),
        ];

        // Recettes déjà utilisées le même jour (autre slot verrouillé ou déjà
        // sélectionné dans cette passe) → exclure pour éviter les doublons jour.
        final sameDayRecipeIds = allLockedForSlot
            .where((m) =>
                m.date.year == mealToChange.date.year &&
                m.date.month == mealToChange.date.month &&
                m.date.day == mealToChange.date.day)
            .map((m) => m.recipe.id)
            .toSet();

        // Pool = catégorie filtrée moins le ban de CE slot et les doublons jour.
        final slotAvailable = allCategoryRecipes
            .where((r) => !slotBanned.contains(r.id) && !sameDayRecipeIds.contains(r.id))
            .toList();
        debugPrint('[SHUFFLE] Passe1 slot $sk : banned=${slotBanned.length}, available=${slotAvailable.length}');
        if (slotAvailable.isEmpty || _algoExhaustedSlots.contains(sk)) {
          if (slotAvailable.isEmpty) _algoExhaustedSlots.add(sk);
          final dayLabel = '${mealToChange.date.day.toString().padLeft(2, '0')}/${mealToChange.date.month.toString().padLeft(2, '0')}';
          final typeLabel = mealToChange.type == MealType.lunch ? 'déjeuner' : 'dîner';
          debugPrint('[SHUFFLE] Passe1 slot $sk → EXHAUSTED (added to failedSlotMeals, recipe=${mealToChange.recipe.id})');
          unfilledLabels.add('$typeLabel du $dayLabel');
          failedSlotMeals.add(mealToChange);
          continue;
        }

        // Paramètres communs pour les appels à l'algo.
        MealPlan runPlan(List<Recipe> recipes, {List<Meal>? overrideLocked, bool strict = true}) {
          final locked = overrideLocked ?? allLockedForSlot;
          return MealPlanningService.generateMealPlan(
            recipes: recipes,
            servings: allServings,
            users: users,
            startDate: _generatedMealPlan!.startDate,
            durationDays: _generatedMealPlan!.durationDays,
            recentMeals: filteredHistoryMeals,
            userSelectedMeals: locked.isEmpty ? null : locked,
            pantryItems: _pantryIngredients,
            urgentPantryIngredientNames: _urgentPantryNames,
            selectedCategories: _selectedCategories.toList(),
            leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
            similarityPenaltyWeight: 60.0,
            wastePenaltyWeight: 25.0,
            strictNoWaste: strict,
          );
        }
        Meal? pickFromPlan(MealPlan plan) => plan.meals.where(
          (m) => !m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
        ).firstOrNull;

        Meal? newMeal;

        // Si l'ancienne recette avait des restes, on privilégie les recettes
        // qui en produiront aussi (même schéma J+1).
        if (oldLeftoverSlotKeys.isNotEmpty) {
          final leftoverFavored = slotAvailable
              .where((r) => r.servings > mealToChange.totalServings)
              .toList();
          if (leftoverFavored.isNotEmpty) {
            final candidate = pickFromPlan(runPlan(leftoverFavored));
            if (candidate != null &&
                candidate.recipe.servings * candidate.recipeMultiplier > candidate.totalServings) {
              newMeal = candidate;
            }
          }
        }

        // Fallback : toutes les recettes disponibles pour ce slot.
        final fallbackPlan = runPlan(slotAvailable);
        newMeal ??= pickFromPlan(fallbackPlan);

        // Si null : vérifier si ce slot est couvert par un reste d'une recette
        // déjà sélectionnée dans ce batch (ex : 30-mai-midi produit des restes
        // qui tombent sur 31-mai-midi, lui aussi libre dans ce même shuffle).
        // Dans ce cas, ne pas chercher une nouvelle recette indépendante —
        // le reste sera injecté naturellement en passe 2.
        if (newMeal == null && selectedNewMeals.isNotEmpty) {
          final batchRecipeIds = selectedNewMeals.map((m) => m.recipe.id).toSet();
          final coveredByBatchLeftover = fallbackPlan.meals.any((m) =>
            m.isLeftoverMeal &&
            _slotKey(m.date, m.type) == sk &&
            batchRecipeIds.contains(m.recipe.id),
          );
          if (coveredByBatchLeftover) {
            debugPrint('[SHUFFLE] Passe1 slot $sk → covered by batch leftover, skip');
            // L'ancienne recette avait peut-être ses propres restes : les marquer
            // à vider car ce slot sera désormais occupé par un reste du batch.
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
            continue;
          }
        }

        // Si null : un reste cascade exactement sur sk → pickFromPlan filtre
        // isLeftoverMeal → null. On retire itérativement chaque recette source
        // du pool jusqu'à obtenir un plan sans cascade sur sk, ou épuiser le pool.
        bool cascadeUnresolvable = false;
        if (newMeal == null) {
          final poolExcluded = <String>{};
          bool coveredByLeftover = false;
          int safetyLimit = 15; // max itérations pour éviter boucle infinie
          while (newMeal == null && safetyLimit-- > 0) {
            final currentPool = slotAvailable
                .where((r) => !poolExcluded.contains(r.id))
                .toList();
            if (currentPool.isEmpty) break;
            final locked = allLockedForSlot
                .where((m) => !poolExcluded.contains(m.recipe.id))
                .toList();
            final trialPlan = runPlan(currentPool, overrideLocked: locked);
            final cascading = trialPlan.meals.where(
              (m) => m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
            ).firstOrNull;
            if (cascading == null) {
              // Plus de cascade : tenter de récupérer la recette pour sk.
              newMeal = pickFromPlan(trialPlan);
              // Si null, le slot est peut-être couvert par un reste d'une recette
              // extérieure (hors pool exclu). Dans ce cas, skip comme batch leftover.
              if (newMeal == null) {
                final coveredByAnyLeftover = trialPlan.meals.any((m) =>
                  m.isLeftoverMeal && _slotKey(m.date, m.type) == sk,
                );
                if (coveredByAnyLeftover) {
                  coveredByLeftover = true;
                  debugPrint('[SHUFFLE] Passe1 slot $sk → cascade cleared but covered by external leftover, skip');
                }
              }
              debugPrint('[SHUFFLE] Passe1 slot $sk → cascade cleared, pool=${currentPool.length}, newMeal=${newMeal?.recipe.id}');
              break;
            }
            poolExcluded.add(cascading.recipe.id);
            debugPrint('[SHUFFLE] Passe1 slot $sk → leftover-source ${cascading.recipe.id} excluded, poolLeft=${currentPool.length - 1}');
          }
          if (coveredByLeftover) {
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
            continue; // slot sera rempli par le reste en passe 2
          }
          cascadeUnresolvable = newMeal == null && poolExcluded.isNotEmpty;
          if (cascadeUnresolvable) {
            debugPrint('[SHUFFLE] Passe1 slot $sk → cascade unresolvable after ${poolExcluded.length} exclusions');
          }
        }

        if (newMeal != null) {
          debugPrint('[SHUFFLE] Passe1 slot $sk → SUCCESS new recipe=${newMeal.recipe.id} (${newMeal.recipe.title})');
          selectedNewMeals.add(newMeal);
          // L'ancienne recette avait des restes : libérer ces slots.
          // La nouvelle recette peut elle aussi produire des restes, mais
          // on ne les injecte pas automatiquement — l'utilisateur a shufflé
          // uniquement la première occurrence, pas les slots suivants.
          if (oldLeftoverSlotKeys.isNotEmpty) {
            slotsToLeaveEmpty.addAll(oldLeftoverSlotKeys);
          }
        } else {
          // L'algo a retourné null malgré un pool non vide.
          // Vérifier EN PREMIER si le blocage vient de la contrainte no-waste
          // (recettes restantes produisent trop de restes pour les slots libres)
          // avant de conclure à l'épuisement ou à un blocage contextuel.
          final dayLabel =
              '${mealToChange.date.day.toString().padLeft(2, '0')}/${mealToChange.date.month.toString().padLeft(2, '0')}';
          final typeLabel = mealToChange.type == MealType.lunch ? 'déjeuner' : 'dîner';
          final isWasteConstrained = cascadeUnresolvable ||
              pickFromPlan(runPlan(slotAvailable, strict: false)) != null;
          if (isWasteConstrained) {
            debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO null (waste-constrained, aucune recette sans restes dispo). recipe=${mealToChange.recipe.id}');
            wasteConstrainedLabels.add('$typeLabel du $dayLabel');
          } else {
            // Blocage contextuel (diversité, pantry, etc.).
            // Si presque toutes les recettes ont été essayées, marquer comme épuisé.
            final exhaustionThreshold = (allCategoryRecipes.length * 0.25).ceil();
            if (slotAvailable.length <= exhaustionThreshold) {
              _algoExhaustedSlots.add(sk);
              debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO null (near-exhaustion ${slotAvailable.length}/${allCategoryRecipes.length}, not waste-constrained). recipe=${mealToChange.recipe.id}');
              unfilledLabels.add('$typeLabel du $dayLabel');
            } else {
              debugPrint('[SHUFFLE] Passe1 slot $sk → ALGO returned null (contextual, ${slotAvailable.length} available preserved). recipe=${mealToChange.recipe.id}');
              contextualFailedLabels.add('$typeLabel du $dayLabel');
            }
          }
          failedSlotMeals.add(mealToChange);
        }
      }

      debugPrint('[SHUFFLE] Passe1 END: selectedNewMeals=${selectedNewMeals.map((m) => '${_slotKey(m.date, m.type)}=${m.recipe.id}').toList()}');
      debugPrint('[SHUFFLE] Passe1 END: failedSlotMeals=${failedSlotMeals.map((m) => '${_slotKey(m.date, m.type)}=${m.recipe.id}').toList()}');

      // Signaler les slots non remplis.
      if (unfilledLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = unfilledLabels.length == 1 && freeSlotKeys.length == 1
              ? 'Toutes les recettes ont été proposées pour ce créneau.'
              : 'Toutes les recettes ont été proposées pour : ${unfilledLabels.join(', ')}.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFF6A5AE0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
      }
      if (contextualFailedLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = contextualFailedLabels.length == 1 && freeSlotKeys.length == 1
              ? 'Impossible de trouver une recette adaptée pour ce créneau. Réessayez ou déverrouillez des repas voisins.'
              : 'Impossible de trouver une recette pour : ${contextualFailedLabels.join(', ')}. Réessayez ou déverrouillez des repas voisins.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFFE06A5A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ));
        }
      }
      if (wasteConstrainedLabels.isNotEmpty) {
        if (!suppressDialogs && mounted) {
          final message = wasteConstrainedLabels.length == 1
              ? 'Aucune recette sans restes gaspillés n\'est disponible pour le ${wasteConstrainedLabels.first}. Déverrouillez des repas voisins pour que les restes puissent être absorbés.'
              : 'Aucune recette sans restes gaspillés pour : ${wasteConstrainedLabels.join(', ')}. Déverrouillez des repas voisins pour que les restes puissent être absorbés.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.no_food_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
            ]),
            backgroundColor: const Color(0xFFFF9800),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 8),
          ));
        }
      }
      {
        // Si aucun slot n'a pu être mis à jour, tout le plan reste inchangé.
        if (selectedNewMeals.isEmpty) return;
      }

      // ── PASSE 2 : plan final ──────────────────────────────────────────────
      // Tous les repas (verrouillés + nouvelles recettes + slots échoués) sont
      // passés comme userSelectedMeals. L'algo calcule les cascades de restes
      // sur le plan complet de façon cohérente.
      // Les slots échoués (épuisés) sont verrouillés sur leur recette actuelle.
      // On verrouille aussi TOUS les repas de l'ancien plan qui ne sont ni
      // shufflés ni à vider : empêche l'algo de remplir des slots "spectateurs"
      // avec de nouvelles recettes (ex : 6-3_lunch leftover d'une autre source).
      final alreadyCoveredSlots = {
        ...lockedMeals.map((m) => _slotKey(m.date, m.type)),
        ...failedSlotMeals.map((m) => _slotKey(m.date, m.type)),
        ...selectedNewMeals.map((m) => _slotKey(m.date, m.type)),
      };
      final preservedOriginalMeals = _generatedMealPlan!.meals.where((m) {
        final sk = _slotKey(m.date, m.type);
        if (freeSlotKeys.contains(sk)) return false;        // slot shufflé
        if (slotsToLeaveEmpty.contains(sk)) return false;   // slot à vider
        if (alreadyCoveredSlots.contains(sk)) return false; // déjà verrouillé
        if (DateTime(m.date.year, m.date.month, m.date.day)
            .isBefore(today)) return false;
        return true;
      }).map((m) => m.copyWith(userSelected: true)).toList();

      final allUserSelectedFinal = [
        ...lockedMeals.map((m) => m.copyWith(userSelected: true)),
        ...failedSlotMeals.map((m) => m.copyWith(userSelected: true)),
        ...selectedNewMeals.map((m) => m.copyWith(userSelected: true)),
        ...preservedOriginalMeals,
      ];
      debugPrint('[SHUFFLE] Passe2 allUserSelectedFinal (${allUserSelectedFinal.length}):');
      for (final m in allUserSelectedFinal) {
        debugPrint('[SHUFFLE]   ${_slotKey(m.date, m.type)} recipe=${m.recipe.id} (${m.recipe.title}) leftover=${m.isLeftoverMeal} userSelected=${m.userSelected}');
      }

      final finalPlan = MealPlanningService.generateMealPlan(
        recipes: allCategoryRecipes, // pool complet (tous les slots sont verrouillés)
        servings: allServings,
        users: users,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        recentMeals: filteredHistoryMeals,
        userSelectedMeals: allUserSelectedFinal.isEmpty ? null : allUserSelectedFinal,
        pantryItems: _pantryIngredients,
        urgentPantryIngredientNames: _urgentPantryNames,
        selectedCategories: _selectedCategories.toList(),
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
        similarityPenaltyWeight: 60.0,
        wastePenaltyWeight: 25.0,
      );

      // Supprimer les repas non-leftover dans les slots marqués vides
      // (anciens slots de restes dont la nouvelle recette ne produit pas de restes).
      // Aussi supprimer tout repas placé par l'algo dans un slot qui était vide
      // avant ce shuffle, sauf s'il s'agit d'un reste dérivé d'une des nouvelles recettes.
      final selectedNewRecipeIds = selectedNewMeals.map((m) => m.recipe.id).toSet();
      MealPlan planToSave = finalPlan.copyWith(id: _generatedMealPlan!.id);
      {
        final prunedMeals = planToSave.meals.where((m) {
          final sk = _slotKey(m.date, m.type);
          // Anciens slots de restes libérés par le shuffle.
          // On garde uniquement les restes de la nouvelle recette sélectionnée
          // (si elle produit elle-même des restes qui tombent sur ces slots).
          // Tout autre repas (y compris les restes de l'ancienne recette) est supprimé.
          if (slotsToLeaveEmpty.contains(sk)) {
            return m.isLeftoverMeal && selectedNewRecipeIds.contains(m.recipe.id);
          }
          // Slots qui étaient vides avant ce shuffle : ne garder que les restes
          // légitimes des nouvelles recettes sélectionnées.
          if (currentlyEmptyFutureSlotKeys.contains(sk)) {
            return m.isLeftoverMeal && selectedNewRecipeIds.contains(m.recipe.id);
          }
          return true;
        }).toList();

        // Snackbar pour les slots réellement laissés vides (non couverts par la
        // nouvelle recette).
        final trulyVacatedSlots = slotsToLeaveEmpty
            .where((sk) => !prunedMeals.any((m) => _slotKey(m.date, m.type) == sk))
            .toSet();
        if (trulyVacatedSlots.isNotEmpty) {
          final vacatedLabels = <String>[];
          for (int di = 0; di < planToSave.durationDays; di++) {
            final day = planToSave.startDate.add(Duration(days: di));
            for (final type in [MealType.lunch, MealType.dinner]) {
              final sk = _slotKey(day, type);
              if (!trulyVacatedSlots.contains(sk)) continue;
              final dayLabel = '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
              final typeLabel = type == MealType.lunch ? 'déjeuner' : 'dîner';
              vacatedLabels.add('$typeLabel du $dayLabel');
            }
          }
          if (!suppressDialogs && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  'La recette a changé — les restes de l\'ancienne recette ont été supprimés. ${vacatedLabels.length == 1 ? 'Créneau maintenant libre' : 'Créneaux maintenant libres'} : ${vacatedLabels.join(', ')}.',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                )),
              ]),
              backgroundColor: const Color(0xFF6A5AE0),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 6),
            ));
          }
        }

        planToSave = planToSave.copyWith(meals: prunedMeals);
      }

      await _mealPlanRepo.saveMealPlan(planToSave);
      await ShoppingListGenerator().generateAndSaveShoppingList(planToSave);

      if (mounted) setState(() => _generatedMealPlan = planToSave);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Remplit les slots vides apparus après un multi-shuffle
  /// (ex : restes supprimés dont le nouveau repas ne produit pas de restes).
  /// Utilise l'algorithme de planification pour choisir la meilleure recette.
  /// [skipSlotKeys] : slots qui étaient originalement des restes — on les ignore
  /// pour ne pas injecter un repas frais là où un reste devrait aller.
  /// [onlySlotKeys] : si non-null, seuls ces slots sont traités (ignore les autres vides).
  Future<void> _fillVacatedSlots({Set<String> skipSlotKeys = const {}, Set<String>? onlySlotKeys}) async {
    if (_generatedMealPlan == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Charger recettes + servings une seule fois pour tous les slots vides.
    final allRecipesRaw = await _loadRecipes();
    final allServings = await _loadServings();

    // Résoudre les noms d'ingrédients pour que la similarité fonctionne correctement.
    final allIngredientIds = allRecipesRaw
        .expand((r) => r.ingredients.map((i) => i.ingredient.id))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
    final allRecipes = allRecipesRaw.map((recipe) {
      final resolved = recipe.ingredients.map((ri) {
        final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
        return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
      }).toList();
      return recipe.copyWith(ingredients: resolved);
    }).toList();

    final validSelectedCategories =
        _selectedCategories.where((id) => _categoryDataById.containsKey(id)).toSet();
    final filteredRecipes = validSelectedCategories.isEmpty
        ? allRecipes
        : allRecipes
            .where((r) => r.categoryIds.any((c) => validSelectedCategories.contains(c)))
            .toList();
    if (filteredRecipes.isEmpty) return;

    final users = allServings
        .map((s) => s.userId)
        .toSet()
        .map((uid) => User(id: uid, name: uid))
        .toList();
    if (users.isEmpty) return;

    final currentUserIds = allServings.map((s) => s.userId).toSet();

    for (int i = 0; i < (_generatedMealPlan?.durationDays ?? 0); i++) {
      if (_generatedMealPlan == null) break;
      final day = _generatedMealPlan!.startDate.add(Duration(days: i));
      final dayNorm = DateTime(day.year, day.month, day.day);
      if (dayNorm.isBefore(today)) continue;

      for (final mealType in [MealType.lunch, MealType.dinner]) {
        if (_generatedMealPlan == null) break;
        // Skip slots that were originally leftovers — they should stay empty
        // or be filled naturally by leftover injection from the new source meal.
        if (skipSlotKeys.contains(_slotKey(day, mealType))) continue;
        // Si onlySlotKeys est fourni, ne traiter que ces slots spécifiques.
        if (onlySlotKeys != null && !onlySlotKeys.contains(_slotKey(day, mealType))) continue;
        final hasMeal = _generatedMealPlan!.meals.any((m) =>
            m.date.year == day.year &&
            m.date.month == day.month &&
            m.date.day == day.day &&
            m.type == mealType);
        if (hasMeal) continue;

        // Slot vide détecté — choisir la meilleure recette.

        // Compter les slots libres futurs (même type) disponibles pour des restes.
        final planEnd = _generatedMealPlan!.startDate
            .add(Duration(days: _generatedMealPlan!.durationDays - 1));
        int freeFollowingSlots = 0;
        DateTime checkDay = day.add(const Duration(days: 1));
        while (!DateTime(checkDay.year, checkDay.month, checkDay.day)
            .isAfter(DateTime(planEnd.year, planEnd.month, planEnd.day))) {
          final occupied = _generatedMealPlan!.meals.any((m) =>
              m.date.year == checkDay.year &&
              m.date.month == checkDay.month &&
              m.date.day == checkDay.day &&
              m.type == mealType);
          if (!occupied) freeFollowingSlots++;
          checkDay = checkDay.add(const Duration(days: 1));
        }

        // Si aucun slot suivant n'est libre, restreindre aux recettes sans restes.
        // Si aucune telle recette n'existe, laisser le slot vide et alerter.
        List<Recipe> recipesForSlot = filteredRecipes;
        if (freeFollowingSlots == 0) {
          final userPortions = allServings.fold<int>(0, (sum, s) =>
              sum + (mealType == MealType.lunch ? s.lunchServings : s.dinnerServings));
          final noLeftoverRecipes = filteredRecipes
              .where((r) => r.servings > 0 && userPortions % r.servings == 0)
              .toList();
          if (noLeftoverRecipes.isNotEmpty) {
            recipesForSlot = noLeftoverRecipes;
          } else {
            // Aucune recette sans restes disponible → slot laissé vide + alerte
            if (mounted) {
              final dayLabel =
                  '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
              final typeLabel = mealType == MealType.lunch ? 'déjeuner' : 'dîner';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour le $typeLabel du $dayLabel. Slot laissé vide.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            continue;
          }
        }

        final filteredHistory = _mealHistory.entries
            .expand((e) => e.value)
            .where((m) =>
                m.userServings.isEmpty ||
                m.userServings.keys.any((uid) => currentUserIds.contains(uid)))
            .toList();

        final otherPlanMeals = _generatedMealPlan!.meals
            .where((m) => !(
                m.date.year == day.year &&
                m.date.month == day.month &&
                m.date.day == day.day &&
                m.type == mealType))
            .toList();

        // Verrouille l'autre repas du même jour (s'il existe) pour que le slot
        // qui nous intéresse reçoive la bonne pénalité de similarité.
        final otherTypeForFill =
            mealType == MealType.lunch ? MealType.dinner : MealType.lunch;
        final sameDayOtherFillMeal = _generatedMealPlan!.meals.where((m) =>
            m.date.year == day.year &&
            m.date.month == day.month &&
            m.date.day == day.day &&
            m.type == otherTypeForFill &&
            !m.isLeftoverMeal).firstOrNull;
        final userSelectedForFill = sameDayOtherFillMeal != null
            ? [sameDayOtherFillMeal.copyWith(userSelected: true)]
            : <Meal>[];

        final tempPlan = MealPlanningService.generateMealPlan(
          recipes: recipesForSlot,
          servings: allServings,
          users: users,
          startDate: day,
          durationDays: 1,
          recentMeals: [...filteredHistory, ...otherPlanMeals],
          userSelectedMeals: userSelectedForFill.isEmpty ? null : userSelectedForFill,
          pantryItems: _pantryIngredients,
          selectedCategories: _selectedCategories.toList(),
          referenceDate: day,
        );

        final newMeal = tempPlan.meals
            .where((m) => m.type == mealType)
            .firstOrNull;
        if (newMeal == null) continue;

        // Insérer le repas dans le plan courant.
        final insertedMeal = newMeal.copyWith(date: day);
        final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals)
          ..add(insertedMeal);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        if (mounted) setState(() => _generatedMealPlan = updatedPlan);
        // Injecter un reste si la recette produit plus de portions que consommées.
        await _injectLeftoverIfNeeded(insertedMeal);
      }
    }
  }

  /// Shuffle unitaire : verrouille tous les autres slots et délègue à _shuffleFreeSlots.
  Future<void> _autoChangeMealRecipe(
    Meal mealToChange, {
    bool suppressDialogs = false,
  }) async {
    await _shuffleFreeSlots(
      {_slotKey(mealToChange.date, mealToChange.type)},
      suppressDialogs: suppressDialogs,
    );
  }
  /// Injecte un repas reste dans le slot du lendemain (même type) si la recette
  /// de [newMeal] produit plus de portions que consommées. Gère également le cas
  /// où le slot courant est lui-même un reste du jour précédent.
  ///
  /// Si [forceReplace] est true (choix explicite de l'utilisateur), les repas
  /// déjà présents dans les slots cibles sont supprimés pour laisser place aux restes.
  /// Retourne les slot keys des slots qui ont été vidés (pour pouvoir les re-remplir).
  Future<Set<String>> _injectLeftoverIfNeeded(Meal newMeal, {bool forceReplace = false}) async {
    final vacatedSlots = <String>{};
    if (_generatedMealPlan == null) return vacatedSlots;
    final cookedServings = newMeal.recipe.servings * newMeal.recipeMultiplier;
    final leftoverServings = cookedServings - newMeal.totalServings;
    if (leftoverServings <= 0) return vacatedSlots;

    final prevDay = newMeal.date.subtract(const Duration(days: 1));
    final prevDayHasSameRecipe = _generatedMealPlan!.meals.any((m) =>
        m.recipe.id == newMeal.recipe.id &&
        m.date.year == prevDay.year &&
        m.date.month == prevDay.month &&
        m.date.day == prevDay.day &&
        m.type == newMeal.type &&
        !m.isLeftoverMeal);
    if (prevDayHasSameRecipe) {
      // Le slot courant est lui-même un reste du jour précédent.
      final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals);
      final idx = updatedMeals.indexWhere((m) =>
          m.recipe.id == newMeal.recipe.id &&
          m.date.year == newMeal.date.year &&
          m.date.month == newMeal.date.month &&
          m.date.day == newMeal.date.day &&
          m.type == newMeal.type);
      if (idx != -1) {
        updatedMeals[idx] = updatedMeals[idx].copyWith(isLeftoverMeal: true);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        setState(() => _generatedMealPlan = updatedPlan);
      }
    } else {
      // Propage les portions restantes sur les jours suivants (même type),
      // en boucle comme generateMealPlan, jusqu'à épuisement ou fin du plan.
      final planEnd = _generatedMealPlan!.startDate
          .add(Duration(days: _generatedMealPlan!.durationDays - 1));
      final planEndNorm = DateTime(planEnd.year, planEnd.month, planEnd.day);

      var remainingLeft = leftoverServings;
      DateTime candidateDay = newMeal.date.add(const Duration(days: 1));

      while (remainingLeft > 0) {
        final candidateNorm = DateTime(
            candidateDay.year, candidateDay.month, candidateDay.day);
        if (candidateNorm.isAfter(planEndNorm)) break;

        // Ne pas injecter si la recette est déjà présente ce jour-là.
        final alreadyHasSame = _generatedMealPlan!.meals.any((m) =>
            m.date.year == candidateDay.year &&
            m.date.month == candidateDay.month &&
            m.date.day == candidateDay.day &&
            m.type == newMeal.type &&
            m.recipe.id == newMeal.recipe.id);
        if (alreadyHasSame) {
          candidateDay = candidateDay.add(const Duration(days: 1));
          continue;
        }

        // En mode forceReplace (choix explicite de l'utilisateur), on supprime
        // les repas déjà présents sur ce slot pour laisser place aux restes.
        // On supprime aussi tous les restes futurs des recettes écrasées pour
        // éviter les restes orphelins.
        // En mode normal (shuffle auto), on respecte les repas existants.
        if (forceReplace) {
          // Identifier les repas frais qui vont être écrasés (pour nettoyer leurs restes)
          final mealsToRemove = _generatedMealPlan!.meals.where((m) =>
              m.date.year == candidateDay.year &&
              m.date.month == candidateDay.month &&
              m.date.day == candidateDay.day &&
              m.type == newMeal.type).toList();
          final candidateDayNorm = DateTime(candidateDay.year, candidateDay.month, candidateDay.day);
          // Identifier les restes futurs des recettes écrasées AVANT suppression
          // pour les ajouter à vacatedSlots (ils deviendront des slots vides).
          final futureLeftoversOfErased = _generatedMealPlan!.meals.where((m) {
            if (!m.isLeftoverMeal) return false;
            final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
            if (!mDateNorm.isAfter(candidateDayNorm)) return false;
            return mealsToRemove.any((removed) =>
                !removed.isLeftoverMeal &&
                removed.recipe.id == m.recipe.id &&
                removed.type == m.type);
          }).toList();
          final updatedMealsForce = List<Meal>.from(_generatedMealPlan!.meals)
            ..removeWhere((m) {
              // Supprimer le repas du slot cible
              if (m.date.year == candidateDay.year &&
                  m.date.month == candidateDay.month &&
                  m.date.day == candidateDay.day &&
                  m.type == newMeal.type) return true;
              // Supprimer les restes futurs des recettes écrasées
              if (m.isLeftoverMeal) {
                final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
                if (mDateNorm.isAfter(candidateDayNorm)) {
                  return mealsToRemove.any((removed) =>
                      !removed.isLeftoverMeal &&
                      removed.recipe.id == m.recipe.id &&
                      removed.type == m.type);
                }
              }
              return false;
            });
          // Tracker les restes futurs supprimés → ils deviennent des slots vides à remplir
          for (final lo in futureLeftoversOfErased) {
            vacatedSlots.add(_slotKey(lo.date, lo.type));
          }
          _generatedMealPlan = _generatedMealPlan!.copyWith(meals: updatedMealsForce);
        }

        // Utilisateurs qui ont déjà un repas (frais OU reste) ce slot.
        // En mode forceReplace ils ont été supprimés ci-dessus, donc tous sont éligibles.
        final usersWithAnyMeal = forceReplace
            ? <String>{}
            : _generatedMealPlan!.meals
                .where((m) =>
                    m.date.year == candidateDay.year &&
                    m.date.month == candidateDay.month &&
                    m.date.day == candidateDay.day &&
                    m.type == newMeal.type)
                .expand((m) => m.userServings.keys)
                .toSet();

        // Calculer les portions à injecter pour ce slot.
        final leftoverUserServings = <String, int>{};
        int leftoverTotal = 0;
        final eligibleEntries = newMeal.userServings.entries
            .where((e) => !usersWithAnyMeal.contains(e.key))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        for (int idx = 0; idx < eligibleEntries.length; idx++) {
          if (remainingLeft <= 0) break;
          final entry = eligibleEntries[idx];
          final portionsNeeded = entry.value;
          final usersLeft = eligibleEntries.length - idx;
          final fairShare = max(1, remainingLeft ~/ usersLeft);
          final toAssign = min(portionsNeeded, min(fairShare, remainingLeft));
          if (toAssign > 0) {
            leftoverUserServings[entry.key] = toAssign;
            leftoverTotal += toAssign;
            remainingLeft -= toAssign;
          }
        }

        if (leftoverTotal == 0) {
          // Tous les users ont déjà un repas ce slot → arrêter la cascade.
          break;
        }

        final leftover = Meal(
          recipe: newMeal.recipe,
          date: candidateDay,
          type: newMeal.type,
          totalServings: leftoverTotal,
          userServings: leftoverUserServings,
          recipeMultiplier: 1,
          isLeftoverMeal: true,
        );
        final updatedMeals = List<Meal>.from(_generatedMealPlan!.meals)..add(leftover);
        final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedMeals);
        await _mealPlanRepo.saveMealPlan(updatedPlan);
        await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);
        setState(() => _generatedMealPlan = updatedPlan);

        candidateDay = candidateDay.add(const Duration(days: 1));
      }
    }
    return vacatedSlots;
  }
  /// Auto-fills an empty meal slot by picking a recipe with the planning algorithm.
  Future<void> _autoFillEmptySlot(DateTime date, MealType type) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allRecipesRaw = await _loadRecipes();
      final servings = await _loadServings();
      // Dériver les users à partir des servings (UIDs uniques)
      final users = servings
          .map((s) => s.userId)
          .toSet()
          .map((uid) => User(id: uid, name: uid))
          .toList();

      // Résoudre les noms d'ingrédients pour la similarité.
      final allIngredientIds = allRecipesRaw
          .expand((r) => r.ingredients.map((i) => i.ingredient.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameMap = await IngredientNameCache.instance.fetchNamesForIds(allIngredientIds);
      final allRecipes = allRecipesRaw.map((recipe) {
        final resolved = recipe.ingredients.map((ri) {
          final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
          return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
        }).toList();
        return recipe.copyWith(ingredients: resolved);
      }).toList();

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

      // Compter les slots libres futurs (même type) pour le check leftover.
      final planEndFill = _generatedMealPlan?.startDate
          .add(Duration(days: (_generatedMealPlan?.durationDays ?? 1) - 1));
      int freeFollowingFill = 0;
      if (planEndFill != null) {
        DateTime checkFill = date.add(const Duration(days: 1));
        final endNorm = DateTime(planEndFill.year, planEndFill.month, planEndFill.day);
        while (!DateTime(checkFill.year, checkFill.month, checkFill.day).isAfter(endNorm)) {
          final occupied = _generatedMealPlan!.meals.any((m) =>
              m.date.year == checkFill.year &&
              m.date.month == checkFill.month &&
              m.date.day == checkFill.day &&
              m.type == type);
          if (!occupied) freeFollowingFill++;
          checkFill = checkFill.add(const Duration(days: 1));
        }
      }

      Meal? _runFillAlgo(List<Recipe> recipes) {
        final plan = MealPlanningService.generateMealPlan(
          recipes: recipes,
          servings: servings,
          users: users,
          startDate: date,
          durationDays: 1,
          recentMeals: [...filteredHistory, ...otherPlanMeals],
          pantryItems: _pantryIngredients,
          selectedCategories: _selectedCategories.toList(),
          referenceDate: date,
        );
        return plan.meals.where((m) => m.type == type).firstOrNull;
      }

      // Première passe : algo sans restriction.
      Meal? newMeal = _runFillAlgo(filteredRecipes);
      if (newMeal == null) return;

      // Post-check : si aucun slot libre et la recette produit des restes, relancer avec filtre.
      if (freeFollowingFill == 0) {
        final cooked = newMeal.recipe.servings * newMeal.recipeMultiplier;
        if (cooked > newMeal.totalServings) {
          final actualConsumed = newMeal.totalServings;
          final noLeftover = filteredRecipes
              .where((r) => r.servings > 0 && actualConsumed % r.servings == 0)
              .toList();
          if (noLeftover.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour ce créneau. Slot inchangé.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            return;
          }
          final attempt2 = _runFillAlgo(noLeftover);
          final cooked2 = attempt2 != null
              ? attempt2.recipe.servings * attempt2.recipeMultiplier
              : 0;
          if (attempt2 == null || cooked2 > attempt2.totalServings) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune recette sans restes disponible pour ce créneau. Slot inchangé.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFFF9800),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
              ));
            }
            return;
          }
          newMeal = attempt2;
        }
      }

      setState(() => _isLoading = false);
      await _addMealToPlan(newMeal.recipe, date, type);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openRecipeDetail(Meal meal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: meal.recipe.id,
          initialRecipe: meal.recipe,
        ),
      ),
    ).then((_) {
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
        leftoverUserOrder: plan.leftoverUserOrder,
      );
      
      await ShoppingListGenerator().generateAndSaveShoppingList(planForShoppingList);

      if (!mounted) return savedId;
      // Removed the saved snackbar confirmation
      return savedId;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Affiche un dialog de confirmation pour modifier le frigo/placard.
  /// Retourne true si l'utilisateur accepte, false/null sinon.
  Future<bool?> _showPantryModificationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required Color color,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Non', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: Text(confirmLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMeal(Meal mealToDelete) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mealDate = DateTime(
        mealToDelete.date.year, mealToDelete.date.month, mealToDelete.date.day);
    final isHistory = mealDate.isBefore(today);

    if (isHistory) {
      // ── Suppression d'un repas historisé ──
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
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
                  'Supprimer de l\'historique ?',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            'Voulez-vous retirer "${mealToDelete.recipe.title}" de l\'historique ?',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              child: Text('Annuler', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
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
        // Mettre à jour l'historique local + Firestore
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        final previousMeals = List<Meal>.from(historyMeals);
        historyMeals.removeWhere((m) =>
            m.date.year == mealToDelete.date.year &&
            m.date.month == mealToDelete.date.month &&
            m.date.day == mealToDelete.date.day &&
            m.type == mealToDelete.type &&
            m.recipe.id == mealToDelete.recipe.id);

        if (historyMeals.isEmpty) {
          _mealHistory.remove(mealDate);
          await _historyRepo.deleteDayFromHistory(mealDate, mealsBeingDeleted: previousMeals);
        } else {
          _mealHistory[mealDate] = historyMeals;
          await _historyRepo.addDayToHistory(mealDate, historyMeals, previousMeals: previousMeals);
        }
        setState(() {});
      } finally {
        setState(() => _isLoading = false);
      }

      if (!mounted) return;
      // Proposer de remettre les ingrédients dans le frigo/placard
      final restorePantry = await _showPantryModificationDialog(
        title: 'Remettre dans le frigo/placard ?',
        message:
            'Ce plat n\'a pas été cuisiné. Voulez-vous remettre les ingrédients de "${mealToDelete.recipe.title}" dans le frigo/placard ?',
        confirmLabel: 'Oui, remettre',
        icon: Icons.kitchen_rounded,
        color: const Color(0xFF6A5AE0),
      );

      if (restorePantry == true) {
        setState(() => _isLoading = true);
        try {
          final fullRecipe =
              await _recipeRepo.fetchRecipeById(mealToDelete.recipe.id);
          if (fullRecipe != null) {
            final mealWithIngredients = mealToDelete.copyWith(recipe: fullRecipe);
            await FirebasePantryRepository.instance
                .restoreFromMeals([mealWithIngredients]);
            await _loadPantryFromRepository();
          }
        } finally {
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (_generatedMealPlan == null) return;

    // Vérifie si une deuxième occurrence (restes) existe le lendemain
    final nextDay = mealToDelete.date.add(const Duration(days: 1));
    final hasLeftover = !mealToDelete.isLeftoverMeal &&
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

      // Remove leftover of this recipe from next day if one exists
      if (!mealToDelete.isLeftoverMeal) {
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
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
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

  Future<void> _changeMealRecipe(Meal mealToUpdate, Recipe newRecipe, {bool showSnackbar = true, Meal? fullMeal, bool suppressLeftoverDialog = false}) async {
    setState(() => _isLoading = true);
    try {
      // Check if the meal belongs to history
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final mealDate = DateTime(mealToUpdate.date.year, mealToUpdate.date.month, mealToUpdate.date.day);
      final isHistory = mealDate.isBefore(today);

      if (isHistory) {
        // Edit the meal in history
        final historyMeals = List<Meal>.from(_mealHistory[mealDate] ?? []);
        final previousMeals = List<Meal>.from(historyMeals); // snapshot avant modif
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

        // Persist the change in Firestore history (diff pour usageCount)
        await _historyRepo.addDayToHistory(mealDate, historyMeals, previousMeals: previousMeals);

        // Sync the change back to the meal plan document so that deleting
        // history and re-adding doesn't restore the old recipe.
        if (_generatedMealPlan != null) {
          final planMealIndex = _generatedMealPlan!.meals.indexWhere((m) =>
              m.date.year == mealToUpdate.date.year &&
              m.date.month == mealToUpdate.date.month &&
              m.date.day == mealToUpdate.date.day &&
              m.type == mealToUpdate.type &&
              m.recipe.id == mealToUpdate.recipe.id);
          if (planMealIndex != -1) {
            final updatedPlanMeals = List<Meal>.from(_generatedMealPlan!.meals);
            updatedPlanMeals[planMealIndex] = historyMeals[indexToUpdate];
            final updatedPlan = _generatedMealPlan!.copyWith(meals: updatedPlanMeals);
            await _mealPlanRepo.saveMealPlan(updatedPlan);
            _generatedMealPlan = updatedPlan;
          }
        }

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

        // Proposer de REMETTRE les ingrédients de l'ANCIENNE recette dans le frigo/placard
        // (elle n'a pas été cuisinée)
        if (!mounted) return;
        final restorePantry = await _showPantryModificationDialog(
          title: 'Remettre dans le frigo/placard ?',
          message:
              'Vous n\'avez pas cuisiné "${mealToUpdate.recipe.title}". Voulez-vous remettre ses ingrédients dans le frigo/placard ?',
          confirmLabel: 'Oui, remettre',
          icon: Icons.kitchen_rounded,
          color: const Color(0xFF6A5AE0),
        );
        if (restorePantry == true) {
          setState(() => _isLoading = true);
          try {
            final oldFullRecipe = await _recipeRepo.fetchRecipeById(mealToUpdate.recipe.id);
            if (oldFullRecipe != null) {
              // Résoudre les noms des ingrédients (stockés séparément)
              final ids = oldFullRecipe.ingredients
                  .map((i) => i.ingredient.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              final nameMap = await IngredientNameCache.instance.fetchNamesForIds(ids);
              final resolved = oldFullRecipe.copyWith(
                ingredients: oldFullRecipe.ingredients.map((ri) {
                  final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
                  return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
                }).toList(),
              );
              final oldMeal = Meal(
                recipe: resolved,
                date: mealToUpdate.date,
                type: mealToUpdate.type,
                totalServings: resolved.servings,
                userServings: {},
                recipeMultiplier: 1,
                isLeftoverMeal: false,
                userSelected: true,
              );
              await FirebasePantryRepository.instance.restoreFromMeals([oldMeal]);
              await _loadPantryFromRepository();
            }
          } finally {
            setState(() => _isLoading = false);
          }
        }

        // Proposer de DÉDUIRE les ingrédients de la NOUVELLE recette du frigo/placard
        // (elle a été cuisinée à la place, et c'est un jour passé)
        if (!mounted) return;
        final deductPantry = await _showPantryModificationDialog(
          title: 'Déduire du frigo/placard ?',
          message:
              'Vous avez cuisiné "${newRecipe.title}" à la place. Voulez-vous déduire ses ingrédients du frigo/placard ?',
          confirmLabel: 'Oui, déduire',
          icon: Icons.kitchen_rounded,
          color: const Color(0xFF6A5AE0),
        );
        if (deductPantry == true) {
          setState(() => _isLoading = true);
          try {
            final fullRecipe = await _recipeRepo.fetchRecipeById(newRecipe.id);
            if (fullRecipe != null) {
              // Résoudre les noms des ingrédients (stockés séparément)
              final ids = fullRecipe.ingredients
                  .map((i) => i.ingredient.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              final nameMap = await IngredientNameCache.instance.fetchNamesForIds(ids);
              final resolved = fullRecipe.copyWith(
                ingredients: fullRecipe.ingredients.map((ri) {
                  final name = nameMap[ri.ingredient.id] ?? ri.ingredient.name;
                  return ri.copyWith(ingredient: ri.ingredient.copyWith(name: name));
                }).toList(),
              );
              final newMeal = Meal(
                recipe: resolved,
                date: mealToUpdate.date,
                type: mealToUpdate.type,
                totalServings: resolved.servings,
                userServings: {},
                recipeMultiplier: 1,
                isLeftoverMeal: false,
                userSelected: true,
              );
              await FirebasePantryRepository.instance.deductFromMeals([newMeal]);
              await _loadPantryFromRepository();
            }
          } finally {
            setState(() => _isLoading = false);
          }
        }
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

      // Remove ALL future leftovers of the old recipe (any day after the source meal).
      // Only removing J+1 left orphaned leftovers on J+2, J+3, etc., which then
      // blocked _injectLeftoverIfNeeded from cascading to those days correctly.
      if (!mealToUpdate.isLeftoverMeal) {
        final sourceDateNorm = DateTime(
            mealToUpdate.date.year, mealToUpdate.date.month, mealToUpdate.date.day);
        updatedMeals.removeWhere((m) {
          if (!m.isLeftoverMeal) return false;
          if (m.recipe.id != mealToUpdate.recipe.id) return false;
          if (m.type != mealToUpdate.type) return false;
          final mDateNorm = DateTime(m.date.year, m.date.month, m.date.day);
          return mDateNorm.isAfter(sourceDateNorm);
        });
      }

      // --- UPDATE CURRENT SLOT ---
      // Si un Meal complet est fourni (ex: shuffle), on l'utilise directement.
      // Sinon (sélection manuelle), on calcule les vrais userServings depuis
      // la config des portions pour détecter correctement les restes.
      final Meal savedMeal;
      if (fullMeal != null) {
        savedMeal = fullMeal.copyWith(
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          isLeftoverMeal: false,
          userSelected: true,
        );
      } else {
        // Calcul des portions réellement consommées depuis la config
        final allServings = await _loadServings();
        final userServingsMap = <String, int>{};
        int totalConsumed = 0;
        for (final s in allServings.where((s) => s.recipeId == newRecipe.id)) {
          final portions = mealToUpdate.type == MealType.lunch
              ? s.lunchServings
              : s.dinnerServings;
          if (portions > 0) {
            userServingsMap[s.userId] = portions;
            totalConsumed += portions;
          }
        }
        // Fallback si pas de config : toutes les portions consommées (pas de restes)
        savedMeal = Meal(
          recipe: newRecipe,
          date: mealToUpdate.date,
          type: mealToUpdate.type,
          totalServings: totalConsumed > 0 ? totalConsumed : newRecipe.servings,
          userServings: userServingsMap,
          recipeMultiplier: 1,
          isLeftoverMeal: false,
          userSelected: true,
        );
      }
      updatedMeals[indexToUpdate] = savedMeal;

      // --- SAVE ---

      final updatedPlan = MealPlan(
        id: _generatedMealPlan!.id,
        startDate: _generatedMealPlan!.startDate,
        durationDays: _generatedMealPlan!.durationDays,
        meals: updatedMeals,
        createdAt: _generatedMealPlan!.createdAt,
        pantryItems: _generatedMealPlan!.pantryItems,
        selectedCategories: _generatedMealPlan!.selectedCategories,
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
      );

      await _mealPlanRepo.saveMealPlan(updatedPlan);
      await ShoppingListGenerator().generateAndSaveShoppingList(updatedPlan);

      setState(() {
        _generatedMealPlan = updatedPlan;
      });

      // --- RESTES : proposer de cascader si la recette en produit ---
      if (!suppressLeftoverDialog && fullMeal == null) {
        final cookedServings = savedMeal.recipe.servings * savedMeal.recipeMultiplier;
        final leftoverServings = cookedServings - savedMeal.totalServings;
        if (leftoverServings > 0 && mounted) {
          final injectLeftovers = await _showPantryModificationDialog(
            title: 'Planifier les restes ?',
            message:
                '"${newRecipe.title}" donne $cookedServings portions pour ${savedMeal.totalServings} consommée${savedMeal.totalServings > 1 ? 's' : ''}. '
                'Voulez-vous planifier les $leftoverServings portion${leftoverServings > 1 ? 's' : ''} restante${leftoverServings > 1 ? 's' : ''} sur les jours suivants ?',
            confirmLabel: 'Oui, planifier',
            icon: Icons.restaurant_rounded,
            color: const Color(0xFF6A5AE0),
          );
          if (injectLeftovers == true) {
            final vacated = await _injectLeftoverIfNeeded(savedMeal, forceReplace: true);
            // Informer l'utilisateur des slots laissés vides suite aux écrasements.
            if (vacated.isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${vacated.length} créneau${vacated.length > 1 ? 'x' : ''} laissé${vacated.length > 1 ? 's' : ''} vide${vacated.length > 1 ? 's' : ''} suite aux restes. Ajoutez manuellement un repas si nécessaire.',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFF6A5AE0),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 6),
              ));
            }
          }
        }
      }

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
        leftoverUserOrder: _generatedMealPlan!.leftoverUserOrder,
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
      floatingActionButton: Padding(
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
                                  pantryCount: _pantryIngredients.length,
                                  urgentCount: _urgentPantryNames.length,
                                  pantrySnapshot: _pantrySnapshot,
                                  onViewPantrySnapshot: () {
                                    Navigator.pop(context);
                                    _showCurrentPantryDialog();
                                  },
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
                        const SizedBox(width: 8),
                        Consumer(
                          builder: (context, ref, _) {
                            final authState = ref.watch(authNotifierProvider);
                            if (authState is AuthAuthenticated && authState.user.role == 'admin') {
                              return Tooltip(
                                message: 'Administration',
                                child: Material(
                                  color: Colors.orange.shade700,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const AdminPage(),
                                        ),
                                      );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.admin_panel_settings_outlined,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        const SizedBox(width: 8),
                        Consumer(
                          builder: (context, ref, _) => Tooltip(
                            message: 'Déconnexion',
                            child: Material(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20)),
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
                                            child: const Icon(Icons.logout_rounded,
                                                color: Color(0xFF6A5AE0), size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Déconnexion',
                                              style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600, fontSize: 16),
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: Text(
                                        'Voulez-vous vous déconnecter ?',
                                        style: GoogleFonts.poppins(
                                            fontSize: 14, color: Colors.black54),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.black54),
                                          child: Text('Annuler',
                                              style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w500)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF6A5AE0),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 10),
                                            elevation: 0,
                                          ),
                                          child: Text('Déconnexion',
                                              style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .signOut();
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.logout_rounded,
                                    color: Color(0xFF555555),
                                    size: 24,
                                  ),
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
                      if (_generatedMealPlan == null && _mealHistory.isEmpty && !_isLoading) ...[
                        SizedBox(height: _mealHistory.isEmpty ? 40 : 16),
                        Builder(builder: (context) {
                          final header = _ModernPlannerHeader(
                            selectedStartDate: _selectedStartDate,
                            selectedDuration: _selectedDuration,
                            selectedCategories: _selectedCategories,
                            categoryDataById: _categoryDataById,
                            pantryCount: _pantryIngredients.length,
                            urgentCount: _urgentPantryNames.length,
                            pantrySnapshot: _pantrySnapshot,
                            onViewPantrySnapshot: _pantrySnapshot.isNotEmpty
                                ? _showPantrySnapshotDialog
                                : _pantryIngredients.isNotEmpty
                                    ? _showCurrentPantryDialog
                                    : null,
                            onPickStartDate: () {
                              _pickStartDate(onDatePicked: () => setState(() {}));
                            },
                            onPickDuration: () {
                              _pickDuration(onUpdated: () => setState(() {}));
                            },
                            onPickCategories: () {
                              _pickCategories(onUpdated: () => setState(() {}));
                            },
                            onLaunchPlanning: _launchPlanning,
                            isLoading: _isLoading,
                          );
                          return _mealHistory.isEmpty ? Center(child: header) : header;
                        }),
                        SizedBox(height: _mealHistory.isEmpty ? 40 : 12),
                      ],
                      if (_generatedMealPlan != null || _mealHistory.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        if (_generatedMealPlan != null) ...[
                          _buildPlanMetadata(),
                          const SizedBox(height: 12),
                        ],
                        _buildModernCalendar(),
                        const SizedBox(height: 12),
                        // ── Boutons supprimer ──
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _mealHistory.isNotEmpty ? _deleteHistory : null,
                                icon: const Icon(Icons.history_toggle_off_rounded, size: 15),
                                label: Text(
                                  'Supprimer l\'historique',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade600,
                                  side: BorderSide(color: Colors.red.shade200),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            if (_generatedMealPlan != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _deletePlan,
                                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                                  label: Text(
                                    'Supprimer le plan',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade600,
                                    side: BorderSide(color: Colors.red.shade200),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ── Zone multi-shuffle (plan uniquement) ──
                        if (_generatedMealPlan != null) ...[
                          if (!_isMultiShuffleMode)
                            // Mode inactif : bouton "Regénérer plusieurs repas"
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  if (_generatedMealPlan == null) {
                                    setState(() => _isMultiShuffleMode = true);
                                    return;
                                  }
                                  // Restaurer les locks persistés directement par slotKey.
                                  setState(() {
                                    _isMultiShuffleMode = true;
                                    _multiShuffleKeptSlots
                                      ..clear()
                                      ..addAll(_persistedLockedSlotKeys);
                                  });
                                },
                                icon: const Icon(Icons.autorenew, size: 18),
                                label: Text(
                                  'Regénérer plusieurs repas',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF9800),
                                  side: BorderSide(color: const Color(0xFFFF9800).withOpacity(0.6)),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            )
                          else
                            // Mode actif : carte avec instruction + boutons côte à côte
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8F0),
                                border: Border.all(
                                    color: const Color(0xFFFF9800).withOpacity(0.5)),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.touch_app_rounded,
                                          color: Color(0xFFFF9800), size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Touchez les repas à conserver, puis regénérez les autres',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => setState(() {
                                            _isMultiShuffleMode = false;
                                            _multiShuffleKeptSlots.clear();
                                          }),
                                          icon: const Icon(Icons.close_rounded, size: 15),
                                          label: Text('Annuler',
                                              style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.grey[700],
                                            side: BorderSide(color: Colors.grey.shade400),
                                            padding:
                                                const EdgeInsets.symmetric(vertical: 11),
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: ElevatedButton.icon(
                                          onPressed: _launchMultiShuffle,
                                          icon: const Icon(Icons.autorenew, size: 15),
                                          label: Text('Regénérer les autres',
                                              style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFF9800),
                                            foregroundColor: Colors.white,
                                            padding:
                                                const EdgeInsets.symmetric(vertical: 11),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 8),
                        _buildMealDetails(),
                        const SizedBox(height: 88),
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
    if (_pantrySnapshot.isEmpty) return const SizedBox();

    final urgentCount = _pantrySnapshot.where((i) => i.isUrgent).length;
    final normalCount = _pantrySnapshot.where((i) => !i.isUrgent).length;

    return GestureDetector(
      onTap: _showPantrySnapshotDialog,
      child: Container(
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.kitchen_rounded, size: 16, color: Color(0xFF6A5AE0)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frigo / Placard de ce plan',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (normalCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$normalCount normaux',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6A5AE0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (urgentCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🔥 $urgentCount urgents',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6A5AE0), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildModernCalendar() {
    final historyDates = _mealHistory.keys.toList();
    final historyMin = historyDates.isNotEmpty
        ? historyDates.reduce((a, b) => a.isBefore(b) ? a : b)
        : null;
    final historyMax = historyDates.isNotEmpty
        ? historyDates.reduce((a, b) => a.isAfter(b) ? a : b)
        : null;

    // Automatically choose calendar format based on plan duration (only on first load)
    if (_calendarFormat == null) {
      if (_generatedMealPlan != null) {
        final startDate = _generatedMealPlan!.startDate;
        final durationDays = _generatedMealPlan!.durationDays;
        final endDate = startDate.add(Duration(days: durationDays - 1));

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
          _calendarFormat = CalendarFormat.week;
        } else if (durationDays <= 14) {
          _calendarFormat = CalendarFormat.twoWeeks;
        } else {
          _calendarFormat = CalendarFormat.month;
        }
      } else {
        _calendarFormat = CalendarFormat.month;
      }
    }

    // Calculate the min/max range between history and plan
    final DateTime firstDay;
    final DateTime lastDay;
    if (_generatedMealPlan != null) {
      final planStart = _generatedMealPlan!.startDate;
      final planEnd = planStart.add(
        Duration(days: _generatedMealPlan!.durationDays - 1),
      );
      firstDay = historyMin != null && historyMin.isBefore(planStart)
          ? historyMin
          : planStart;
      lastDay = historyMax != null && historyMax.isAfter(planEnd)
          ? historyMax
          : planEnd;
    } else {
      // History-only mode
      firstDay = historyMin ?? DateTime.now();
      lastDay = historyMax ?? DateTime.now();
    }

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

    // Trier par nom alphabétique du premier utilisateur du repas pour un ordre stable
    String _firstUserName(Meal m) {
      if (m.userServings.isEmpty) return '';
      final names = m.userServings.keys
          .map((uid) => _userNames[uid] ?? uid)
          .toList()
        ..sort();
      return names.first;
    }

    final lunchMeals = mealsOfDay
        .where((m) => m.type == MealType.lunch)
        .toList()
      ..sort((a, b) => _firstUserName(a).compareTo(_firstUserName(b)));
    final dinnerMeals = mealsOfDay
        .where((m) => m.type == MealType.dinner)
        .toList()
      ..sort((a, b) => _firstUserName(a).compareTo(_firstUserName(b)));

    Widget buildMealCard(Meal meal) {
      final isKept = _multiShuffleKeptSlots.contains(_slotKey(meal.date, meal.type));
      final isSelectableMeal = _isMultiShuffleMode && !meal.isLeftoverMeal && !isPastDay;

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: isSelectableMeal
              ? () => setState(() {
                    final key = _slotKey(meal.date, meal.type);
                    if (_multiShuffleKeptSlots.contains(key)) {
                      _multiShuffleKeptSlots.remove(key);
                    } else {
                      _multiShuffleKeptSlots.add(key);
                    }
                  })
              : null,
          child: Stack(
            children: [
              Column(
                children: [
                  // ── Main content (tap to open recipe) ──
                  InkWell(
                    onTap: isSelectableMeal ? null : () => _openRecipeDetail(meal),
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
                                  // ...badge "X pers" supprimé...
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
            // ── Action bar (hidden in multi-shuffle mode) ──
            if (!_isMultiShuffleMode)
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.autorenew, color: Colors.grey.shade500, size: 22),
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, color: Colors.grey.shade500, size: 22),
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red.shade300, size: 22),
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
                ], // Column children
              ), // Column
              // ── Selection overlay (multi-shuffle mode) ──
              if (isSelectableMeal)
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isKept
                          ? Colors.green.withOpacity(0.18)
                          : Colors.orange.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isKept
                            ? Colors.green.withOpacity(0.7)
                            : Colors.orange.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: isKept
                              ? Container(
                                  key: const ValueKey('kept'),
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                                )
                              : Container(
                                  key: const ValueKey('shuffle'),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 16),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ], // Stack children
          ), // Stack
        ), // GestureDetector
      );
    }

    // ── Grouped slot card: une seule Card quand les repas diffèrent par user ──
    Widget buildSlotCard(List<Meal> meals) {
      if (meals.length == 1) return buildMealCard(meals.first);

      // Multi-recettes dans le même créneau → card unique avec une ligne par repas
      Widget rowBtn(IconData icon, Color color, VoidCallback onTap) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 22, color: color),
            ),
          ),
        );
      }

      Widget compactRow(Meal meal) {
        final userLabels = meal.userServings.isNotEmpty
            ? (meal.userServings.keys
                .map((uid) => _userNames[uid] ?? uid)
                .toList()
                ..sort((a, b) => a.compareTo(b)))
            : <String>[];

        final isKeptCompact = _multiShuffleKeptSlots.contains(_slotKey(meal.date, meal.type));
        final isSelectableCompact = _isMultiShuffleMode && !meal.isLeftoverMeal && !isPastDay;

        return GestureDetector(
          onTap: isSelectableCompact
              ? () => setState(() {
                    final key = _slotKey(meal.date, meal.type);
                    if (_multiShuffleKeptSlots.contains(key)) {
                      _multiShuffleKeptSlots.remove(key);
                    } else {
                      _multiShuffleKeptSlots.add(key);
                    }
                  })
              : null,
          child: Stack(
          children: [
            InkWell(
              onTap: isSelectableCompact ? null : () => _openRecipeDetail(meal),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // Icône
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: meal.isLeftoverMeal
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        meal.isLeftoverMeal ? Icons.restaurant : Icons.restaurant_menu,
                        color: meal.isLeftoverMeal ? Colors.orange : Colors.green,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Titre recette
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            meal.recipe.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (meal.isLeftoverMeal)
                            Text(
                              'Restes du repas précédent',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange[700],
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Chips noms utilisateurs
                    ...userLabels.map((name) => Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF6A5AE0).withOpacity(0.30)),
                          ),
                          child: Text(
                            name,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: const Color(0xFF6A5AE0),
                                fontWeight: FontWeight.w600),
                          ),
                        )),
                    const SizedBox(width: 4),
                    // Bouton Aléatoire (plan futur seulement)
                    if (!isPastDay && !_isMultiShuffleMode)
                      rowBtn(Icons.autorenew, Colors.grey.shade500,
                          () => _autoChangeMealRecipe(meal)),
                    // Bouton Chercher
                    if (!_isMultiShuffleMode)
                    rowBtn(Icons.search, Colors.grey.shade500, () async {
                      final now2 = DateTime.now();
                      final today2 =
                          DateTime(now2.year, now2.month, now2.day);
                      final mealDate2 = DateTime(
                          meal.date.year, meal.date.month, meal.date.day);
                      if (mealDate2.isBefore(today2)) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            titlePadding:
                                const EdgeInsets.fromLTRB(24, 24, 24, 0),
                            contentPadding:
                                const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            actionsPadding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            title: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.history,
                                    color: Colors.orange, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text('Repas historique',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16))),
                            ]),
                            content: Text(
                              "Ce repas fait partie de l'historique. Voulez-vous vraiment modifier la recette ?",
                              style: GoogleFonts.poppins(
                                  fontSize: 14, color: Colors.black54),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.black54),
                                child: Text('Annuler',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w500)),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF6A5AE0),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  elevation: 0,
                                ),
                                child: Text('Oui, modifier',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      } else {
                        _autoChangeBannedRecipes.clear();
                      }
                      _showRecipeSelector(
                          mealToUpdate: meal, requireConfirmation: false);
                    }),
                    // Bouton Supprimer
                    if (!_isMultiShuffleMode)
                    rowBtn(Icons.delete_outline, Colors.red.shade300,
                        () => _deleteMeal(meal)),
                  ],
                ),
              ),
            ),
            if (_loadingRecipeId == meal.recipe.id)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            // Selection overlay for multi-shuffle
            if (isSelectableCompact)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isKeptCompact
                        ? Colors.green.withOpacity(0.18)
                        : Colors.orange.withOpacity(0.06),
                    border: Border.all(
                      color: isKeptCompact
                          ? Colors.green.withOpacity(0.7)
                          : Colors.orange.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isKeptCompact
                            ? Container(
                                key: const ValueKey('keptC'),
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 14),
                              )
                            : Container(
                                key: const ValueKey('shuffleC'),
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 14),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          ), // Stack
        ); // GestureDetector
      }

      return Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int _i = 0; _i < meals.length; _i++) ...[
              if (_i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200),
              compactRow(meals[_i]),
            ],
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
      padding: EdgeInsets.zero,
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
            buildSlotCard(lunchMeals)
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
            buildSlotCard(dinnerMeals)
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
  
  final int pantryCount;
  final int urgentCount;
  final List<PantrySnapshotItem> pantrySnapshot;
  final VoidCallback? onViewPantrySnapshot;

  final VoidCallback onPickStartDate;
  final VoidCallback onPickDuration;
  final VoidCallback onPickCategories;
  final VoidCallback onLaunchPlanning;
  final bool isLoading;

  const _ModernPlannerHeader({
    required this.selectedStartDate,
    required this.selectedDuration,
    required this.selectedCategories,
    required this.categoryDataById,
    required this.pantryCount,
    required this.urgentCount,
    required this.pantrySnapshot,
    this.onViewPantrySnapshot,
    required this.onPickStartDate,
    required this.onPickDuration,
    required this.onPickCategories,
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
          GestureDetector(
            onTap: (pantrySnapshot.isNotEmpty || pantryCount > 0) ? onViewPantrySnapshot : null,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: urgentCount > 0
                    ? Colors.orange.withOpacity(0.5)
                    : pantryCount > 0
                        ? const Color(0xFF6A5AE0).withOpacity(0.3)
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
                  child: Icon(
                    Icons.kitchen_rounded,
                    color: urgentCount > 0 ? Colors.orange[700] : const Color(0xFF6A5AE0),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Frigo / Placard',
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pantryCount == 0
                            ? 'Aucun article renseigné'
                            : urgentCount > 0
                                ? '$pantryCount article${pantryCount > 1 ? 's' : ''} · $urgentCount urgent${urgentCount > 1 ? 's' : ''} 🔥'
                                : '$pantryCount article${pantryCount > 1 ? 's' : ''} disponible${pantryCount > 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: urgentCount > 0
                              ? Colors.orange[800]
                              : const Color(0xFF2D2D2D),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pantrySnapshot.isNotEmpty
                            ? 'Appuyez pour voir le frigo de ce plan'
                            : 'Gérez votre stock dans l\'onglet Frigo / Placard',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                if (pantrySnapshot.isNotEmpty)
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 18)
                else
                  const Icon(Icons.lock_outline_rounded, color: Colors.black12, size: 16),
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
