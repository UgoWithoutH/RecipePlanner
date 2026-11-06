// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recipe_planner/domain/entities/category.dart';
import 'package:recipe_planner/presentation/widgets/ingredient_autocomplete.dart'
    show IngredientAutocomplete;
import '../../../core/constants/unit.dart' show Unit;
import '../../../core/constants/meal_time.dart';
import '../../../core/utils/qty_format.dart';
import '../../../domain/entities/ingredient.dart';
import '../../../domain/entities/recipe.dart';
import '../../../domain/entities/recipe_ingredient.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/user_recipe_serving.dart';
import '../../../data/repositories/firebase_recipe_repository.dart';
import '../../../data/repositories/firebase_category_repository.dart';
import '../../../data/repositories/firebase_ingredient_repository.dart';
import '../../../data/repositories/firebase_user_repository.dart';
import '../../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../../data/repositories/firebase_meal_plan_repository.dart';
import '../../../domain/usecases/shopping_list_generator.dart';
import '../../../domain/entities/ingredient_type.dart';
import '../../../data/repositories/firebase_ingredient_type_repository.dart';

import '../../../domain/entities/pending_ingredient.dart';

part 'create_recipe_data.dart';
part 'create_recipe_ingredient_dialogs.dart';
part 'create_recipe_instruction_dialogs.dart';
part 'create_recipe_inputs.dart';
part 'create_recipe_sections.dart';

class CreateRecipePage extends StatefulWidget {
  final Recipe? recipe;
  final Map<String, dynamic>? presetData;

  const CreateRecipePage({super.key, this.recipe, this.presetData});

  @override
  State<CreateRecipePage> createState() => _CreateRecipePageState();
}

class _CreateRecipePageState extends State<CreateRecipePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Recipe fields
  late TextEditingController _titleController;
  late TextEditingController _urlController;
  late TextEditingController _descriptionController;
  late TextEditingController _preparationTimeController;
  late TextEditingController _cookingTimeController;
  late TextEditingController _servingsController;

  // Ingredient fields
  late TextEditingController _ingredientNameController;
  late TextEditingController _ingredientQuantityController;
  late TextEditingController _ingredientNotesController;

  // Instruction inline form
  late TextEditingController _instructionController;

  Unit? _selectedIngredientUnit;
  final List<Unit> _units = Unit.values;

  // Portions scaling
  late FocusNode _servingsFocusNode;
  int _previousServings = 0;
  Timer? _servingsDebounceTimer;
  Timer? _stepperRepeatTimer;

  final List<RecipeIngredient> _ingredients = [];
  // Liste temporaire pour les nouveaux ingrédients à créer à la sauvegarde
  final List<PendingIngredient> _pendingIngredients = [];
  final List<String> _instructions = [];

  String? _selectedIngredientId;

  // Categories
  List<Category> _categories = [];
  List<String> _selectedCategoryIds = [];
  bool _isLoadingCategories = true;

  // Meal time preference
  MealTime _selectedMealTime = MealTime.both;

  // Ingredient Types
  List<IngredientType> _ingredientTypes = [];
  final FirebaseIngredientTypeRepository _ingredientTypeRepo =
      FirebaseIngredientTypeRepository();

  // Users & servings
  List<User> _users = [];
  final Map<String, UserRecipeServing> _userServings = {};

  // Repositories
  final FirebaseRecipeRepository _recipeRepo = FirebaseRecipeRepository();
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();
  final FirebaseIngredientRepository _ingredientRepo =
      FirebaseIngredientRepository();
  final FirebaseUserRepository _userRepo = FirebaseUserRepository();
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController();
    _urlController = TextEditingController();
    _descriptionController = TextEditingController();
    _preparationTimeController = TextEditingController();
    _cookingTimeController = TextEditingController();
    _servingsController = TextEditingController();

    _ingredientNameController = TextEditingController();
    _ingredientQuantityController = TextEditingController();
    _ingredientNotesController = TextEditingController();
    _instructionController = TextEditingController();

    _servingsFocusNode = FocusNode();
    _servingsFocusNode.addListener(() {
      if (!_servingsFocusNode.hasFocus) _onServingsEditingDone();
    });
    _previousServings = widget.recipe?.servings ?? 0;

    // Si presetData présent : attendre types ET catégories ensemble avant de pré-remplir
    if (widget.presetData != null && widget.recipe == null) {
      Future.wait([_loadIngredientTypes(), _loadCategories()]).then((_) {
        if (mounted && widget.presetData != null) _prefillFromPreset(widget.presetData!);
      });
    } else {
      _loadCategories();
      _loadIngredientTypes();
    }
    _loadUsers();

    if (widget.recipe != null) {
      final r = widget.recipe!;
      _titleController.text = r.title;
      _urlController.text = r.url ?? '';
      _descriptionController.text = r.description;
      _preparationTimeController.text = r.preparationTime.toString();
      _cookingTimeController.text = r.cookingTime.toString();
      _servingsController.text = r.servings.toString();
      if (mounted)
        setState(() => _selectedCategoryIds = List.from(r.categoryIds));
      _ingredients.addAll(r.ingredients);
      _instructions.addAll(r.instructions);
      _selectedMealTime = r.mealTime;
      _loadExistingServings();
    }
  }


  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    _preparationTimeController.dispose();
    _cookingTimeController.dispose();
    _servingsController.dispose();
    _ingredientNameController.dispose();
    _ingredientQuantityController.dispose();
    _ingredientNotesController.dispose();
    _instructionController.dispose();
    _servingsFocusNode.dispose();
    _servingsDebounceTimer?.cancel();
    _stepperRepeatTimer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFEFEFFC),
                    Colors.white,
                  ], // Very subtle purple fading to white
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _headerCircleButton(
                              Icons.arrow_back_ios_new_rounded,
                              () => Navigator.pop(context),
                            ),
                            Text(
                              widget.recipe == null
                                  ? 'Créer une recette'
                                  : 'Modifier la recette',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 40),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCategorySelector(),
                              _buildTextField(_titleController, 'Titre *'),
                              _buildTextField(
                                isRequired: false,
                                _descriptionController,
                                'Description',
                                maxLines: 3,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                _urlController,
                                'URL',
                                isRequired: false,
                                keyboardType: TextInputType.url,
                              ),
                              _buildNumberStepper(
                                controller: _servingsController,
                                label: 'Portions *',
                                min: 1,
                                max: 99,
                                focusNode: _servingsFocusNode,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildNumberStepper(
                                      controller: _preparationTimeController,
                                      label: 'Préparation (min) *',
                                      min: 0,
                                      max: 999,
                                      step: 5,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildNumberStepper(
                                      controller: _cookingTimeController,
                                      label: 'Cuisson (min) *',
                                      min: 0,
                                      max: 999,
                                      step: 5,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 32),
                              _buildIngredientsSection(),
                              const SizedBox(height: 32),
                              _buildInstructionsSection(),
                              _buildMealTimeSelectorSection(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // FAB Positioned at bottom right
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: Material(
                    borderRadius: BorderRadius.circular(30),
                    elevation: 8,
                    shadowColor: const Color(0xFF6A5AE0).withOpacity(0.4),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6A5AE0).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: _isSaving ? null : _saveRecipe,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSaving)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                ),

                              if (!_isSaving) ...[
                                const SizedBox(width: 12),
                                Text(
                                  'Enregistrer',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
