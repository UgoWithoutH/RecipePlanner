import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/entities/category.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_category_repository.dart';
import 'create_recipe_page.dart';

class RecipeDetailPage extends StatefulWidget {
  final Recipe recipe;

  const RecipeDetailPage({super.key, required this.recipe});

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Recipe _recipe;
  bool _isDeleting = false;

  List<UserRecipeServing> _userServings = [];
  bool _isLoadingServings = true;
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();

  List<Category> _categories = [];
  String? _categoryName;
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
    _loadUserServings();
    _loadCategories();
  }

  Future<void> _loadUserServings() async {
    if (_recipe.id.isEmpty) return;
    final servings = await _userServingRepo.fetchServingsForRecipe(_recipe.id);
    if (!mounted) return;
    setState(() {
      _userServings = servings;
      _isLoadingServings = false;
    });
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryRepo.getCategories();
    if (!mounted) return;

    setState(() {
      _categories = categories;
      final cat = _categories.firstWhere(
        (c) => c.id == _recipe.category,
        orElse: () => Category(id: '', name: 'Unknown'),
      );
      _categoryName = cat.name;
    });
  }

  Future<void> _deleteRecipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la recette'),
        content: const Text('Voulez-vous vraiment supprimer cette recette ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    await FirebaseRecipeRepository().deleteRecipe(_recipe.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// CUSTOM HEADER (BUTTONS AT TOP + TITLE BELOW)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            /// Back button
                            _headerIcon(
                              Icons.arrow_back,
                              () => Navigator.pop(context),
                              color: Colors.black87,
                            ),

                            /// Edit / delete actions
                            Row(
                              children: [
                                _headerIcon(Icons.edit, () async {
                                  final updatedRecipe =
                                      await Navigator.push<Recipe>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              CreateRecipePage(recipe: _recipe),
                                        ),
                                      );

                                  if (updatedRecipe != null && mounted) {
                                    setState(() => _recipe = updatedRecipe);
                                    _loadUserServings();
                                    _loadCategories();
                                  }
                                }, color: Colors.blue),
                                const SizedBox(width: 8),
                                _headerIcon(
                                  Icons.delete,
                                  _isDeleting ? null : _deleteRecipe,
                                  color: Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        /// TITLE BELOW
                        Text(
                          _recipe.title,
                          maxLines: 2,
                          overflow: TextOverflow
                              .ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                      ],
                    ),
                  ),

                  /// RECIPE CONTENT
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _recipe.description,
                          style: const TextStyle(fontSize: 16),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            const Icon(
                              Icons.category,
                              size: 20,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _categoryName ?? _recipe.category,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _infoItem(
                              Icons.timer,
                              'Prépa : ${_recipe.preparationTime} min',
                            ),
                            _infoItem(
                              Icons.restaurant,
                              'Cuisson : ${_recipe.cookingTime} min',
                            ),
                            _infoItem(
                              Icons.people,
                              'Portions : ${_recipe.servings}',
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        if (_recipe.addExtraMeal)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_available, color: Colors.green),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "Cette recette génère un repas supplémentaire pour tous les utilisateurs dans le planning",
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const Text(
                          'Ingrédients',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        ..._recipe.ingredients.map(
                          (i) => Card(
                            child: ListTile(
                              title: Text(i.ingredient.name),
                              subtitle: i.notes != null ? Text(i.notes!) : null,
                              trailing: Text('${i.quantity} ${i.unit.label}'),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'Instructions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._recipe.instructions.asMap().entries.map(
                          (e) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(e.value),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'Portions par utilisateur',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (_isLoadingServings)
                          const Center(child: CircularProgressIndicator())
                        else if (_userServings.isEmpty)
                          const Text('Aucune portion enregistrée')
                        else
                          Column(
                            children: [
                              ..._userServings
                                  .map(
                                    (s) => Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text(s.userName)),
                                            Text('Déj : ${s.lunchServings}'),
                                            const SizedBox(width: 16),
                                            Text('Dîner : ${s.dinnerServings}'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              if (_recipe.addExtraMeal)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.event_available, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          "Cette recette génère un repas supplémentaire pour tous les utilisateurs dans le planning",
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isDeleting)
              Container(
                color: Colors.black45,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(
    IconData icon,
    VoidCallback? onTap, {
    Color color = const Color(0xFF6A5AE0),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}
