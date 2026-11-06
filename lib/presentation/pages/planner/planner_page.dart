import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../providers/auth_notifier.dart';
import '../../providers/auth_state.dart';

import '../../../data/repositories/firebase_meal_plan_repository.dart';
import '../../../data/repositories/firebase_meal_history_repository.dart';
import '../../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../../data/repositories/notification_settings_repository.dart';
import '../../../data/services/notification_service.dart';

import '../../../domain/entities/meal_plan.dart';
import '../../../domain/entities/recipe.dart';
import '../../../domain/entities/recipe_ingredient.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/user_recipe_serving.dart';
import '../../../domain/usecases/meal_planning_service.dart';
import '../../../domain/usecases/shopping_list_generator.dart';
import '../../../data/repositories/firebase_shopping_list_repository.dart';
import '../../../core/utils/ingredient_name_cache.dart';
import '../../../data/repositories/firebase_recipe_repository.dart';
import '../../../data/repositories/firebase_user_repository.dart';
import '../../../data/repositories/firebase_pantry_repository.dart';
import '../../../data/repositories/firebase_pantry_snapshot_repository.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../domain/entities/pantry_item.dart';
import '../../../core/utils/qty_format.dart';

import '../recipe_detail/recipe_detail_page.dart';
import '../meal_plan_notifications/meal_plan_notifications_page.dart';
import '../admin/admin_page.dart';
import '../../widgets/recipe_selector.dart';
import '../../widgets/pantry_input_dialog.dart';
import 'planner_header.dart';

part 'planner_data.dart';
part 'planner_pickers.dart';
part 'planner_pantry_dialogs.dart';
part 'planner_generation.dart';
part 'planner_multi_shuffle.dart';
part 'planner_leftovers.dart';
part 'planner_swap.dart';
part 'planner_meal_delete.dart';
part 'planner_meal_edit.dart';
part 'planner_plan_sections.dart';
part 'planner_meal_details.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

const _kPrefKeyCategories = 'selected_category_ids';
const _kPrefKeyDuration = 'planner_duration_days';
const _kPrefKeyLockedSlots = 'multi_shuffle_locked_slots';
const _kPrefKeyMinRating = 'planner_min_rating';

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
  double _selectedMinRating = 0.0; // 0 => all rated recipes allowed
  List<RecipeIngredient> _pantryIngredients = [];
  List<PantryItem> _rawPantryItems = [];
  Set<String> _urgentPantryNames = {};
  List<PantrySnapshotItem> _pantrySnapshot = [];
  
  // Stores ID -> {name, color}
  Map<String, Map<String, dynamic>> _categoryDataById = {};
  
  bool _isLoading = false;

  // Plan generation progress
  bool _isGenerating = false;
  double _generationProgress = 0.0;
  String _generationStep = '';

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

  /// Swap mode: the meal currently selected as source for a slot swap.
  /// When non-null, tapping another non-leftover future meal triggers the swap.
  Meal? _swapSourceMeal;

  /// Slot keys (date_mealType) verrouillés lors du dernier multi-shuffle.
  /// Persistés dans SharedPreferences et restaurés au prochain passage en mode multi-shuffle.
  Set<String> _persistedLockedSlotKeys = {};


  @override
  void initState() {
    super.initState();
    _loadAllCategories();
    _loadSavedPreferences();
    _loadMostRecentMealPlanAndHistory();
    _loadPantryFromRepository();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _generatedMealPlan == null ? null : Padding(
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
                                ModernPlannerHeader(
                                  selectedStartDate: _selectedStartDate,
                                  selectedDuration: _selectedDuration,
                                  selectedCategories: _selectedCategories,
                                  selectedMinRating: _selectedMinRating,
                                  categoryDataById: _categoryDataById,
                                  pantryCount: _pantryIngredients.length,
                                  urgentCount: _urgentPantryNames.length,
                                  pantrySnapshot: _pantrySnapshot,
                                  onViewPantrySnapshot: () {
                                    _showCurrentPantryDialog();
                                  },
                                  onPickDateRange: () {
                                    _pickDateRange(onUpdated: () => setModalState(() {}));
                                  },
                                  onPickCategories: () {
                                    _pickCategories(onUpdated: () => setModalState(() {}));
                                  },
                                  onMinRatingChanged: (v) {
                                    _saveMinRatingAndApply(v).then((_) => setModalState(() {}));
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
                            if (authState is! AuthAuthenticated) return const SizedBox.shrink();
                            final isAdmin = authState.user.role == 'admin';
                            return Tooltip(
                              message: 'Mon groupe',
                              child: Material(
                                color: isAdmin ? Colors.orange.shade700 : const Color(0xFF6A5AE0),
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AdminPage(isAdmin: isAdmin),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(
                                      isAdmin
                                          ? Icons.admin_panel_settings_outlined
                                          : Icons.group_outlined,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            );
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
                          final header = ModernPlannerHeader(
                            selectedStartDate: _selectedStartDate,
                            selectedDuration: _selectedDuration,
                            selectedCategories: _selectedCategories,
                            selectedMinRating: _selectedMinRating,
                            categoryDataById: _categoryDataById,
                            pantryCount: _pantryIngredients.length,
                            urgentCount: _urgentPantryNames.length,
                            pantrySnapshot: _pantrySnapshot,
                            onViewPantrySnapshot: _pantrySnapshot.isNotEmpty
                                ? _showPantrySnapshotDialog
                                : _pantryIngredients.isNotEmpty
                                    ? _showCurrentPantryDialog
                                    : null,
                            onPickDateRange: () {
                              _pickDateRange(onUpdated: () => setState(() {}));
                            },
                            onPickCategories: () {
                              _pickCategories(onUpdated: () => setState(() {}));
                            },
                            onMinRatingChanged: (v) {
                              _saveMinRatingAndApply(v);
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
                        // ── Bouton supprimer le plan ──
                        if (_generatedMealPlan != null)
                          SizedBox(
                            width: double.infinity,
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
                        // ── Zone swap (plan uniquement) ──
                        if (_generatedMealPlan != null && _swapSourceMeal != null) ...[
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FF),
                              border: Border.all(color: const Color(0xFF6A5AE0).withOpacity(0.4)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.compare_arrows_rounded, color: Color(0xFF6A5AE0), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Touchez un repas pour l\'échanger avec « ${_swapSourceMeal!.recipe.title} »',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Color(0xFF3D2F9E), fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(() => _swapSourceMeal = null),
                                  child: const Icon(Icons.close_rounded, color: Color(0xFF6A5AE0), size: 20),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
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
          if (_isGenerating)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            color: Color(0xFF6A5AE0),
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Génération du plan',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _generationStep,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _generationProgress,
                            minHeight: 8,
                            backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.12),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6A5AE0)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${(_generationProgress * 100).round()} %',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6A5AE0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_isLoading)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),

        ],
      ),
    );
  }


}
