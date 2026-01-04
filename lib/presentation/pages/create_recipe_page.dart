// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:recipe_planner/domain/entities/category.dart';
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

class CreateRecipePage extends StatefulWidget {
  final Recipe? recipe;

  const CreateRecipePage({super.key, this.recipe});

  @override
  State<CreateRecipePage> createState() => _CreateRecipePageState();
}

class _CreateRecipePageState extends State<CreateRecipePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Recipe fields
  late TextEditingController _titleController;
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
  final List<String> _instructions = [];

  String? _selectedIngredientId;

  // Categories
  List<Category> _categories = [];
  String? _selectedCategoryId;

  // Users & portions
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
    _descriptionController = TextEditingController();
    _preparationTimeController = TextEditingController();
    _cookingTimeController = TextEditingController();
    _servingsController = TextEditingController();

    _ingredientNameController = TextEditingController();
    _ingredientQuantityController = TextEditingController();
    _ingredientNotesController = TextEditingController();

    _loadCategories();
    _loadUsers();

    if (widget.recipe != null) {
      final r = widget.recipe!;
      _titleController.text = r.title;
      _descriptionController.text = r.description;
      _preparationTimeController.text = r.preparationTime.toString();
      _cookingTimeController.text = r.cookingTime.toString();
      _servingsController.text = r.servings.toString();
      _selectedCategoryId = r.category;
      _ingredients.addAll(r.ingredients);
      _instructions.addAll(r.instructions);
      _loadExistingServings();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  /// Load existing servings for the recipe if editing
  Future<void> _loadExistingServings() async {
    if (widget.recipe == null) return;

    // Fetch servings for this recipe
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all ingredient fields')),
      );
      return;
    }

    final id =
        _selectedIngredientId ??
        await _ingredientRepo.getOrCreateIngredientId(
          _ingredientNameController.text.trim(),
        );

    setState(() {
      _ingredients.add(
        RecipeIngredient(
          ingredient: Ingredient(
            id: id,
            name: _ingredientNameController.text.trim(),
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

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    // Check category
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    // Check recipe title uniqueness if creating new
    if (widget.recipe == null &&
        await _recipeTitleExists(_titleController.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recipe already exists')));
      return;
    }

    // Check ingredients and instructions
    if (_ingredients.isEmpty || _instructions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add ingredients and instructions')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String recipeId;
      final recipe = Recipe(
        id: widget.recipe?.id ?? '', // leave empty if new
        title: _titleController.text.trim().toLowerCase(),
        description: _descriptionController.text,
        preparationTime: int.parse(_preparationTimeController.text),
        cookingTime: int.parse(_cookingTimeController.text),
        servings: int.parse(_servingsController.text),
        category: _selectedCategoryId!,
        ingredients: _ingredients,
        instructions: _instructions,
        createdAt: widget.recipe?.createdAt ?? DateTime.now(),
      );

      if (widget.recipe == null) {
        // Create new recipe and get the generated ID
        recipeId = await _recipeRepo.createRecipe(
          recipe,
        ); // make sure this returns the doc ID
      } else {
        await _recipeRepo.updateRecipe(recipe);
        recipeId = recipe.id;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving recipe: $e')));
    }
  }

  // ------------------------
  // UI Builders
  // ------------------------

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: _selectedCategoryId,
        decoration: const InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(),
        ),
        items: _categories
            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
            .toList(),
        onChanged: (v) => setState(() => _selectedCategoryId = v),
        validator: (v) => v == null ? 'Please select a category' : null,
      ),
    );
  }

  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingredients',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Autocomplete<Map<String, String>>(
          optionsBuilder: (TextEditingValue textEditingValue) async {
            final query = textEditingValue.text.trim();
            if (query.isEmpty) return <Map<String, String>>[];
            return await _ingredientRepo.searchIngredients(query);
          },
          displayStringForOption: (option) => option['name']!,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.text != _ingredientNameController.text) {
                controller.text = _ingredientNameController.text;
                controller.selection = _ingredientNameController.selection;
              }
            });

            controller.addListener(() {
              _ingredientNameController.value = controller.value;
            });

            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            );
          },
          onSelected: (selectedIngredient) {
            _ingredientNameController.text = selectedIngredient['name']!;
            _selectedIngredientId = selectedIngredient['id'];
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _ingredientQuantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<Unit>(
                value: _selectedIngredientUnit,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _units
                    .map(
                      (u) => DropdownMenuItem(value: u, child: Text(u.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedIngredientUnit = v),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _addIngredient, child: const Text('Add')),
          ],
        ),
        const SizedBox(height: 12),
        _ingredients.isEmpty
            ? const Text('No ingredients added yet')
            : Column(
                children: _ingredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ingredient = entry.value;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(ingredient.ingredient.name),
                      subtitle: Text(
                        '${ingredient.quantity} ${ingredient.unit.label}' +
                            (ingredient.notes != null
                                ? ' (${ingredient.notes})'
                                : ''),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            setState(() => _ingredients.removeAt(index)),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildInstructionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Instructions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _instructions.isEmpty
            ? const Text('No instructions added yet')
            : Column(
                children: _instructions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final instruction = entry.value;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(instruction),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            setState(() => _instructions.removeAt(index)),
                      ),
                    ),
                  );
                }).toList(),
              ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            final controller = TextEditingController();
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Add Instruction'),
                content: TextField(controller: controller),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        setState(() => _instructions.add(controller.text));
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            );
          },
          child: const Text('Add Instruction'),
        ),
      ],
    );
  }

  Widget _buildUserServingsSection() {
    if (_users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'User Portions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Column(
          children: _users.map((user) {
            // Use existing servings if available
            final lunchController = TextEditingController(
              text: _userServings[user.id]?.lunchServings.toString() ?? '0',
            );
            final dinnerController = TextEditingController(
              text: _userServings[user.id]?.dinnerServings.toString() ?? '0',
            );

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: Text(user.name)),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: lunchController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Lunch'),
                        onChanged: (v) {
                          final existing = _userServings[user.id];
                          _userServings[user.id] = UserRecipeServing(
                            userId: user.id,
                            recipeId: widget.recipe?.id ?? '',
                            lunchServings:
                                int.tryParse(v) ?? existing?.lunchServings ?? 0,
                            dinnerServings: existing?.dinnerServings ?? 0,
                            userName: user.name,
                            recipeTitle: _titleController.text.trim(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: dinnerController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Dinner'),
                        onChanged: (v) {
                          final existing = _userServings[user.id];
                          _userServings[user.id] = UserRecipeServing(
                            userId: user.id,
                            recipeId: widget.recipe?.id ?? '',
                            lunchServings: existing?.lunchServings ?? 0,
                            dinnerServings:
                                int.tryParse(v) ??
                                existing?.dinnerServings ??
                                0,
                            userName: user.name,
                            recipeTitle: _titleController.text.trim(),
                          );
                        },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'Create Recipe' : 'Edit Recipe'),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16).copyWith(bottom: 250),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(_titleController, 'Title'),
                  _buildTextField(
                    _descriptionController,
                    'Description',
                    maxLines: 3,
                  ),
                  _buildCategoryDropdown(),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _preparationTimeController,
                          'Prep (min)',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _cookingTimeController,
                          'Cook (min)',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _servingsController,
                    'Servings',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  _buildIngredientsSection(),
                  const SizedBox(height: 24),
                  _buildInstructionsSection(),
                  _buildUserServingsSection(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveRecipe,
                      child: const Text('Save Recipe'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
