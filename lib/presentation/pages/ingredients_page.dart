import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/ingredient_name_cache.dart';
import 'recipe_detail_page.dart';
import '../../domain/entities/recipe.dart';
import '../../core/constants/unit.dart' show Unit;
import '../../core/constants/meal_time.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe_ingredient.dart';
import 'ingredient_types_page.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../data/repositories/firebase_ingredient_repository.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/firebase_stats_repository.dart';

class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> {
  List<Map<String, dynamic>> _ingredients = [];
  List<IngredientType> _types = [];
  bool _isLoading = true;
  String _filter = '';
  List<String> _selectedTypeIds = [];
  final _typeRepo = FirebaseIngredientTypeRepository();
  final _ingredientRepo = FirebaseIngredientRepository();
  final _shoppingListRepo = FirebaseShoppingListRepository();
  Map<String, int> _ingredientCounts = {};
  String _sortMode = 'alpha'; // 'alpha' | 'usage' | 'unused'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Load types first or parallel
    final typesFuture = _typeRepo.getTypes();
    final ingredientsFuture = _ingredientRepo.getAllIngredients();

    final results = await Future.wait([typesFuture, ingredientsFuture]);
    final typesList = results[0] as List<IngredientType>;
    final ingredientsList = results[1] as List<Map<String, dynamic>>;

    if (!mounted) return;
    setState(() {
      _types = typesList;
      _ingredients = List<Map<String, dynamic>>.from(ingredientsList)
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      _isLoading = false;
    });

    // Compte les recettes du groupe et du catalogue utilisant chaque ingrédient (sans bloquer l’UI)
    _loadGroupCounts();
  }

  Future<void> _loadIngredients() async {
    // Helper to just reload ingredients (and types to be safe)
    await _loadData();
  }

  Future<void> _loadGroupCounts() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('recipes')
        .where('groupId', isEqualTo: groupId)
        .get();
    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ingredients = data['ingredients'] as List<dynamic>? ?? [];
      final seen = <String>{};
      for (final i in ingredients) {
        final iId = i['ingredientId'] as String? ?? '';
        if (iId.isNotEmpty && seen.add(iId)) {
          counts[iId] = (counts[iId] ?? 0) + 1;
        }
      }
    }
    if (mounted) setState(() => _ingredientCounts = counts);
  }

  Future<void> _addIngredient() async {
    final controller = TextEditingController();
    String? selectedTypeId;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Ajouter un ingrédient',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom de l\'ingrédient',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Type',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedTypeId,
                decoration: InputDecoration(
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: [
                   DropdownMenuItem<String>(
                    value: null,
                    child: Text('Aucun type', style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                  ..._types.map((type) {
                  return DropdownMenuItem(
                    value: type.id,
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                              color: Color(type.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(type.name, style: GoogleFonts.poppins()),
                      ],
                    ),
                  );
                })],
                onChanged: (val) => setStateDialog(() => selectedTypeId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler',
                    style: GoogleFonts.poppins(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Ajouter',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0)))),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();

      // Check for duplicate name (case-insensitive)
      final alreadyExists = _ingredients.any(
        (ing) => (ing['name'] as String).toLowerCase() == name.toLowerCase(),
      );
      if (alreadyExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Un ingrédient avec ce nom existe déjà.',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final data = <String, dynamic>{'name': name};
      if (selectedTypeId != null) {
        data['typeId'] = selectedTypeId;
      }

      final gid = await GroupRepository.instance.getCurrentGroupId();
      if (gid != null) data['groupId'] = gid;
      final docRef = await FirebaseFirestore.instance
          .collection('ingredients')
          .add(data);

      IngredientNameCache.instance.setName(docRef.id, name);
      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }

  Future<void> _editIngredient(String id, String oldName, String? oldTypeId) async {
    final controller = TextEditingController(text: oldName);
    String? selectedTypeId = oldTypeId;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Modifier l\'ingrédient',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Type',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _types.any((t) => t.id == selectedTypeId)
                    ? selectedTypeId
                    : null,
                decoration: InputDecoration(
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: [
                   DropdownMenuItem<String>(
                    value: null,
                    child: Text('Aucun type', style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                  ..._types.map((type) {
                    return DropdownMenuItem(
                      value: type.id,
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                                color: Color(type.color), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(type.name, style: GoogleFonts.poppins()),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setStateDialog(() => selectedTypeId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler',
                    style: GoogleFonts.poppins(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Enregistrer',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0)))),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();

      // Check for duplicate name (case-insensitive), excluding the current ingredient
      final alreadyExists = _ingredients.any(
        (ing) =>
            ing['id'] != id &&
            (ing['name'] as String).toLowerCase() == newName.toLowerCase(),
      );
      if (alreadyExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Un ingrédient avec ce nom existe déjà.',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final updates = <String, dynamic>{'name': newName};
      updates['typeId'] = selectedTypeId; // Can be null to remove type

      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .update(updates);

      IngredientNameCache.instance.setName(id, newName);

      // Update all shopping list items with this ingredient's name
      // (Assumes shopping list items use the ingredient name as key)
      await _shoppingListRepo.updateShoppingItemsTypeForIngredient(newName, selectedTypeId);

      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }

  Future<void> _deleteIngredient(String id) async {
    // Vérifie si l'ingrédient est utilisé dans une recette du groupe
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId != null) {
      final recipesSnap = await FirebaseFirestore.instance
          .collection('recipes')
          .where('groupId', isEqualTo: groupId)
          .get();
      final isUsed = recipesSnap.docs.any((doc) {
        final ingredients = (doc.data()['ingredients'] as List<dynamic>? ?? []);
        return ingredients.any((i) => i['ingredientId'] == id);
      });
      if (isUsed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Impossible de supprimer : cet ingrédient est utilisé dans une ou plusieurs recettes du groupe.',
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

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
            Text('Supprimer l\'ingrédient',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous vraiment supprimer cet ingrédient ?',
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
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .delete();

      IngredientNameCache.instance.remove(id);
      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }

  Future<void> _showRecipesForIngredient(String ingredientId, String ingredientName) async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    try {
      final groupSnap = await FirebaseFirestore.instance
          .collection('recipes')
          .where('groupId', isEqualTo: groupId)
          .get();
      docs = groupSnap.docs;
    } catch (_) {
      // Réseau indisponible ou erreur Firestore : on affiche la modale vide
    }
    if (!mounted) return;
    final groupRecipes = <Recipe>[];
    final Map<String, int> groupRecipeCounts = {};
    for (final doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final ingredients = data['ingredients'] as List<dynamic>? ?? [];
        if (ingredients.any((i) => i['ingredientId'] == ingredientId)) {
          final usage = (data['usageCount'] as num?)?.toInt() ?? 0;
          if (usage > 0) groupRecipeCounts[doc.id] = usage;
          final rawIngredients = data['ingredients'] as List<dynamic>? ?? [];
          final mappedIngredients = rawIngredients.map((i) {
            return RecipeIngredient(
              ingredient: Ingredient(id: i['ingredientId'] ?? '', name: '...'),
              quantity: (i['quantity'] as num?)?.toDouble() ?? 0.0,
              unit: Unit.values.firstWhere((u) => u.label == i['unit'], orElse: () => Unit.g),
              notes: i['notes'],
            );
          }).toList();
          groupRecipes.add(Recipe(
            id: doc.id,
            title: data['title'] ?? '',
            description: data['description'] ?? '',
            preparationTime: (data['preparationTime'] as num?)?.toInt() ?? 0,
            cookingTime: (data['cookingTime'] as num?)?.toInt() ?? 0,
            servings: (data['servings'] as num?)?.toInt() ?? 1,
            categoryIds: (data['categoryIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                ((data['category'] as String?)?.isNotEmpty == true ? [data['category'] as String] : []),
            ingredients: mappedIngredients,
            instructions: List<String>.from(data['instructions'] ?? []),
            createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
            isFavorite: data['isFavorite'] ?? false,
            rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
            mealTime: MealTime.fromString(data['mealTime'] as String?),
          ));
        }
      } catch (_) {
        // Données malformées pour cette recette, on l'ignore
      }
    }
    groupRecipes.sort((a, b) => a.title.compareTo(b.title));

    const double headerPx = 130;
    const double itemPx = 62;
    const double minFraction = 0.50;
    const double maxFraction = 0.95;
    final screenH = MediaQuery.of(context).size.height;
    final contentH = headerPx + groupRecipes.length * itemPx + 80;
    final initial = (contentH / screenH).clamp(minFraction, maxFraction);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipesForIngredientSheet(
        ingredientName: ingredientName,
        recipes: groupRecipes,
        recipeCounts: groupRecipeCounts,
        initialChildSize: initial,
        maxChildSize: maxFraction,
      ),
    );
  }

  Future<void> _openFiltersSheet() async {
    String tempSort = _sortMode;
    final tempTypes = Set<String>.from(_selectedTypeIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Filtres ingrédients',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.sort_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Tri',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort_by_alpha_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('A-Z'),
                            ],
                          ),
                          selected: tempSort == 'alpha',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'alpha'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bar_chart_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Plus utilisés'),
                            ],
                          ),
                          selected: tempSort == 'usage',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'usage'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.block_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Jamais utilisés'),
                            ],
                          ),
                          selected: tempSort == 'unused',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'unused'),
                        ),
                      ],
                    ),
                    if (_types.isNotEmpty) ...[const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.label_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Types',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Tous', style: TextStyle(fontWeight: FontWeight.w600)),
                            selected: tempTypes.isEmpty,
                            backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.15),
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(() => tempTypes.clear()),
                          ),
                          for (final type in _types)
                            FilterChip(
                              label: Text(
                                type.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              selected: tempTypes.contains(type.id),
                              backgroundColor: Color(type.color).withOpacity(0.15),
                              selectedColor: Color(type.color).withOpacity(0.35),
                              onSelected: (_) {
                                setStateSheet(() {
                                  if (tempTypes.contains(type.id)) {
                                    tempTypes.remove(type.id);
                                  } else {
                                    tempTypes.add(type.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setStateSheet(() {
                                tempSort = 'alpha';
                                tempTypes.clear();
                              });
                            },
                            child: Text(
                              'Réinitialiser',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _sortMode = tempSort;
                                _selectedTypeIds = tempTypes.toList();
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              'Appliquer',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _activeFiltersCount() {
    int count = 0;
    if (_sortMode != 'alpha') count++;
    if (_selectedTypeIds.isNotEmpty) count++;
    return count;
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
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const IngredientTypesPage()),
                          ).then((_) => _loadIngredients());
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.local_offer_rounded,
                            size: 22,
                            color: Color(0xFF6A5AE0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // BARRE COMPACTE (recherche + filtres)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Filtrer par nom...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                          onChanged: (v) => setState(() => _filter = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openFiltersSheet,
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.tune_rounded, size: 18),
                            if (_activeFiltersCount() > 0)
                              Positioned(
                                right: -7,
                                top: -7,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6A5AE0),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_activeFiltersCount()}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        label: Text(
                          'Filtres',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF6A5AE0)),
                          foregroundColor: const Color(0xFF6A5AE0),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(builder: (_) {
                          var filtered = List<Map<String, dynamic>>.from(
                            _filter.isEmpty
                                ? _ingredients
                                : _ingredients
                                    .where((ing) => (ing['name'] as String)
                                        .toLowerCase()
                                        .contains(_filter.toLowerCase()))
                                    .toList(),
                          );
                          if (_selectedTypeIds.isNotEmpty) {
                            filtered = filtered.where((ing) => ing['typeId'] != null && _selectedTypeIds.contains(ing['typeId'])).toList();
                          }
                          if (_sortMode == 'unused') {
                            filtered = filtered.where((ing) => ((ing['usageCount'] as int?) ?? 0) == 0).toList();
                          }
                          if (_sortMode == 'usage') {
                            filtered.sort((a, b) {
                              final diff = ((b['usageCount'] as int?) ?? 0).compareTo((a['usageCount'] as int?) ?? 0);
                              return diff != 0 ? diff : (a['name'] as String).compareTo(b['name'] as String);
                            });
                          } else {
                            filtered.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
                          }
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
                              final typeId = ing['typeId'] as String?;
                              
                              final type = _types.cast<IngredientType?>().firstWhere(
                                (t) => t?.id == typeId, 
                                orElse: () => null
                              );

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
                                            child: Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 8,
                                              children: [
                                                Text(
                                                  name,
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                    color: const Color(0xFF2D2D2D),
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (type != null)
                                                  Builder(
                                                    builder: (context) {
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
                                                if ((_ingredientCounts[id] ?? 0) > 0)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF26A69A).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.group_rounded, size: 12, color: Color(0xFF26A69A)),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${_ingredientCounts[id]}×',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: const Color(0xFF26A69A),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                if (((ing['usageCount'] as int?) ?? 0) > 0)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF57C00).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.bar_chart_rounded, size: 12, color: Color(0xFFF57C00)),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${ing['usageCount']}×',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: const Color(0xFFF57C00),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () => _editIngredient(id, name, typeId),
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
                                                onTap: () => _deleteIngredient(id),
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
                    'Nouvel ingrédient',
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
  final Map<String, int> recipeCounts;
  final double initialChildSize;
  final double maxChildSize;

  const _RecipesForIngredientSheet({
    required this.ingredientName,
    required this.recipes,
    required this.recipeCounts,
    required this.initialChildSize,
    required this.maxChildSize,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
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
                // Handle
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
                // Contenu scrollable : deux sections
                Expanded(
                  child: recipes.isEmpty
                      ? Center(
                          child: Text(
                            'Aucune recette utilise cet ingrédient.',
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          children: [
                            // ── Section recettes du groupe ──
                            _SectionHeader(
                              icon: Icons.group_rounded,
                              label: 'Recettes du groupe (${recipes.length})',
                            ),
                            const SizedBox(height: 8),
                            if (recipes.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Aucune recette du groupe.',
                                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                                ),
                              )
                            else
                              ...recipes.map((recipe) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _RecipeItem(
                                  title: recipe.title,
                                  usageCount: recipeCounts[recipe.id],
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailPage(
                                        recipeId: recipe.id,
                                        initialRecipe: recipe,
                                      ),
                                    ),
                                  ),
                                ),
                              )),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6A5AE0)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6A5AE0),
          ),
        ),
      ],
    );
  }
}

class _RecipeItem extends StatelessWidget {
  final String title;
  final int? usageCount;
  final VoidCallback? onTap;
  const _RecipeItem({required this.title, this.usageCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: onTap != null ? const Color(0xFFF5F4FF) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  onTap != null ? Icons.restaurant_menu_rounded : Icons.book_rounded,
                  size: 18,
                  color: onTap != null ? const Color(0xFF6A5AE0) : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF2D2D2D),
                    ),
                  ),
                ),
                if ((usageCount ?? 0) > 0) ...
                  [
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF57C00).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bar_chart_rounded, size: 12, color: Color(0xFFF57C00)),
                          const SizedBox(width: 3),
                          Text(
                            '$usageCount×',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFF57C00),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
