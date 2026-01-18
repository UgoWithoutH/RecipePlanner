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
  final int? ingredientMultiplier;
  final bool showAddExtraMealBadge;

  const RecipeDetailPage({
    super.key,
    required this.recipe,
    this.ingredientMultiplier,
    this.showAddExtraMealBadge = true,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Recipe _recipe;
  int? _ingredientMultiplier;
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
    _ingredientMultiplier = widget.ingredientMultiplier;
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
          
          SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      /// CUSTOM HEADER (BUTTONS AT TOP)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            /// Back button
                            _headerCircleButton(
                              Icons.arrow_back_ios_new_rounded,
                              () => Navigator.pop(context),
                            ),

                            /// Edit / delete actions
                            Row(
                              children: [
                                _headerCircleButton(
                                  Icons.edit_rounded, 
                                  () async {
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
                                  }, 
                                  color: Colors.blueAccent
                                ),
                                const SizedBox(width: 12),
                                _headerCircleButton(
                                  Icons.delete_outline_rounded,
                                  _isDeleting ? null : _deleteRecipe,
                                  color: Colors.redAccent,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Main Content Area
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            // Category Badge
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurpleAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (_categoryName ?? _recipe.category).toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.deepPurpleAccent,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            /// TITLE
                            Text(
                              _recipe.title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A1A1A),
                                height: 1.2,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Description
                            Text(
                              _recipe.description,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey[600],
                                height: 1.6,
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Stats Row
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildModernStatItem(
                                    Icons.access_time_rounded,
                                    '${_recipe.preparationTime} min',
                                    'Préparation',
                                    const Color(0xFF5C6BC0),
                                  ),
                                  Container(width: 1, height: 40, color: Colors.grey[200]),
                                  _buildModernStatItem(
                                    Icons.local_fire_department_rounded,
                                    '${_recipe.cookingTime} min',
                                    'Cuisson',
                                    const Color(0xFFFFA726),
                                  ),
                                  Container(width: 1, height: 40, color: Colors.grey[200]),
                                  _buildModernStatItem(
                                    Icons.pie_chart_rounded,
                                    '${_recipe.servings}',
                                    'Portions',
                                    const Color(0xFF66BB6A),
                                  ),
                                ],
                              ),
                            ),

                            if (_recipe.addExtraMeal && (widget.showAddExtraMealBadge)) ...[
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.green),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Génère un repas supplémentaire pour le planning",
                                        style: GoogleFonts.poppins(
                                          color: Colors.green[800],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 40),

                            // INGREDIENTS
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Ingrédients',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (_ingredientMultiplier != null && _ingredientMultiplier! > 1) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    '×${_ingredientMultiplier}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurpleAccent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recipe.ingredients.length,
                              itemBuilder: (context, index) {
                                final item = _recipe.ingredients[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurpleAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          item.ingredient.name,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${item.quantity} ${item.unit.label}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 40),

                            // INSTRUCTIONS
                            Text(
                              'Préparation',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recipe.instructions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 20),
                              itemBuilder: (context, index) {
                                final step = _recipe.instructions[index];
                                return _buildInstructionStep(index + 1, step);
                              },
                            ),

                            const SizedBox(height: 40),

                            // USER SERVINGS
                            Text(
                              'Portions par utilisateur',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_isLoadingServings)
                              const Center(child: CircularProgressIndicator())
                            else if (_userServings.isEmpty)
                              Text(
                                'Aucune portion enregistrée',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey, 
                                  fontStyle: FontStyle.italic
                                ),
                              )
                            else 
                              _buildUserServingsList(),
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
        ],
      ),
    );
  }

  Widget _headerCircleButton(IconData icon, VoidCallback? onTap, {Color color = Colors.black87}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Widget _buildModernStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF6A5AE0),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: const Color(0xFF2D2D2D), // Dark grey
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserServingsList() {
    return Column(
      children: _userServings.map((s) {
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
                  s.userName.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6A5AE0),
                    fontSize: 16
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  s.userName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, 
                    fontSize: 15,
                    color: const Color(0xFF2D2D2D)
                  ),
                ),
              ),
              _buildServingBadge(Icons.wb_sunny_rounded, '${s.lunchServings}', Colors.orange),
              const SizedBox(width: 8),
              _buildServingBadge(Icons.nights_stay_rounded, '${s.dinnerServings}', const Color(0xFF5C6BC0)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildServingBadge(IconData icon, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            count,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
