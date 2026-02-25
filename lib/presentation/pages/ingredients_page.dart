import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/ingredient_name_cache.dart';
import 'recipe_detail_page.dart';
import '../../domain/entities/recipe.dart';
import '../../core/constants/unit.dart' show Unit;
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe_ingredient.dart';

class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> {
  List<Map<String, dynamic>> _ingredients = [];
  bool _isLoading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    final snap = await FirebaseFirestore.instance
        .collection('ingredients')
        .orderBy('name')
        .get();

    if (!mounted) return;
    setState(() {
      _ingredients = snap.docs
          .map((doc) => {
                'id': doc.id,
                'name': doc.get('name'),
              })
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _addIngredient() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ajouter un ingrédient'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(labelText: 'Nom de l\'ingrédient'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      final docRef = await FirebaseFirestore.instance
          .collection('ingredients')
          .add({'name': name});

      IngredientNameCache.instance.setName(docRef.id, name);
      _loadIngredients();
    }
  }

  Future<void> _editIngredientName(String id, String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier l\'ingrédient'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .update({'name': newName});

      IngredientNameCache.instance.setName(id, newName);
      _loadIngredients();
    }
  }

  Future<void> _deleteIngredient(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'ingrédient'),
        content:
            const Text('Voulez-vous vraiment supprimer cet ingrédient ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .delete();

      IngredientNameCache.instance.remove(id);
      _loadIngredients();
    }
  }

  Future<void> _showRecipesForIngredient(String ingredientId, String ingredientName) async {
    // Pre-load so we can size the sheet to fit the content
    final snap = await FirebaseFirestore.instance.collection('recipes').get();
    if (!mounted) return;

    // Use full Recipe objects instead of just strings
    final recipes = <Recipe>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final ingredients = data['ingredients'] as List<dynamic>? ?? [];
      
      if (ingredients.any((i) => i['ingredientId'] == ingredientId)) {
        // Construct minimal Recipe object for list display, or full parsing if needed soon
        // Let's parse fully so we can pass it to Detail Page
        final ingredientList = <RecipeIngredient>[]; // We can skip detailed ingredient parsing for now or do it lazy
        // To be safe and reuse Detail Page logic, let's parse minimally but enough for ID/Title
        // OR better: parse properly so DetailPage works.

        // Re-using fetch logic locally or parsing manually:
        final rawIngredients = data['ingredients'] as List<dynamic>? ?? [];
        // Map raw ingredients to RecipeIngredient... (simplified since we might not have names cached for ALL ingredients here)
        // Ideally we should use a Repository, but here is inline for quick fix:
        final mappedIngredients = rawIngredients.map((i) {
             return RecipeIngredient(
                ingredient: Ingredient(id: i['ingredientId'], name: '...'), // Placeholder name
                quantity: (i['quantity'] as num).toDouble(),
                unit: Unit.values.firstWhere((u) => u.label == i['unit'], orElse: () => Unit.g),
                notes: i['notes'],
             ); 
        }).toList();

        final r = Recipe(
          id: doc.id,
          title: data['title'] ?? '',
          description: data['description'] ?? '',
          preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
          cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
          servings: (data['servings'] as num?)?.toInt() ?? 1,
          categoryIds: (data['categoryIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              ((data['category'] as String?)?.isNotEmpty == true
                  ? [data['category'] as String]
                  : []),
          ingredients: mappedIngredients,
          instructions: List<String>.from(data['instructions'] ?? []),
          createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
          isFavorite: data['isFavorite'] ?? false,
          rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
          addExtraMeal: data['addExtraMeal'] ?? false,
        );
        recipes.add(r);
      }
    }
    recipes.sort((a, b) => a.title.compareTo(b.title));

    // Compute a snug initial height: header ≈ 130 px, each item ≈ 62 px
    const double headerPx = 130;
    const double itemPx = 62;
    const double minFraction = 0.50;
    const double maxFraction = 0.95;
    final screenH = MediaQuery.of(context).size.height;
    final contentH = headerPx + recipes.length * itemPx + 24;
    final initial = (contentH / screenH).clamp(minFraction, maxFraction);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipesForIngredientSheet(
        ingredientName: ingredientName,
        recipes: recipes,
        initialChildSize: initial,
        maxChildSize: maxFraction,
      ),
    );
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
                  colors: [Color(0xFFEFEFFC), Colors.white], // Very subtle purple fading to white
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    children: [
                      Text(
                        'Ingrédients',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search field
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Filtrer par nom...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(builder: (_) {
                          final filtered = _filter.isEmpty
                              ? _ingredients
                              : _ingredients
                                  .where((ing) => (ing['name'] as String)
                                      .toLowerCase()
                                      .contains(_filter.toLowerCase()))
                                  .toList();

                          if (filtered.isEmpty) {
                            return Center(
                              child: Text(
                                'Aucun ingrédient trouvé',
                                style: GoogleFonts.poppins(color: Colors.grey),
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (_, index) {
                              final ing = filtered[index];
                              final name = ing['name'] as String;
                              final id = ing['id'] as String;

                              return Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.06),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    onTap: () => _showRecipesForIngredient(id, name),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                color: const Color(0xFF2D2D2D),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent),
                                            onPressed: () => _editIngredientName(id, name),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                            onPressed: () => _deleteIngredient(id),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                ),
              ],
            ),
          ),
        ],
      ),

      // FAB
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: Colors.transparent, // Fix for square background
          child: InkWell(
            onTap: _addIngredient,
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
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Ajouter',
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
    );
  }
}

// =====================================================
// Bottom sheet : recettes pour un ingrédient
// =====================================================
class _RecipesForIngredientSheet extends StatelessWidget {
  final String ingredientName;
  final List<Recipe> recipes;
  final double initialChildSize;
  final double maxChildSize;

  const _RecipesForIngredientSheet({
    required this.ingredientName,
    required this.recipes,
    required this.initialChildSize,
    required this.maxChildSize,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Zone transparente au-dessus : tap pour fermer
        GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: 0.3,
      maxChildSize: maxChildSize,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle (tap to close)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
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
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Recettes avec "$ingredientName"',
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
            const SizedBox(height: 12),
            const Divider(height: 1),
            // List
            Expanded(
              child: recipes.isEmpty
                      ? Center(
                          child: Text(
                            'Aucune recette utilise cet ingrédient.',
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          itemCount: recipes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, index) => Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F4FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => RecipeDetailPage(
                                      recipeId: recipes[index].id, 
                                      initialRecipe: recipes[index]
                                    )),
                                  );
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.restaurant_menu_rounded,
                                          size: 18, color: Color(0xFF6A5AE0)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          recipes[index].title,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF2D2D2D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
        ), // DraggableScrollableSheet
      ], // Stack children
    ); // Stack
  }
}
