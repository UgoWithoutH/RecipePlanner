// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recipe_planner/domain/entities/category.dart';
import 'package:recipe_planner/presentation/widgets/ingredient_autocomplete.dart'
    show IngredientAutocomplete;
import '../../core/constants/unit.dart' show Unit;
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_category_repository.dart';
import '../../data/repositories/firebase_ingredient_repository.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../domain/usecases/shopping_list_generator.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';

import '../../domain/entities/pending_ingredient.dart';

class CreateRecipePage extends StatefulWidget {
  final Recipe? recipe;

  const CreateRecipePage({super.key, this.recipe});

  @override
  State<CreateRecipePage> createState() => _CreateRecipePageState();
}

class _CreateRecipePageState extends State<CreateRecipePage> {
  // Field for the addExtraMeal switch
  bool _addExtraMeal = false;
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

  Unit? _selectedIngredientUnit;
  final List<Unit> _units = Unit.values;

  final List<RecipeIngredient> _ingredients = [];
  // Liste temporaire pour les nouveaux ingrédients à créer à la sauvegarde
  final List<PendingIngredient> _pendingIngredients = [];
  final List<String> _instructions = [];

  String? _selectedIngredientId;

  // Categories
  List<Category> _categories = [];
  List<String> _selectedCategoryIds = [];

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

    _loadCategories();
    _loadUsers();
    _loadIngredientTypes();

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
      _addExtraMeal = r.addExtraMeal;
      _loadExistingServings();
    }
  }

  Future<void> _loadIngredientTypes() async {
    final types = await _ingredientTypeRepo.getTypes() ?? [];
    if (mounted) setState(() => _ingredientTypes = types);
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
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryRepo.getCategories();
    if (mounted) setState(() => _categories = categories);
  }

  Future<void> _loadUsers() async {
    final users = await _userRepo.getUsers();
    if (mounted) setState(() => _users = users);
  }

  Future<void> _loadExistingServings() async {
    if (widget.recipe == null) return;

    final servings = await _userServingRepo.fetchServingsForRecipe(
      widget.recipe!.id,
    );

    if (!mounted) return;

    setState(() {
      for (var serving in servings) {
        _userServings[serving.userId] = serving;
      }
    });
  }

  Future<bool> _recipeTitleExists(String title) async {
    final recipes = await _recipeRepo.fetchRecipesByTitle(
      title.trim().toLowerCase(),
    );
    return recipes.isNotEmpty;
  }

  Future<void> _addIngredient() async {
    if (_ingredientNameController.text.isEmpty ||
        _ingredientQuantityController.text.isEmpty ||
        _selectedIngredientUnit == null) {
      _showError('Remplissez tous les champs ingrédient');
      return;
    }

    String inputName = _ingredientNameController.text.trim();
    // Vérifie si un ingrédient avec le même nom existe déjà dans la recette (case-insensitive)
    final duplicate = _ingredients.any(
      (ri) => ri.ingredient.name.toLowerCase() == inputName.toLowerCase(),
    );
    if (duplicate) {
      _showError('Cet ingrédient a déjà été ajouté à la recette.');
      return;
    }

    String? id = _selectedIngredientId;
    String? selectedTypeId;
    String? existingTypeId;
    String nameToUse = inputName;

    // Check if ingredient exists
    if (id == null) {
      // Cherche l'ingrédient existant (non sensible à la casse)
      final existing = await _ingredientRepo.getIngredientByNameCaseInsensitive(
        inputName,
      );
      if (existing != null) {
        id = existing['id'];
        existingTypeId = existing['typeId'];
        nameToUse = existing['name'] ?? inputName;
      } else {
        // Prompt for type selection
        selectedTypeId = await _showTypeSelectionDialog(inputName);
        if (selectedTypeId == null) {
          // User cancelled
          return;
        }
        // Ajoute à la liste temporaire, id sera résolu à la sauvegarde
        final pending = PendingIngredient(
          name: inputName,
          typeId: selectedTypeId,
          quantity: double.parse(_ingredientQuantityController.text),
          unit: _selectedIngredientUnit!,
          notes: _ingredientNotesController.text.isEmpty
              ? null
              : _ingredientNotesController.text,
        );
        setState(() {
          _pendingIngredients.add(pending);
          _ingredients.add(
            RecipeIngredient(
              ingredient: Ingredient(
                id: '', // temporaire, sera remplacé à la sauvegarde
                name: inputName,
                typeId: selectedTypeId,
              ),
              quantity: pending.quantity,
              unit: pending.unit,
              notes: pending.notes,
            ),
          );
          _ingredientNameController.clear();
          _ingredientQuantityController.clear();
          _ingredientNotesController.clear();
          _selectedIngredientUnit = null;
          _selectedIngredientId = null;
        });
        return;
      }
    } else {
      // Si on a un id, on va chercher le type
      final existing = await _ingredientRepo.getIngredientByNameCaseInsensitive(
        inputName,
      );
      if (existing != null) {
        existingTypeId = existing['typeId'];
        nameToUse = existing['name'] ?? inputName;
      }
    }

    // Ajoute l'ingrédient existant (ou modifié) à la liste
    setState(() {
      _ingredients.add(
        RecipeIngredient(
          ingredient: Ingredient(
            id: id!,
            name: nameToUse,
            typeId: existingTypeId,
          ),
          quantity: double.parse(_ingredientQuantityController.text),
          unit: _selectedIngredientUnit!,
          notes: _ingredientNotesController.text.isEmpty
              ? null
              : _ingredientNotesController.text,
        ),
      );

      _ingredientNameController.clear();
      _ingredientQuantityController.clear();
      _ingredientNotesController.clear();
      _selectedIngredientUnit = null;
      _selectedIngredientId = null;
    });
  }

  Future<String?> _showTypeSelectionDialog(String ingredientName) async {
    String? selectedTypeId;
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Nouveau ingrédient',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L\'ingrédient "$ingredientName" n\'existe pas. Sélectionnez un type pour le créer.',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                const SizedBox(height: 20),
                Text(
                  'Type',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedTypeId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Aucun type',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    ),
                    ..._ingredientTypes.map((type) {
                      return DropdownMenuItem(
                        value: type.id,
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Color(type.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(type.name, style: GoogleFonts.poppins()),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) =>
                      setStateDialog(() => selectedTypeId = val),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.poppins(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, selectedTypeId),
                child: Text(
                  'Créer',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6A5AE0),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.recipe == null &&
        await _recipeTitleExists(_titleController.text)) {
      _showError('Une recette avec ce titre existe déjà');
      return;
    }

    if (_ingredients.isEmpty) {
      _showError('Ajoutez au moins un ingrédient');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Créer les nouveaux ingrédients en base et mettre à jour les IDs dans _ingredients
      for (int i = 0; i < _pendingIngredients.length; i++) {
        final pending = _pendingIngredients[i];
        final newId = await _ingredientRepo.createIngredientWithType(
          pending.name,
          pending.typeId,
        );
        // Met à jour l'ID dans la liste _ingredients
        final idx = _ingredients.indexWhere(
          (ri) => ri.ingredient.id == '' && ri.ingredient.name == pending.name,
        );
        if (idx != -1) {
          final old = _ingredients[idx];
          _ingredients[idx] = RecipeIngredient(
            ingredient: Ingredient(
              id: newId,
              name: pending.name,
              typeId: pending.typeId,
            ),
            quantity: old.quantity,
            unit: old.unit,
            notes: old.notes,
          );
        }
      }
      _pendingIngredients.clear();

      // 2. Sauvegarde la recette normalement
      String recipeId;
      final recipe = Recipe(
        id: widget.recipe?.id ?? '',
        title: _titleController.text.trim().toLowerCase(),
        description: _descriptionController.text,
        preparationTime: int.parse(_preparationTimeController.text),
        cookingTime: int.parse(_cookingTimeController.text),
        servings: int.parse(_servingsController.text),
        categoryIds: _selectedCategoryIds,
        ingredients: _ingredients,
        instructions: _instructions,
        createdAt: widget.recipe?.createdAt ?? DateTime.now(),
        addExtraMeal: _addExtraMeal,
      );

      if (widget.recipe == null) {
        recipeId = await _recipeRepo.createRecipe(recipe);
      } else {
        await _recipeRepo.updateRecipe(recipe);
        recipeId = recipe.id;

        // If updating a recipe, propagate changes to existing meal plans
        // and regenerate their shopping lists.
        final planRepo = FirebaseMealPlanRepository();
        final updatedPlans = await planRepo.updatePlansForRecipe(recipe);

        for (final plan in updatedPlans) {
          await ShoppingListGenerator().generateAndSaveShoppingList(plan);
        }
      }

      for (var userServing in _userServings.values) {
        final updatedServing = userServing.copyWith(recipeId: recipeId);
        await _userServingRepo.save(updatedServing);
      }

      if (!mounted) return;
      final recipeToReturn = recipe.copyWith(id: recipeId);
      Navigator.pop(context, recipeToReturn);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Erreur lors de la sauvegarde : $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE53935), // Less flashy red
        behavior:
            SnackBarBehavior.floating, // Floating creates the "bubble" effect
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        elevation: 4,
      ),
    );
  }

  // ------------------------
  // UI Builders
  // ------------------------

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool isRequired = true,
  }) {
    // Defines input formatters if keyboardType is number
    List<TextInputFormatter>? inputFormatters;
    if (keyboardType == TextInputType.number) {
      inputFormatters = [FilteringTextInputFormatter.digitsOnly];
    }

    // Nettoyer le label pour le placeholder (enlever le *)
    final String cleanLabel = label.contains('*')
        ? label.replaceAll('*', '').trim()
        : label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: controller,
              maxLines: maxLines,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: GoogleFonts.poppins(fontSize: 15),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: InputBorder.none,
                hintText: 'Entrez $cleanLabel...',
                hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
              ),
              validator: (v) {
                if (!isRequired) return null;
                return v == null || v.isEmpty ? 'Requis' : null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catégorie',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedCategoryIds.contains(category.id);
                  final categoryColor = Color(category.color);

                  final hsl = HSLColor.fromColor(categoryColor);
                  final startLightness = hsl.lightness;
                  final textLightness = startLightness > 0.4
                      ? 0.4
                      : startLightness;
                  final textColor = hsl.withLightness(textLightness).toColor();

                  return FilterChip(
                    label: Text(
                      category.name,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategoryIds.add(category.id);
                        } else {
                          _selectedCategoryIds.remove(category.id);
                        }
                      });
                    },
                    backgroundColor: categoryColor.withOpacity(0.15),
                    selectedColor: categoryColor.withOpacity(0.35),
                    checkmarkColor: textColor,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ingrédients',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        // Add Form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Autocomplete<Map<String, String>>(
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  final query = textEditingValue.text.trim();
                  if (query.isEmpty) return <Map<String, String>>[];
                  // Use the centralized suggestion logic
                  return await IngredientAutocomplete.suggestIngredients(query);
                },
                displayStringForOption: (option) => option['name']!,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (controller.text != _ingredientNameController.text) {
                          controller.text = _ingredientNameController.text;
                          controller.selection =
                              _ingredientNameController.selection;
                        }
                      });
                      controller.addListener(() {
                        _ingredientNameController.value = controller.value;
                        // Dès que l'utilisateur modifie le champ, on réinitialise l'id sélectionné
                        _selectedIngredientId = null;
                      });
                      return _buildModernInput(
                        controller,
                        'Nom (ex: Farine)',
                        focusNode: focusNode,
                      );
                    },
                onSelected: (selectedIngredient) {
                  _ingredientNameController.text = selectedIngredient['name']!;
                  _selectedIngredientId = selectedIngredient['id'];
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildModernInput(
                      _ingredientQuantityController,
                      'Qté',
                      inputType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Unit>(
                          value: _selectedIngredientUnit,
                          hint: Text(
                            'Unité',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                          isExpanded: true,
                          items: _units
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    u.label,
                                    style: GoogleFonts.poppins(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedIngredientUnit = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.small(
                    onPressed: _addIngredient,
                    backgroundColor: const Color(0xFF6A5AE0),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _ingredients.isEmpty
            ? Text(
                'Aucun ingrédient ajouté',
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Column(
                children: _ingredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ingredient = entry.value;
                  // Cherche le type associé à l'ingrédient
                  final type = _ingredientTypes.firstWhere(
                    (t) => t.id == ingredient.ingredient.typeId,
                    orElse: () =>
                        IngredientType(id: '', name: '', color: 0xFFBDBDBD),
                  );
                  final hasType =
                      ingredient.ingredient.typeId != null &&
                      type.id.isNotEmpty;
                  // Couleur logique similaire aux catégories
                  final typeColor = Color(type.color).withOpacity(0.15);
                  final hsl = HSLColor.fromColor(Color(type.color));
                  final startLightness = hsl.lightness;
                  final textLightness = startLightness > 0.4
                      ? 0.4
                      : startLightness;
                  final textColor = hsl.withLightness(textLightness).toColor();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6A5AE0),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  ingredient.ingredient.name,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (hasType) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: typeColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Color(type.color),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          type.name,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  '- ${ingredient.quantity} ${ingredient.unit.label}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () =>
                                setState(() => _ingredients.removeAt(index)),
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildModernInput(
    TextEditingController controller,
    String hint, {
    TextInputType? inputType,
    FocusNode? focusNode,
  }) {
    List<TextInputFormatter>? inputFormatters;
    if (inputType == TextInputType.number) {
      // Allow decimals for ingredient quantity
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ];
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: inputType == TextInputType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : inputType,
        inputFormatters: inputFormatters,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildInstructionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Instructions',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final controller = TextEditingController();
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(
                      'Ajouter une étape',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                    ),
                    content: SizedBox(
                      width: 400,
                      height: 180,
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 180,
                              maxHeight: 180,
                            ),
                            child: TextField(
                              controller: controller,
                              style: GoogleFonts.poppins(),
                              minLines: null,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                hintText: "Décrivez l'étape...",
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: const Color(0xFF6A5AE0),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Annuler',
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (controller.text.isNotEmpty) {
                            setState(() => _instructions.add(controller.text));
                            Navigator.pop(context);
                          }
                        },
                        child: Text(
                          'Ajouter',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF6A5AE0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: Text(
                "Ajouter",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _instructions.isEmpty
            ? Text(
                'Aucune instruction',
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Column(
                children: _instructions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final instruction = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6A5AE0),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            instruction,
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                        InkWell(
                          onTap: () =>
                              setState(() => _instructions.removeAt(index)),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildUserServingsSection() {
    if (_users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Portions par utilisateur',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Column(
          children: _users.map((user) {
            // Si la recette est en création (pas d'id), on met 1 par défaut
            final isNewRecipe = widget.recipe == null;
            final lunchDefault = isNewRecipe ? 1 : (_userServings[user.id]?.lunchServings ?? 0);
            final dinnerDefault = isNewRecipe ? 1 : (_userServings[user.id]?.dinnerServings ?? 0);
            final lunchController = TextEditingController(
              text: lunchDefault.toString(),
            );
            final dinnerController = TextEditingController(
              text: dinnerDefault.toString(),
            );

            // Important: update logic needs to be preserved or handled carefully
            // The previous logic created new UserRecipeServing objects on change.
            // I will keep that logic but inside a nicer UI.

            // Si la recette est en création, initialiser la map _userServings pour chaque user
            if (isNewRecipe && _userServings[user.id] == null) {
              _userServings[user.id] = UserRecipeServing(
                userId: user.id,
                recipeId: '',
                lunchServings: 1,
                dinnerServings: 1,
                userName: user.name,
                recipeTitle: _titleController.text.trim(),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.1),
                    radius: 20,
                    child: Text(
                      user.name.substring(0, 1).toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6A5AE0),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  // Lunch Input
                  _buildServingInput(
                    lunchController,
                    Icons.wb_sunny_rounded,
                    Colors.orange,
                    (v) {
                      final existing = _userServings[user.id];
                      _userServings[user.id] = UserRecipeServing(
                        userId: user.id,
                        recipeId: widget.recipe?.id ?? '',
                        lunchServings:
                            int.tryParse(v) ?? existing?.lunchServings ?? 1,
                        dinnerServings: existing?.dinnerServings ?? 1,
                        userName: user.name,
                        recipeTitle: _titleController.text.trim(),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Dinner Input
                  _buildServingInput(
                    dinnerController,
                    Icons.nights_stay_rounded,
                    const Color(0xFF5C6BC0),
                    (v) {
                      final existing = _userServings[user.id];
                      _userServings[user.id] = UserRecipeServing(
                        userId: user.id,
                        recipeId: widget.recipe?.id ?? '',
                        lunchServings: existing?.lunchServings ?? 1,
                        dinnerServings:
                            int.tryParse(v) ?? existing?.dinnerServings ?? 1,
                        userName: user.name,
                        recipeTitle: _titleController.text.trim(),
                      );
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildServingInput(
    TextEditingController controller,
    IconData icon,
    Color color,
    Function(String) onChanged,
  ) {
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------
  // BUILD PAGE
  // ------------------------

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
                            const SizedBox(
                              width: 40,
                            ), // Balance the back button
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
                              _buildTextField(
                                _servingsController,
                                'Portions globales (ex: 4) *',
                                keyboardType: TextInputType.number,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      _preparationTimeController,
                                      'Préparation (min) *',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildTextField(
                                      _cookingTimeController,
                                      'Cuisson (min) *',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),

                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.05),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Switch(
                                      value: _addExtraMeal,
                                      activeColor: Colors.green,
                                      onChanged: (val) {
                                        setState(() {
                                          _addExtraMeal = val;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Génère un repas supplémentaire pour le planning",
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Colors.green[800],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              _buildIngredientsSection(),
                              const SizedBox(height: 32),
                              _buildInstructionsSection(),
                              _buildUserServingsSection(),
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

  Widget _headerCircleButton(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}
