import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/entities/category.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../../core/constants/unit.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_category_repository.dart';
import 'create_recipe_page.dart';



class RecipeDetailPage extends StatefulWidget {
  final String recipeId;
  final Recipe? initialRecipe;
  final int? ingredientMultiplier;
  final bool showAddExtraMealBadge;

  const RecipeDetailPage({
    super.key,
    required this.recipeId,
    this.initialRecipe,
    this.ingredientMultiplier,
    this.showAddExtraMealBadge = true,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  Recipe? _recipe;
  int? _ingredientMultiplier;
  bool _isDeleting = false;

  List<UserRecipeServing> _userServings = [];
  bool _isLoadingServings = true;
  final FirebaseUserRecipeServingRepository _userServingRepo =
      FirebaseUserRecipeServingRepository();

  List<Category> _categories = [];
  List<Category> _currentCategories = [];
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();

  bool _isLoadingRecipe = false;
  bool _fullRecipeLoaded = false;

  @override
  void initState() {
    super.initState();
    _recipe = widget.initialRecipe;
    _ingredientMultiplier = widget.ingredientMultiplier;
    
    // Always fetch the full recipe to ensure fresh data and complete details
    _loadFullRecipe();
    
    if (_recipe != null) {
      _loadUserServings();
      _loadCategories();
    }
  }

  Future<void> _loadFullRecipe() async {
    if (!mounted) return;
    setState(() => _isLoadingRecipe = true);
    try {
      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic>? data;
      String? docId;

      // 1. Direct document fetch by ID (most reliable path)
      final directDoc =
          await firestore.collection('recipes').doc(widget.recipeId).get();
      if (directDoc.exists) {
        data = directDoc.data() as Map<String, dynamic>;
        docId = directDoc.id;
      } 
      
      // 2. Fallback: query by stored 'id' field
      if (data == null) {
        final query = await firestore
            .collection('recipes')
            .where('id', isEqualTo: widget.recipeId)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          data = query.docs.first.data() as Map<String, dynamic>;
          docId = query.docs.first.id;
        }
      }

      // 3. Last resort: query by TITLE (exact or capitalized)
      if (data == null && widget.initialRecipe != null) {
        // Try exact title first
        var titleQuery = await firestore
            .collection('recipes')
            .where('title', isEqualTo: widget.initialRecipe!.title)
            .limit(1)
            .get();
        
        // If failed, try capitalizing the first letter (seed data convention)
        if (titleQuery.docs.isEmpty && widget.initialRecipe!.title.isNotEmpty) {
           final t = widget.initialRecipe!.title;
           final capitalized = t[0].toUpperCase() + t.substring(1);
           if (capitalized != t) {
              titleQuery = await firestore
                .collection('recipes')
                .where('title', isEqualTo: capitalized)
                .limit(1)
                .get();
           }
        }

        if (titleQuery.docs.isNotEmpty) {
           data = titleQuery.docs.first.data() as Map<String, dynamic>;
           docId = titleQuery.docs.first.id; // Override ID with the new one
           debugPrint('RecipeDetailPage: Found recipe by title overlap: ${data!['title']}');
        }
      }

      if (data == null || !mounted) {
        // Could not load recipe from Firestore
        debugPrint('RecipeDetailPage: Recipe document not found. Using partial data.');
        return;
      }

      // Parse ingredients — use null-safe id extraction to avoid cast errors
      final ingredientsData = (data['ingredients'] as List<dynamic>?) ?? [];
      debugPrint('RecipeDetailPage: Found ${ingredientsData.length} ingredients in Firestore');

      final ingredientIds = ingredientsData
          .map((i) {
             if (i is Map<String, dynamic>) {
                return (i['ingredientId'] as String?) ?? '';
             }
             return '';
          })
          .where((id) => id.isNotEmpty)
          .toList();

      // Enrich ingredient names via cache
      final names = ingredientIds.isNotEmpty
          ? await IngredientNameCache.instance.fetchNamesForIds(ingredientIds)
          : <String, String>{};

      final enriched = ingredientsData.map((i) {
        if (i is! Map<String, dynamic>) return null;
        
        final id = (i['ingredientId'] as String?) ?? '';
        return RecipeIngredient(
          ingredient: Ingredient(
            id: id,
            name: names[id] ?? (i['ingredientName'] as String? ?? ''),
          ),
          quantity: (i['quantity'] as num?)?.toDouble() ?? 0,
          unit: Unit.values.firstWhere(
            (u) => u.label == i['unit'] || u.name == i['unit'],
            orElse: () => Unit.g,
          ),
          notes: i['notes'] as String?,
        );
      }).whereType<RecipeIngredient>().toList();

      if (!mounted) return;
      
      final currentRecipe = _recipe;
      
      setState(() {
        _fullRecipeLoaded = true;
        _recipe = Recipe(
          // Preserve the original id used to find the recipe so that
          // subsequent saves / fetches keep working correctly.
          id: docId ?? widget.recipeId,
          title: data!['title'] as String? ?? currentRecipe?.title ?? '',
          description: data['description'] as String? ?? currentRecipe?.description ?? '',
          preparationTime:
              (data['preparationTime'] as num?)?.toInt() ??
              currentRecipe?.preparationTime ?? 0,
          cookingTime:
              (data['cookingTime'] as num?)?.toInt() ?? currentRecipe?.cookingTime ?? 0,
          servings:
              (data['servings'] as num?)?.toInt() ?? currentRecipe?.servings ?? 1,
          categoryIds: (data['categoryIds'] != null ? List<String>.from(data['categoryIds']) : (data['category'] != null ? [data['category'] as String] : [])),
          ingredients: enriched,
          instructions: List<String>.from(data['instructions'] ?? []),
          createdAt:
              DateTime.tryParse(data['createdAt'] as String? ?? '') ??
              currentRecipe?.createdAt ?? DateTime.now(),
          isFavorite: data['isFavorite'] as bool? ?? currentRecipe?.isFavorite ?? false,
          rating:
              (data['rating'] as num?)?.toDouble() ?? currentRecipe?.rating ?? 0.0,
          addExtraMeal:
              data['addExtraMeal'] as bool? ?? currentRecipe?.addExtraMeal ?? false,
        );
        // Update displayed category name once the full recipe is loaded
        if (_categories.isNotEmpty && _recipe != null) {
          _currentCategories = _categories.where((c) => _recipe!.categoryIds.contains(c.id)).toList();
        }
      });
      
      // Load secondary data if it wasn't loaded before
      _loadUserServings();
      _loadCategories();
      
    } catch (e, stack) {
      // Log the real error so it is visible in the debug console
      debugPrint('RecipeDetailPage._loadFullRecipe error: $e');
      debugPrint('$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Impossible de charger les détails : $e', 
                    style: GoogleFonts.poppins(color: Colors.white)
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            elevation: 4,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRecipe = false);
    }
  }

  Future<void> _loadUserServings() async {
    if (_recipe == null || _recipe!.id.isEmpty) return;
    final servings = await _userServingRepo.fetchServingsForRecipe(_recipe!.id);
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
      if (_recipe != null) {
        _currentCategories = _categories.where((c) => _recipe!.categoryIds.contains(c.id)).toList();
      }
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

    if (_recipe != null) {
      setState(() => _isDeleting = true);
      await FirebaseRecipeRepository().deleteRecipe(_recipe!.id);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_recipe == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final currentRecipe = _recipe!;

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
                                                CreateRecipePage(recipe: currentRecipe),
                                          ),
                                        );

                                    if (updatedRecipe != null && mounted) {
                                      setState(() => _recipe = updatedRecipe);
                                      _loadUserServings();
                                      _loadCategories();
                                      
                                      // Force reload of full recipe to get standardized data 
                                      // and ensure any title/instruction updates are fully reflected locally
                                       _isLoadingRecipe = true;
                                       _loadFullRecipe();
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
                              child: _currentCategories.isEmpty 
                                  ? const SizedBox.shrink()
                                  : Wrap(
                                      spacing: 8.0,
                                      runSpacing: 4.0,
                                      alignment: WrapAlignment.center,
                                      children: _currentCategories.map((category) {
                                        final colorVal = category.color;
                                        final baseColor = Color(colorVal);
                                        final name = category.name;

                                        final hsl = HSLColor.fromColor(baseColor);
                                        final startLightness = hsl.lightness;
                                        final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                                        final textColor = hsl.withLightness(textLightness).toColor();

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: baseColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            name.toUpperCase(),
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: textColor,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),

                            const SizedBox(height: 16),

                            /// TITLE
                            Text(
                              currentRecipe.title,
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
                              currentRecipe.description,
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
                                    '${currentRecipe.preparationTime} min',
                                    'Préparation',
                                    const Color(0xFF5C6BC0),
                                  ),
                                  Container(width: 1, height: 40, color: Colors.grey[200]),
                                  _buildModernStatItem(
                                    Icons.local_fire_department_rounded,
                                    '${currentRecipe.cookingTime} min',
                                    'Cuisson',
                                    const Color(0xFFFFA726),
                                  ),
                                  Container(width: 1, height: 40, color: Colors.grey[200]),
                                  _buildModernStatItem(
                                    Icons.pie_chart_rounded,
                                    '${currentRecipe.servings}',
                                    'Portions',
                                    const Color(0xFF66BB6A),
                                  ),
                                ],
                              ),
                            ),

                            if (currentRecipe.addExtraMeal && (widget.showAddExtraMealBadge)) ...[
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
                            if (_isLoadingRecipe && _recipe!.ingredients.isEmpty)
                              const Center(child: CircularProgressIndicator())
                            else if (_recipe!.ingredients.isEmpty)
                               Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  "Aucun ingrédient trouvé",
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic
                                  ),
                                ),
                              )
                            else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: currentRecipe.ingredients.length,
                              itemBuilder: (context, index) {
                                final item = currentRecipe.ingredients[index];
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
                            if (_isLoadingRecipe)
                              const SizedBox.shrink()
                            else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: currentRecipe.instructions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 20),
                              itemBuilder: (context, index) {
                                final step = currentRecipe.instructions[index];
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
