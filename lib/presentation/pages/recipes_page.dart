import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/recipe.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../widgets/ingredient_autocomplete.dart' show IngredientAutocomplete;

import 'recipe_detail_page.dart';
import 'categories_page.dart';
import 'create_recipe_page.dart';
import '../../data/repositories/firebase_recipe_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/firebase_stats_repository.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
    String _titleFilter = '';
    Set<String> _selectedIngredientIds = {};
    List<Map<String, String>> _allIngredients = [];
    bool _ingredientsLoading = true;
    
    // Category filter state
    Set<String> _selectedCategoryIds = {};
    List<Map<String, dynamic>> _allCategories = [];
    bool _categoriesLoading = true;

  // Catalog mode
  bool _showCatalog = false;
  List<Map<String, dynamic>> _catalogRecipes = [];
  bool _catalogLoading = false;
  List<Map<String, String>> _catalogGroups = [];
  Set<String> _selectedCatalogGroupIds = {};
  Set<String> _groupRecipeTitles = {};
  String _catalogImportFilter = 'notImported'; // 'all', 'imported', 'notImported'
  String _catalogSortMode = 'alpha'; // 'alpha' | 'rating'

  Map<String, int> _recipeCounts = {};
  String _sortMode = 'alpha'; // 'alpha' | 'usage' | 'unused' | 'rating'

  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = fetchRecipes().then((recipes) {
      if (mounted) setState(() => _groupRecipeTitles = recipes.map((r) => r.title.toLowerCase().trim()).toSet());
      return recipes;
    });

    // Fetch all ingredients for filter
    _fetchAllIngredients();
    // Fetch all categories for filter
    _fetchCategories();
    // Fetch catalog recipes from visible groups
    _fetchCatalogRecipes();
    // Load recipe usage stats from history
    _loadRecipeCounts();
  }
  
  Future<void> _fetchCategories() async {
    setState(() => _categoriesLoading = true);
    try {
      final groupId = await GroupRepository.instance.getCurrentGroupId();
      if (groupId == null) {
        if (mounted) setState(() => _categoriesLoading = false);
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('groupId', isEqualTo: groupId)
          .get();
      if (!mounted) return;
      setState(() {
        _allCategories = snap.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'name': data['name'] as String,
            'color': data.containsKey('color') ? data['color'] as int : 0xFF6A5AE0,
          };
        }).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  Future<void> _fetchAllIngredients() async {
    setState(() => _ingredientsLoading = true);
    try {
      final groupId = await GroupRepository.instance.getCurrentGroupId();
      if (groupId == null) {
        if (mounted) setState(() => _ingredientsLoading = false);
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('ingredients')
          .where('groupId', isEqualTo: groupId)
          .get();
      if (!mounted) return;
      setState(() {
        _allIngredients = snap.docs.map((doc) => {
          'id': doc.id,
          'name': doc.get('name') as String,
        }).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _ingredientsLoading = false);
    }
  }

  // =========================
  // FETCH RECIPES
  // =========================
  Future<List<Recipe>> fetchRecipes() async {
    final recipes = await FirebaseRecipeRepository().fetchAllRecipes();

    // Resolve ingredient names (cached — only fetches missing ids from Firestore)
    final allIds = recipes
        .expand((r) => r.ingredients.map((ri) => ri.ingredient.id))
        .toList();
    final names = await IngredientNameCache.instance.fetchNamesForIds(allIds);

    final enriched = recipes.map((recipe) {
      final updatedIngredients = recipe.ingredients.map((ri) {
        return ri.copyWith(
          ingredient: ri.ingredient.copyWith(
            name: names[ri.ingredient.id] ?? 'Unknown',
          ),
        );
      }).toList();
      return recipe.copyWith(ingredients: updatedIngredients);
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return enriched;
  }

  Future<void> _loadRecipeCounts() async {
    final counts = await FirebaseStatsRepository.instance
        .getRecipeUsageCounts();
    if (mounted) setState(() => _recipeCounts = counts);
  }

  // =========================
  // REFRESH (FIXED)
  // =========================
  void _refreshRecipes() {
    if (!mounted) return;
    setState(() {
      _recipesFuture = fetchRecipes().then((recipes) {
        if (mounted) setState(() => _groupRecipeTitles = recipes.map((r) => r.title.toLowerCase().trim()).toSet());
        return recipes;
      });
    });
  }

  int _catalogActiveFiltersCount() {
    int count = 0;
    if (_catalogImportFilter != 'all') count++;
    if (_catalogSortMode != 'alpha') count++;
    if (_selectedCatalogGroupIds.isNotEmpty) count++;
    return count;
  }

  int _groupActiveFiltersCount() {
    int count = 0;
    if (_sortMode != 'alpha') count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    return count;
  }

  Future<void> _openGroupFiltersSheet() async {
    String tempSort = _sortMode;
    final tempCategories = Set<String>.from(_selectedCategoryIds);
    final tempIngredients = Set<String>.from(_selectedIngredientIds);

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
                      'Filtres recettes',
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
                              const Icon(Icons.star_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Mieux notées'),
                            ],
                          ),
                          selected: tempSort == 'rating',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'rating'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.local_dining_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Plus cuisinées'),
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
                              const Text('Jamais cuisinées'),
                            ],
                          ),
                          selected: tempSort == 'unused',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'unused'),
                        ),
                      ],
                    ),
                    if (_allCategories.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.label_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Catégories',
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
                            label: const Text('Toutes', style: TextStyle(fontWeight: FontWeight.w600)),
                            selected: tempCategories.isEmpty,
                            backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.15),
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(() => tempCategories.clear()),
                          ),
                          for (final category in _allCategories)
                            FilterChip(
                              label: Text(
                                category['name'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              selected: tempCategories.contains(category['id']),
                              backgroundColor: Color(category['color'] as int? ?? 0xFF6A5AE0).withOpacity(0.15),
                              selectedColor: Color(category['color'] as int? ?? 0xFF6A5AE0).withOpacity(0.35),
                              onSelected: (_) {
                                final id = category['id'] as String?;
                                if (id == null || id.isEmpty) return;
                                setStateSheet(() {
                                  if (tempCategories.contains(id)) {
                                    tempCategories.remove(id);
                                  } else {
                                    tempCategories.add(id);
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
                                tempCategories.clear();
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
                                _selectedCategoryIds = tempCategories;
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

  Future<void> _openCatalogFiltersSheet() async {
    String tempImport = _catalogImportFilter;
    String tempSort = _catalogSortMode;
    final tempGroups = Set<String>.from(_selectedCatalogGroupIds);

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
                      'Filtres catalogue',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.download_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Import',
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
                        for (final entry in const [
                          {'value': 'all', 'label': 'Toutes', 'icon': Icons.all_inclusive_rounded},
                          {'value': 'notImported', 'label': 'Non importées', 'icon': Icons.download_rounded},
                          {'value': 'imported', 'label': 'Importées', 'icon': Icons.check_circle_rounded},
                        ])
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(entry['icon'] as IconData, size: 18),
                                const SizedBox(width: 6),
                                Text(entry['label'] as String),
                              ],
                            ),
                            selected: tempImport == entry['value'] as String,
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(
                              () => tempImport = entry['value'] as String,
                            ),
                          ),
                      ],
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
                              const Icon(Icons.star_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Mieux notées'),
                            ],
                          ),
                          selected: tempSort == 'rating',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'rating'),
                        ),
                      ],
                    ),
                    if (_catalogGroups.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.group_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Groupes visibles',
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
                            label: const Text('Tous les groupes'),
                            selected: tempGroups.isEmpty,
                            onSelected: (_) => setStateSheet(() => tempGroups.clear()),
                          ),
                          for (final group in _catalogGroups)
                            FilterChip(
                              label: Text(group['name'] ?? ''),
                              selected: tempGroups.contains(group['id']),
                              onSelected: (_) {
                                final id = group['id'];
                                if (id == null) return;
                                setStateSheet(() {
                                  if (tempGroups.contains(id)) {
                                    tempGroups.remove(id);
                                  } else {
                                    tempGroups.add(id);
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
                                tempImport = 'all';
                                tempSort = 'alpha';
                                tempGroups.clear();
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
                                _catalogImportFilter = tempImport;
                                _catalogSortMode = tempSort;
                                _selectedCatalogGroupIds = tempGroups;
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

  Future<void> _fetchCatalogRecipes() async {
    setState(() => _catalogLoading = true);
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    final visibleGroupIds = List<String>.from(
      (groupDoc.data() as Map<String, dynamic>)['visibleGroupIds'] ?? [],
    );
    if (visibleGroupIds.isEmpty) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    // Fetch group names and recipes in parallel
    final groupNameFutures = visibleGroupIds.map(
      (gid) => FirebaseFirestore.instance.collection('groups').doc(gid).get(),
    );
    final recipesFuture = FirebaseFirestore.instance
        .collection('recipes')
        .where('groupId', whereIn: visibleGroupIds)
        .get();
    final results = await Future.wait([Future.wait(groupNameFutures), recipesFuture]);
    if (!mounted) return;
    final groupSnaps = (results[0] as List).cast<DocumentSnapshot>();
    final groupNames = <String, String>{};
    for (final snap in groupSnaps) {
      if (snap.exists) {
        groupNames[snap.id] = (snap.data() as Map<String, dynamic>)['name'] as String? ?? snap.id;
      }
    }
    final availableGroups = groupNames.entries
        .map((e) => <String, String>{'id': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    final recipesSnap = results[1] as QuerySnapshot;
    final recipes = recipesSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      data['_id'] = doc.id;
      data['_groupName'] = groupNames[data['groupId'] as String? ?? ''] ?? '';
      return data;
    }).toList()
      ..sort((a, b) => (a['title'] as String? ?? '').compareTo(b['title'] as String? ?? ''));
    setState(() {
      _catalogRecipes = recipes;
      _catalogGroups = availableGroups;
      _selectedCatalogGroupIds.removeWhere(
        (id) => !availableGroups.any((g) => g['id'] == id),
      );
      _catalogLoading = false;
    });
  }

  // =========================
  // NAVIGATION
  // =========================
  Future<void> _openRecipeDetail(Recipe recipe) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: recipe.id,
          initialRecipe: recipe,
        ),
      ),
    );

    // Only refresh if something was modified or deleted
    if (result == true) {
      _refreshRecipes();
    }
  }

  Future<void> _openCategoriesPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesPage()),
    );
    // Refresh categories after managing them
    _fetchCategories();
  }

  Future<void> _createNewRecipe() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRecipePage()),
    );

    if (result != null) {
      _refreshRecipes();
    }
  }

  // =========================
  // UI
  // =========================
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
                  colors: [Color(0xFFEFEFFC), Colors.white],
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
                // HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recettes',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      InkWell(
                        onTap: _openCategoriesPage,
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
                
                // TOGGLE GROUPE / CATALOGUE
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                  child: Row(
                    children: [
                      _buildToggleButton(Icons.group_rounded, 'Groupe', !_showCatalog,
                          () => setState(() => _showCatalog = false)),
                      const SizedBox(width: 8),
                      _buildToggleButton(Icons.menu_book_rounded, 'Catalogue', _showCatalog,
                          () => setState(() => _showCatalog = true)),
                    ],
                  ),
                ),

                // BARRE COMPACTE CATALOGUE (recherche + filtres)
                if (_showCatalog)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Rechercher dans le catalogue...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            ),
                            onChanged: (value) => setState(() => _titleFilter = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openCatalogFiltersSheet,
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.tune_rounded, size: 18),
                              if (_catalogActiveFiltersCount() > 0)
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
                                      '${_catalogActiveFiltersCount()}',
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

                // BARRE COMPACTE GROUPE (recherche + filtres)
                if (!_showCatalog)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Filtrer par titre...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            ),
                            onChanged: (value) => setState(() => _titleFilter = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openGroupFiltersSheet,
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.tune_rounded, size: 18),
                              if (_groupActiveFiltersCount() > 0)
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
                                      '${_groupActiveFiltersCount()}',
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

                // AUTOCOMPLETE INGRÉDIENTS (groupe seulement)
                if (!_showCatalog && _ingredientsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: LinearProgressIndicator(),
                  )
                else if (!_showCatalog) ...[  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: IngredientAutocomplete(
                      selectedIngredientIds: _selectedIngredientIds,
                      onIngredientSelected: (ingredient) {
                        setState(() {
                          _selectedIngredientIds.add(ingredient['id']!);
                        });
                      },
                      controller: TextEditingController(),
                    ),
                  ),
                  if (_selectedIngredientIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _allIngredients
                              .where((ing) => _selectedIngredientIds.contains(ing['id']))
                              .map((ingredient) => Chip(
                                    label: Text(ingredient['name'] ?? ''),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedIngredientIds.remove(ingredient['id']!);
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                ],
                if (_showCatalog)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      'Recettes (${_filteredCatalogRecipes().length})',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  )
                else
                FutureBuilder<List<Recipe>>(
                  future: _recipesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    final recipes = snapshot.data ?? [];
                    var filteredRecipes = recipes.where((recipe) {
                      final matchesTitle = _titleFilter.isEmpty || recipe.title.toLowerCase().contains(_titleFilter.toLowerCase());
                      final matchesIngredients = _selectedIngredientIds.isEmpty || recipe.ingredients.any((ri) => _selectedIngredientIds.contains(ri.ingredient.id));
                      final matchesCategory = _selectedCategoryIds.isEmpty || recipe.categoryIds.any((cId) => _selectedCategoryIds.contains(cId));
                      final matchesUsage = _sortMode != 'unused' || (_recipeCounts[recipe.id] ?? 0) == 0;
                      return matchesTitle && matchesIngredients && matchesCategory && matchesUsage;
                    }).toList();
                    if (_sortMode == 'usage') {
                      filteredRecipes.sort((a, b) {
                        final diff = (_recipeCounts[b.id] ?? 0).compareTo(_recipeCounts[a.id] ?? 0);
                        return diff != 0 ? diff : a.title.compareTo(b.title);
                      });
                    } else if (_sortMode == 'rating') {
                      filteredRecipes.sort((a, b) {
                        final diff = b.rating.compareTo(a.rating);
                        return diff != 0 ? diff : a.title.compareTo(b.title);
                      });
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        'Recettes (${filteredRecipes.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  },
                ),

                // LISTE
                if (_showCatalog)
                  _buildCatalogListView()
                else
                Expanded(
                  child: FutureBuilder<List<Recipe>>(
                    future: _recipesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final recipes = snapshot.data ?? [];

                      // Filtrage par titre, ingrédients et statistiques
                      var filteredRecipes = recipes.where((recipe) {
                        final matchesTitle = _titleFilter.isEmpty || recipe.title.toLowerCase().contains(_titleFilter.toLowerCase());
                        final matchesIngredients = _selectedIngredientIds.isEmpty || recipe.ingredients.any((ri) => _selectedIngredientIds.contains(ri.ingredient.id));
                        final matchesCategory = _selectedCategoryIds.isEmpty || recipe.categoryIds.any((cId) => _selectedCategoryIds.contains(cId));
                        final matchesUsage = _sortMode != 'unused' || (_recipeCounts[recipe.id] ?? 0) == 0;
                        return matchesTitle && matchesIngredients && matchesCategory && matchesUsage;
                      }).toList();
                      if (_sortMode == 'usage') {
                        filteredRecipes.sort((a, b) {
                          final diff = (_recipeCounts[b.id] ?? 0).compareTo(_recipeCounts[a.id] ?? 0);
                          return diff != 0 ? diff : a.title.compareTo(b.title);
                        });
                      } else if (_sortMode == 'rating') {
                        filteredRecipes.sort((a, b) {
                          final diff = b.rating.compareTo(a.rating);
                          return diff != 0 ? diff : a.title.compareTo(b.title);
                        });
                      }

                      if (filteredRecipes.isEmpty) {
                        return const Center(
                          child: Text('Aucune recette disponible'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemCount: filteredRecipes.length,
                        itemBuilder: (_, index) {
                          final recipe = filteredRecipes[index];

                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => _openRecipeDetail(recipe),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  recipe.title,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF1A1A1A),
                                                  ),
                                                ),
                                                ...recipe.categoryIds.map((id) {
                                                  // Find category safely
                                                  final catMap = _allCategories.firstWhere(
                                                    (c) => c['id'] == id,
                                                    orElse: () => <String, dynamic>{}, // Fallback empty map
                                                  );

                                                  // If not found or invalid
                                                  if (catMap.isEmpty || !catMap.containsKey('name')) {
                                                    return const SizedBox.shrink(); 
                                                  }

                                                  final name = catMap['name'] as String;
                                                  final colorVal = catMap['color'] as int? ?? 0xFF6A5AE0;
                                                  final baseColor = Color(colorVal);

                                                  // Contrast logic
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
                                                      name,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                if (recipe.isFavorite)
                                                  const Icon(
                                                    Icons.favorite_rounded,
                                                    size: 22,
                                                    color: Colors.redAccent,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              recipe.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                color: Colors.grey[600],
                                                fontSize: 14,
                                                height: 1.5,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            // Footer stats
                                            Row(
                                              children: [
                                                _buildStatItem(
                                                  Icons.access_time_rounded,
                                                  '${recipe.preparationTime + recipe.cookingTime} min',
                                                  const Color(0xFF5C6BC0),
                                                ),
                                                const SizedBox(width: 24),
                                                _buildStatItem(
                                                  Icons.pie_chart_rounded,
                                                  '${recipe.servings} portions',
                                                  const Color(0xFFFF8A65),
                                                ),
                                                if ((_recipeCounts[recipe.id] ?? 0) > 0) ...[
                                                  const SizedBox(width: 12),
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
                                                          '${_recipeCounts[recipe.id]}×',
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
                                                if (recipe.rating > 0) ...[
                                                  const SizedBox(width: 12),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFFA726).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA726)),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${recipe.rating.toInt()}/5',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: const Color(0xFFFFA726),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 18,
                                        color: Colors.black26,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // FAB
      floatingActionButton: _showCatalog ? null : Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: Colors.transparent, // Fix for square background
          child: InkWell(
            onTap: _createNewRecipe,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                  const Icon(Icons.add, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Nouvelle recette',
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

  List<Map<String, dynamic>> _filteredCatalogRecipes() {
    final filtered = _catalogRecipes.where((recipe) {
      final title = recipe['title'] as String? ?? '';
      final recipeGroupId = recipe['groupId'] as String? ?? '';
      final matchesTitle = _titleFilter.isEmpty ||
          title.toLowerCase().contains(_titleFilter.toLowerCase());
      final matchesGroup = _selectedCatalogGroupIds.isEmpty ||
          _selectedCatalogGroupIds.contains(recipeGroupId);
      final isImported = _groupRecipeTitles.contains(title.toLowerCase().trim());
      final matchesImportFilter = _catalogImportFilter == 'all' ||
          (_catalogImportFilter == 'imported' && isImported) ||
          (_catalogImportFilter == 'notImported' && !isImported);
      return matchesTitle && matchesGroup && matchesImportFilter;
    }).toList();

    if (_catalogSortMode == 'rating') {
      filtered.sort((a, b) {
        final aRating = (a['rating'] as num?)?.toDouble() ?? 0.0;
        final bRating = (b['rating'] as num?)?.toDouble() ?? 0.0;
        final diff = bRating.compareTo(aRating);
        if (diff != 0) return diff;
        final aTitle = a['title'] as String? ?? '';
        final bTitle = b['title'] as String? ?? '';
        return aTitle.compareTo(bTitle);
      });
    }

    return filtered;
  }

  Future<void> _openCatalogRecipeDetail(Map<String, dynamic> data) async {
    final recipeId = data['_id'] as String? ?? '';
    final groupName = data['_groupName'] as String? ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: recipeId,
          isCatalogRecipe: true,
          sourceGroupName: groupName,
        ),
      ),
    );
    _refreshRecipes();
    _fetchCatalogRecipes();
  }

  Widget _buildCatalogListView() {
    if (_catalogLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    final filtered = _filteredCatalogRecipes();
    if (filtered.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                _catalogRecipes.isEmpty
                    ? 'Aucun groupe partagé avec vous.'
                    : 'Aucune recette disponible',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemCount: filtered.length,
        itemBuilder: (_, index) {
          final recipe = filtered[index];
          final prepTime = (recipe['preparationTime'] as num?)?.toInt() ?? 0;
          final cookTime = (recipe['cookingTime'] as num?)?.toInt() ?? 0;
          final servings = (recipe['servings'] as num?)?.toInt() ?? 1;
          final title = recipe['title'] as String? ?? '';
          final groupName = recipe['_groupName'] as String? ?? '';
          final rating = (recipe['rating'] as num?)?.toDouble() ?? 0.0;
          final isImported = _groupRecipeTitles.contains(title.toLowerCase().trim());
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openCatalogRecipeDetail(recipe),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                // Source group badge
                                if (groupName.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5C6BC0).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.group_rounded, size: 12, color: Color(0xFF5C6BC0)),
                                        const SizedBox(width: 4),
                                        Text(
                                          groupName,
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF5C6BC0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isImported)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Dans le groupe',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              recipe['description'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _buildStatItem(
                                  Icons.access_time_rounded,
                                  '${prepTime + cookTime} min',
                                  const Color(0xFF5C6BC0),
                                ),
                                const SizedBox(width: 24),
                                _buildStatItem(
                                  Icons.pie_chart_rounded,
                                  '$servings portions',
                                  const Color(0xFFFF8A65),
                                ),
                                if (rating > 0) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA726).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA726)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1)}/5',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFFFA726),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 18,
                        color: Colors.black26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportFilterChip(String value, String label) {
    final selected = _catalogImportFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _catalogImportFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6A5AE0)
              : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF6A5AE0),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(
      IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6A5AE0)
              : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF6A5AE0)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6A5AE0) : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF6A5AE0)),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

}
