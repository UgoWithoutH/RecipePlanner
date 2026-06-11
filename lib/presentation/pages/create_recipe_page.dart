// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recipe_planner/domain/entities/category.dart';
import 'package:recipe_planner/presentation/widgets/ingredient_autocomplete.dart'
    show IngredientAutocomplete;
import '../../core/constants/unit.dart' show Unit;
import '../../core/constants/meal_time.dart';
import '../../core/utils/qty_format.dart';
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

  Future<void> _loadIngredientTypes() async {
    try {
      final types = await _ingredientTypeRepo.getTypes() ?? [];
      if (mounted) setState(() => _ingredientTypes = types);
    } catch (_) {}
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
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (mounted) setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  // _waitForTypesAndPrefill supprimé : remplacé par Future.wait dans initState

  void _prefillFromPreset(Map<String, dynamic> preset) {
    // Libérer le focus avant de modifier les controllers pour éviter RangeError
    FocusManager.instance.primaryFocus?.unfocus();

    _titleController.value = TextEditingValue(text: preset['title'] as String? ?? '');
    _descriptionController.value = TextEditingValue(text: preset['description'] as String? ?? '');
    _preparationTimeController.value = TextEditingValue(
        text: ((preset['preparationTime'] as num?)?.toInt() ?? 0).toString());
    _cookingTimeController.value = TextEditingValue(
        text: ((preset['cookingTime'] as num?)?.toInt() ?? 0).toString());
    _servingsController.value = TextEditingValue(
        text: ((preset['servings'] as num?)?.toInt() ?? 4).toString());

    // Match category names → IDs
    final presetCats =
        List<String>.from(preset['categories'] as List? ?? []);
    _selectedCategoryIds = _categories
        .where((c) => presetCats.contains(c.name))
        .map((c) => c.id)
        .toList();

    // Instructions
    _instructions
      ..clear()
      ..addAll(List<String>.from(preset['instructions'] as List? ?? []));

    // Ingredients
    _ingredients.clear();
    _pendingIngredients.clear();
    final rawIngredients = preset['ingredients'] as List? ?? [];
    for (final raw in rawIngredients) {
      final i = Map<String, dynamic>.from(raw as Map);
      final name = i['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final qty = (i['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitLabel = i['unit'] as String? ?? '';
      final typeName = i['type'] as String? ?? '';

      // Match unit label to Unit enum
      final unit = Unit.values.firstWhere(
        (u) => u.label == unitLabel || u.name == unitLabel,
        orElse: () => Unit.piece,
      );

      // Match type name to typeId
      final typeMatch = _ingredientTypes.firstWhere(
        (t) => t.name == typeName,
        orElse: () => IngredientType(id: '', name: '', color: 0xFFBDBDBD),
      );
      final typeId = typeMatch.id.isNotEmpty ? typeMatch.id : null;

      _pendingIngredients.add(PendingIngredient(
        name: name,
        typeId: typeId,
        quantity: qty,
        unit: unit,
        notes: null,
      ));
      _ingredients.add(RecipeIngredient(
        ingredient: Ingredient(id: '', name: name, typeId: typeId),
        quantity: qty,
        unit: unit,
        notes: null,
      ));
    }

    setState(() {});
  }

  Future<void> _loadUsers() async {
    final users = await _userRepo.getUsers();
    if (!mounted) return;
    setState(() => _users = users);
    // Init default servings (1 lunch + 1 dinner) for new recipes
    if (widget.recipe == null) {
      for (final user in users) {
        _userServings.putIfAbsent(user.id, () => UserRecipeServing(
          userId: user.id,
          recipeId: '',
          lunchServings: 1,
          dinnerServings: 1,
          userName: user.name,
          recipeTitle: '',
        ));
      }
    }
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

  Future<bool> _recipeTitleExists(String title, {String? excludeId}) async {
    final recipes = await _recipeRepo.fetchRecipesByTitle(
      title.trim().toLowerCase(),
    );
    if (excludeId != null) {
      return recipes.any((r) => r.id != excludeId);
    }
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
          quantity: parseQty(_ingredientQuantityController.text),
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
          quantity: parseQty(_ingredientQuantityController.text),
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

  // ── Delete confirmation sheet ─────────────────────────────────────────────

  Future<bool?> _showDeleteConfirmSheet({required String title, required String message}) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Icône rouge
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit ingredient ────────────────────────────────────────────────────────

  Future<void> _showEditIngredientDialog(int index) async {
    final ingredient = _ingredients[index];
    final nameController = TextEditingController(text: ingredient.ingredient.name);
    final qtyController = TextEditingController(text: fmtQty(ingredient.quantity));
    final notesController = TextEditingController(text: ingredient.notes ?? '');
    Unit selectedUnit = ingredient.unit;
    String resolvedId = ingredient.ingredient.id;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget inputBox({
              required TextEditingController ctrl,
              required String hint,
              TextInputType? inputType,
              List<TextInputFormatter>? formatters,
            }) =>
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: ctrl,
                    keyboardType: inputType,
                    inputFormatters: formatters,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: GoogleFonts.poppins(
                          color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF6A5AE0)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Modifier l\'ingrédient',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Nom avec autocomplete
                  Autocomplete<Map<String, String>>(
                    initialValue: TextEditingValue(text: nameController.text),
                    optionsBuilder: (tv) async {
                      final q = tv.text.trim();
                      if (q.isEmpty) return [];
                      return await IngredientAutocomplete.suggestIngredients(q);
                    },
                    displayStringForOption: (o) => o['name']!,
                    fieldViewBuilder: (ctx2, ctrl, fn, _) {
                      ctrl.addListener(() {
                        nameController.text = ctrl.text;
                        resolvedId = '';
                      });
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: ctrl,
                          focusNode: fn,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: InputBorder.none,
                            hintText: 'Nom de l\'ingrédient',
                            hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                          ),
                        ),
                      );
                    },
                    optionsViewBuilder: (ctx2, onSel, opts) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            children: opts.map((o) => ListTile(
                              dense: true,
                              title: Text(o['name']!, style: GoogleFonts.poppins(fontSize: 13)),
                              onTap: () => onSel(o),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                    onSelected: (o) {
                      nameController.text = o['name']!;
                      resolvedId = o['id'] ?? '';
                    },
                  ),
                  const SizedBox(height: 12),
                  // Quantité + Unité
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: inputBox(
                          ctrl: qtyController,
                          hint: 'Qté',
                          inputType: const TextInputType.numberWithOptions(decimal: true),
                          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Unit>(
                              value: selectedUnit,
                              isExpanded: true,
                              icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                              dropdownColor: Colors.white,
                              selectedItemBuilder: (context) => Unit.values.map((u) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Unité', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                                  Text(u.label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                                ],
                              )).toList(),
                              items: Unit.values.map((u) => DropdownMenuItem<Unit>(
                                value: u,
                                child: Text(u.label, style: GoogleFonts.poppins(fontSize: 14)),
                              )).toList(),
                              onChanged: (u) { if (u != null) setStateDialog(() => selectedUnit = u); },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  inputBox(ctrl: notesController, hint: 'Préparation (ex: finement haché)'),
                  const SizedBox(height: 16),
                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final newName = nameController.text.trim();
                            final newQty = parseQty(qtyController.text, fallback: ingredient.quantity);
                            if (newName.isEmpty) return;
                            setState(() {
                              _ingredients[index] = RecipeIngredient(
                                ingredient: ingredient.ingredient.copyWith(name: newName, id: resolvedId),
                                quantity: newQty,
                                unit: selectedUnit,
                                notes: notesController.text.isEmpty ? null : notesController.text,
                              );
                              final pIdx = _pendingIngredients.indexWhere(
                                  (p) => p.name == ingredient.ingredient.name);
                              if (pIdx != -1) {
                                final old = _pendingIngredients[pIdx];
                                _pendingIngredients[pIdx] = PendingIngredient(
                                  name: newName,
                                  typeId: old.typeId,
                                  quantity: newQty,
                                  unit: selectedUnit,
                                  notes: notesController.text.isEmpty ? null : notesController.text,
                                );
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6A5AE0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Enregistrer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Edit instruction ─────────────────────────────────────────────────────────

  /// [editIndex] null → ajout, non-null → modification de l'étape à cet index.
  Future<void> _showEditInstructionDialog(int index) async {
    final controller = TextEditingController(text: _instructions[index]);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A5AE0).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6A5AE0),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Modifier l\'étape ${index + 1}',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Text input
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87, height: 1.6),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                  hintText: 'Décrivez l\'étape...',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      setState(() => _instructions[index] = text);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A5AE0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Enregistrer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInstructionDialog({int? editIndex}) async {
    final controller = TextEditingController(
      text: editIndex != null ? _instructions[editIndex] : '',
    );
    final isEdit = editIndex != null;
    final stepNumber = isEdit ? editIndex! + 1 : _instructions.length + 1;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6A5AE0),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$stepNumber',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Modifier l\'étape' : 'Nouvelle étape',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Text input
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: 7,
                maxLines: 12,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87, height: 1.6),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: 'Décrivez l\'étape en détail...',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Save button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A5AE0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                setState(() {
                  if (isEdit) {
                    _instructions[editIndex!] = text;
                  } else {
                    _instructions.add(text);
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(
                isEdit ? 'Enregistrer' : 'Ajouter l\'étape',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
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

    if (await _recipeTitleExists(_titleController.text, excludeId: widget.recipe?.id)) {
      _showError('Une recette avec ce titre existe déjà dans le groupe');
      return;
    }

    if (_ingredients.isEmpty) {
      _showError('Ajoutez au moins un ingrédient');
      return;
    }

    // Vérifier que la somme des portions utilisateurs ne dépasse pas le nombre de portions de la recette (midi et soir séparément)
    final int recipeServings = int.tryParse(_servingsController.text) ?? 0;
    final int totalLunch = _selectedMealTime == MealTime.dinnerOnly
        ? 0
        : _userServings.values.fold(0, (sum, s) => sum + s.lunchServings);
    final int totalDinner = _selectedMealTime == MealTime.lunchOnly
        ? 0
        : _userServings.values.fold(0, (sum, s) => sum + s.dinnerServings);
    if (totalLunch > recipeServings || totalDinner > recipeServings) {
      final List<String> overflowParts = [];
      if (totalLunch > recipeServings) {
        overflowParts.add('le midi ($totalLunch portion${totalLunch > 1 ? 's' : ''})');
      }
      if (totalDinner > recipeServings) {
        overflowParts.add('le soir ($totalDinner portion${totalDinner > 1 ? 's' : ''})');
      }
      _showError(
        'La somme des portions dépasse le nombre de portions de la recette ($recipeServings) pour : ${overflowParts.join(' et ')}',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Créer les nouveaux ingrédients en parallèle et récupérer les IDs
      if (_pendingIngredients.isNotEmpty) {
        final creates = await Future.wait(
          _pendingIngredients.map((p) => _ingredientRepo.createIngredientWithType(p.name, p.typeId)),
        );
        for (int i = 0; i < _pendingIngredients.length; i++) {
          final pending = _pendingIngredients[i];
          final newId = creates[i];
          final idx = _ingredients.indexWhere(
            (ri) => ri.ingredient.id == '' && ri.ingredient.name == pending.name,
          );
          if (idx != -1) {
            final old = _ingredients[idx];
            _ingredients[idx] = RecipeIngredient(
              ingredient: Ingredient(id: newId, name: pending.name, typeId: pending.typeId),
              quantity: old.quantity,
              unit: old.unit,
              notes: old.notes,
            );
          }
        }
        _pendingIngredients.clear();
      }

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
        mealTime: _selectedMealTime,
      );

      if (widget.recipe == null) {
        recipeId = await _recipeRepo.createRecipe(recipe);
      } else {
        await _recipeRepo.updateRecipe(recipe);
        recipeId = recipe.id;

        // Si mise à jour d'une recette : propager les changements aux plans existants
        // et regénérer leurs listes de courses en parallèle.
        final planRepo = FirebaseMealPlanRepository();
        final updatedPlans = await planRepo.updatePlansForRecipe(recipe);
        if (updatedPlans.isNotEmpty) {
          await Future.wait(
            updatedPlans.map((plan) => ShoppingListGenerator().generateAndSaveShoppingList(plan)),
          );
        }
      }

      // Sauvegarder les portions utilisateurs en parallèle
      await Future.wait(
        _userServings.values.map((s) => _userServingRepo.save(s.copyWith(recipeId: recipeId))),
      );

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
          if (_isLoadingCategories)
            const Center(child: CircularProgressIndicator())
          else if (_categories.isEmpty)
            const SizedBox.shrink()
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
                          controller.value = TextEditingValue(
                            text: _ingredientNameController.text,
                          );
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Unit>(
                          value: _selectedIngredientUnit,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                          dropdownColor: Colors.white,
                          hint: Text('Unité', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400])),
                          selectedItemBuilder: (context) => Unit.values.map((u) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Unité', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                              Text(u.label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                            ],
                          )).toList(),
                          items: Unit.values.map((u) => DropdownMenuItem<Unit>(
                            value: u,
                            child: Text(u.label, style: GoogleFonts.poppins(fontSize: 14)),
                          )).toList(),
                          onChanged: (u) => setState(() => _selectedIngredientUnit = u),
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
              const SizedBox(height: 12),
              _buildModernInput(
                _ingredientNotesController,
                'Préparation (ex: finement haché)',
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
                        border: Border.all(color: Colors.grey[100]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
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
                                          borderRadius:
                                              BorderRadius.circular(12),
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
                                      '- ${fmtQty(ingredient.quantity)} ${ingredient.unit.label}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                if (ingredient.notes != null &&
                                    ingredient.notes!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      ingredient.notes!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _showEditIngredientDialog(index),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6A5AE0).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6A5AE0)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () async {
                                  final confirm = await _showDeleteConfirmSheet(
                                    title: 'Supprimer l\'ingrédient',
                                    message: 'Voulez-vous vraiment supprimer "${_ingredients[index].ingredient.name}" ?',
                                  );
                                  if (confirm == true) setState(() => _ingredients.removeAt(index));
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[400]),
                                ),
                              ),
                            ],
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
      // Allow decimals with comma or dot for ingredient quantity
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
        Text(
          'Instructions',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        // Inline add form
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: _instructionController,
                    minLines: 3,
                    maxLines: 6,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87, height: 1.6),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                      hintText: 'Décrivez l\'étape ${_instructions.length + 1}...',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'addInstruction',
                onPressed: () {
                  final text = _instructionController.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    _instructions.add(text);
                    _instructionController.clear();
                  });
                },
                backgroundColor: const Color(0xFF6A5AE0),
                foregroundColor: Colors.white,
                elevation: 0,
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (_instructions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.format_list_numbered_rounded, size: 32, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    'Aucune étape ajoutée',
                    style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: _instructions.asMap().entries.map((entry) {
              final index = entry.key;
              final instruction = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[100]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF6A5AE0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          instruction,
                          style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _showEditInstructionDialog(index),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6A5AE0).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6A5AE0)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final confirm = await _showDeleteConfirmSheet(
                                title: 'Supprimer l\'étape',
                                message: 'Voulez-vous vraiment supprimer l\'étape ${index + 1} ?',
                              );
                              if (confirm == true) {
                                setState(() => _instructions.removeAt(index));
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[400]),
                            ),
                          ),
                        ],
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

  Widget _buildMealTimeSelectorSection() {
    const purple = Color(0xFF6A5AE0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Moment du repas',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Définit quand cette recette peut être planifiée',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 12),
        Row(
          children: MealTime.values.map((mt) {
            final selected = _selectedMealTime == mt;
            final icon = mt == MealTime.lunchOnly
                ? Icons.wb_sunny_rounded
                : mt == MealTime.dinnerOnly
                    ? Icons.nights_stay_rounded
                    : Icons.today_rounded;
            final color = mt == MealTime.lunchOnly
                ? Colors.orange.shade700
                : mt == MealTime.dinnerOnly
                    ? const Color(0xFF5C6BC0)
                    : purple;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedMealTime = mt;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: selected ? color.withOpacity(0.12) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? color : Colors.grey.shade200,
                        width: selected ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icon, size: 20, color: selected ? color : Colors.grey[400]),
                        const SizedBox(height: 4),
                        Text(
                          mt.shortLabel,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? color : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
            final lunchDefault = _selectedMealTime == MealTime.dinnerOnly
                ? 0
                : isNewRecipe ? 1 : (_userServings[user.id]?.lunchServings ?? 0);
            final dinnerDefault = _selectedMealTime == MealTime.lunchOnly
                ? 0
                : isNewRecipe ? 1 : (_userServings[user.id]?.dinnerServings ?? 0);
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
                lunchServings: _selectedMealTime == MealTime.dinnerOnly ? 0 : 1,
                dinnerServings: _selectedMealTime == MealTime.lunchOnly ? 0 : 1,
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
                      user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : '?',
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
                  Opacity(
                    opacity: _selectedMealTime == MealTime.dinnerOnly ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _selectedMealTime == MealTime.dinnerOnly,
                      child: _buildServingInput(
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dinner Input
                  Opacity(
                    opacity: _selectedMealTime == MealTime.lunchOnly ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _selectedMealTime == MealTime.lunchOnly,
                      child: _buildServingInput(
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
