import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/user_recipe_serving.dart';
import '../../domain/entities/category.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../../core/constants/unit.dart';
import '../../core/constants/meal_time.dart';
import '../../core/utils/qty_format.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe_ingredient.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/firebase_user_recipe_serving_repository.dart';
import '../../data/repositories/firebase_category_repository.dart';
import '../../data/repositories/group_repository.dart';
import 'create_recipe_page.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../data/repositories/firebase_stats_repository.dart';


class RecipeDetailPage extends StatefulWidget {
  final String recipeId;
  final Recipe? initialRecipe;
  const RecipeDetailPage({
    super.key,
    required this.recipeId,
    this.initialRecipe,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
    void _onDeleteRecipe() async {
      final confirm = await showModalBottomSheet<bool>(
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
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
              ),
              const SizedBox(height: 16),
              Text('Supprimer la recette',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
              const SizedBox(height: 8),
              Text('Voulez-vous vraiment supprimer cette recette ?',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400], foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                )),
              ]),
            ],
          ),
        ),
      );
      if (confirm == true) {
        await _deleteRecipe();
      }
    }
  Recipe? _recipe;
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

  List<IngredientType> _ingredientTypes = [];
  final FirebaseIngredientTypeRepository _ingredientTypeRepo = FirebaseIngredientTypeRepository();

  bool _wasModified = false;
  int _usageCount = 0;

  @override
  void initState() {
    super.initState();
    _recipe = widget.initialRecipe;
    _loadIngredientTypes();
    _loadFullRecipe();
    if (_recipe != null) {
      _loadUserServings();
      _loadCategories();
    }
    _loadUsageCount();
  }

  Future<void> _loadUsageCount() async {
    try {
      final counts = await FirebaseStatsRepository.instance.getRecipeUsageCounts();
      final id = widget.recipeId;
      if (mounted) setState(() => _usageCount = counts[id] ?? 0);
    } catch (_) {}
  }

  Future<void> _loadIngredientTypes() async {
    try {
      final types = await _ingredientTypeRepo.getTypes();
      if (mounted) setState(() => _ingredientTypes = types);
    } catch (_) {}
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
        }
      }

      if (data == null || !mounted) {
        // Could not load recipe from Firestore
        return;
      }

      // Parse ingredients — use null-safe id extraction to avoid cast errors
      final ingredientsData = (data['ingredients'] as List<dynamic>?) ?? [];

      final ingredientIds = ingredientsData
          .map((i) {
             if (i is Map<String, dynamic>) {
                return (i['ingredientId'] as String?) ?? '';
             }
             return '';
          })
          .where((id) => id.isNotEmpty)
          .toList();

      // Enrich ingredient names + fetch typeIds in parallel (independent queries)
      final namesFuture = ingredientIds.isNotEmpty
          ? IngredientNameCache.instance.fetchNamesForIds(ingredientIds)
          : Future.value(<String, String>{});
      final typeIdFuture = ingredientIds.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('ingredients')
              .where(FieldPath.documentId, whereIn: ingredientIds)
              .get()
          : Future.value(null);

      final names = await namesFuture;
      Map<String, String?> ingredientIdToTypeId = {};
      final typeIdSnap = await typeIdFuture;
      if (typeIdSnap != null) {
        for (final doc in typeIdSnap.docs) {
          final data = doc.data();
          ingredientIdToTypeId[doc.id] = data.containsKey('typeId') ? data['typeId'] as String? : null;
        }
      }

      final enriched = ingredientsData.map((i) {
        if (i is! Map<String, dynamic>) return null;
        final id = (i['ingredientId'] as String?) ?? '';
        // Prend le typeId Firestore si présent, sinon va le chercher dans la collection ingredients
        final typeId = i.containsKey('typeId') && i['typeId'] != null
            ? i['typeId'] as String?
            : ingredientIdToTypeId[id];
        return RecipeIngredient(
          ingredient: Ingredient(
            id: id,
            name: names[id] ?? (i['ingredientName'] as String? ?? ''),
            typeId: typeId,
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
          url: data['url'] as String? ?? currentRecipe?.url,
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
          mealTime: MealTime.fromString(data['mealTime'] as String?),
        );
        // Update displayed category name once the full recipe is loaded
        if (_categories.isNotEmpty && _recipe != null) {
          _currentCategories = _categories.where((c) =>
            _recipe!.categoryIds.contains(c.id) || _recipe!.categoryIds.contains(c.name)
          ).toList();
        }
        });
      
      // Load secondary data if it wasn't loaded before
      _loadUserServings();
      _loadCategories();
      
    } catch (e, stack) {
      // Log the real error so it is visible in the debug console
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
    try {
      final servings = await _userServingRepo.fetchServingsForRecipe(_recipe!.id);
      if (!mounted) return;
      setState(() {
        _userServings = servings;
        _isLoadingServings = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingServings = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (_recipe != null) {
          _currentCategories = _categories.where((c) =>
            _recipe!.categoryIds.contains(c.id) || _recipe!.categoryIds.contains(c.name)
          ).toList();
        }
      });
    } catch (_) {}
  }

  Future<void> _deleteRecipe() async {
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
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final currentRecipe = _recipe!;
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: null,
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
                  colors: [Color(0xFFEFEFFC), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- Custom Header identique à CreateRecipePage ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _headerCircleButton(
                          Icons.arrow_back_ios_new_rounded,
                          () => Navigator.pop(context, _wasModified),
                        ),
                        const SizedBox(width: 40),
                        Row(
                            children: [
                              _headerCircleButton(
                                Icons.edit_rounded,
                                () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CreateRecipePage(recipe: currentRecipe),
                                    ),
                                  );
                                  if (result is Recipe) {
                                    setState(() {
                                      _recipe = result;
                                      _wasModified = true;
                                    });
                                    _loadUserServings();
                                    _loadCategories();
                                  }
                                },
                                color: const Color(0xFF6A5AE0),
                              ),
                              const SizedBox(width: 8),
                              _headerCircleButton(
                                Icons.delete_outline_rounded,
                                _onDeleteRecipe,
                                color: Colors.redAccent,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // --- Fin Custom Header ---
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

                        // URL (if present)
                        if (currentRecipe.url != null && currentRecipe.url!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Center(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(30),
                                onTap: () async {
                                  final url = currentRecipe.url!;
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Impossible d'ouvrir le lien.")),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF3FD),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: const Color(0xFF6A5AE0).withOpacity(0.18)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6A5AE0).withOpacity(0.07),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link_rounded, color: Color(0xFF6A5AE0), size: 20),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          currentRecipe.url!,
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFF2D3A6A),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                            decoration: TextDecoration.none,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
                              Container(width: 1, height: 40, color: Colors.grey[200]),
                              _buildModernStatItem(
                                currentRecipe.mealTime == MealTime.lunchOnly
                                    ? Icons.wb_sunny_rounded
                                    : currentRecipe.mealTime == MealTime.dinnerOnly
                                        ? Icons.nights_stay_rounded
                                        : Icons.sunny_snowing,
                                currentRecipe.mealTime.shortLabel,
                                'Repas',
                                currentRecipe.mealTime == MealTime.lunchOnly
                                    ? Colors.orange.shade700
                                    : currentRecipe.mealTime == MealTime.dinnerOnly
                                        ? const Color(0xFF5C6BC0)
                                        : const Color(0xFF6A5AE0),
                              ),
                            ],
                          ),
                        ),

                        // Usage count
                        if (_usageCount > 0) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF57C00).withOpacity(0.09),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bar_chart_rounded, size: 15, color: Color(0xFFF57C00)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cuisiné $_usageCount fois',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFF57C00),
                                    ),
                                  ),
                                ],
                              ),
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              item.ingredient.name,
                                              style: GoogleFonts.poppins(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (item.ingredient.typeId != null)
                                              Builder(
                                                builder: (context) {
                                                  final type = _ingredientTypes.firstWhere(
                                                    (t) => t.id == item.ingredient.typeId || t.name == item.ingredient.typeId,
                                                    orElse: () => IngredientType(id: '', name: '', color: 0xFF6A5AE0),
                                                  );
                                                  if (type.id.isEmpty) return const SizedBox.shrink();
                                                  final baseColor = Color(type.color);
                                                  final hsl = HSLColor.fromColor(baseColor);
                                                  final startLightness = hsl.lightness;
                                                  final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                                                  final textColor = hsl.withLightness(textLightness).toColor();
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: baseColor.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      type.name,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                        if (item.notes != null && item.notes!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              item.notes!,
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
                                  Text(
                                    '${fmtQty(item.quantity)} ${item.unit.label}',
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


                      ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
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
                  s.userName.isNotEmpty ? s.userName.substring(0, 1).toUpperCase() : '?',
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
              Opacity(
                opacity: _recipe?.mealTime == MealTime.dinnerOnly ? 0.3 : 1.0,
                child: _buildServingBadge(Icons.wb_sunny_rounded, '${s.lunchServings}', Colors.orange),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _recipe?.mealTime == MealTime.lunchOnly ? 0.3 : 1.0,
                child: _buildServingBadge(Icons.nights_stay_rounded, '${s.dinnerServings}', const Color(0xFF5C6BC0)),
              ),
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
