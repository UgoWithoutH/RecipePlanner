import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/repositories/group_repository.dart';

/// Page de sélection d'une recette prédéfinie depuis la collection `recipes_cache`.
/// Retourne un [Map<String, dynamic>] au pop, ou null si annulé.
class PresetRecipePickerPage extends StatefulWidget {
  const PresetRecipePickerPage({super.key});

  @override
  State<PresetRecipePickerPage> createState() => _PresetRecipePickerPageState();
}

class _PresetRecipePickerPageState extends State<PresetRecipePickerPage> {
  bool _isLoading = true;

  // Data
  List<Map<String, dynamic>> _allRecipes = [];
  List<String> _allCategoryNames = [];

  // Group categories (for colors)
  List<Map<String, dynamic>> _groupCategories = [];

  // Filters
  String _titleFilter = '';
  String _ingredientFilter = '';
  Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load preset recipes from recipes_cache
    final snap = await FirebaseFirestore.instance
        .collection('recipes_cache')
        .get();

    final recipes = snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['_id'] = doc.id;
      return data;
    }).toList();

    // Sort alphabetically by title
    recipes.sort(
        (a, b) => (a['title'] as String).compareTo(b['title'] as String));

    // Extract unique category names
    final catSet = <String>{};
    for (final r in recipes) {
      final cats = (r['categories'] as List?)?.map((e) => e.toString()) ?? [];
      catSet.addAll(cats);
    }
    final sortedCats = catSet.toList()..sort();

    // Load group categories for colors
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    List<Map<String, dynamic>> groupCats = [];
    if (groupId != null) {
      final cSnap = await FirebaseFirestore.instance
          .collection('categories')
          .where('groupId', isEqualTo: groupId)
          .get();
      groupCats = cSnap.docs.map((d) {
        final data = d.data();
        return <String, dynamic>{
          'name': data['name'] as String? ?? '',
          'color': data['color'] as int? ?? 0xFF6A5AE0,
        };
      }).toList();
    }

    if (mounted) {
      setState(() {
        _allRecipes = recipes;
        _allCategoryNames = sortedCats;
        _groupCategories = groupCats;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _allRecipes.where((r) {
      final title = (r['title'] as String? ?? '').toLowerCase();
      final matchesTitle = _titleFilter.isEmpty ||
          title.contains(_titleFilter.toLowerCase());

      final matchesCat = _selectedCategories.isEmpty ||
          (r['categories'] as List?)
                  ?.any((c) => _selectedCategories.contains(c.toString())) ==
              true;

      final matchesIngredient = _ingredientFilter.isEmpty ||
          (r['ingredients'] as List?)?.any((i) {
                final name =
                    ((i as Map)['name'] as String? ?? '').toLowerCase();
                return name.contains(_ingredientFilter.toLowerCase());
              }) ==
              true;

      return matchesTitle && matchesCat && matchesIngredient;
    }).toList();
  }

  int _colorForCategory(String name) {
    final match = _groupCategories.firstWhere(
      (c) => c['name'] == name,
      orElse: () => <String, dynamic>{'color': 0xFF6A5AE0},
    );
    return match['color'] as int? ?? 0xFF6A5AE0;
  }

  // ── Detail dialog ──────────────────────────────────────────────────────────

  void _showDetail(Map<String, dynamic> recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresetDetailSheet(
        recipe: recipe,
        colorForCategory: _colorForCategory,
        onSelect: () {
          Navigator.pop(context); // close sheet
          Navigator.pop(context, recipe); // return recipe to caller
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
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
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.1),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                size: 18, color: Colors.black87),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Recettes prédéfinies',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  // Category chips
                  SizedBox(
                    height: 50,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: _allCategoryNames.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          final isAll = _selectedCategories.isEmpty;
                          return FilterChip(
                            label: Text(
                              'Toutes',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF6A5AE0),
                              ),
                            ),
                            selected: isAll,
                            onSelected: (_) =>
                                setState(() => _selectedCategories.clear()),
                            backgroundColor:
                                const Color(0xFF6A5AE0).withOpacity(0.15),
                            selectedColor:
                                const Color(0xFF6A5AE0).withOpacity(0.35),
                            checkmarkColor: const Color(0xFF6A5AE0),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          );
                        }
                        final name = _allCategoryNames[i - 1];
                        final isSelected = _selectedCategories.contains(name);
                        final colorVal = _colorForCategory(name);
                        final baseColor = Color(colorVal);
                        final hsl = HSLColor.fromColor(baseColor);
                        final textColor = hsl
                            .withLightness(hsl.lightness > 0.4 ? 0.4 : hsl.lightness)
                            .toColor();
                        return FilterChip(
                          label: Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (v) => setState(() => v
                              ? _selectedCategories.add(name)
                              : _selectedCategories.remove(name)),
                          backgroundColor: baseColor.withOpacity(0.15),
                          selectedColor: baseColor.withOpacity(0.35),
                          checkmarkColor: textColor,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        );
                      },
                    ),
                  ),

                  // Title search
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Filtrer par titre...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() => _titleFilter = v),
                    ),
                  ),

                  // Ingredient search
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Filtrer par ingrédient...',
                        prefixIcon:
                            const Icon(Icons.kitchen_outlined, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() => _ingredientFilter = v),
                    ),
                  ),

                  // Count
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: Text(
                      '${_filtered.length} recette${_filtered.length > 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),

                  // List
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune recette trouvée',
                              style: GoogleFonts.poppins(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 16),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, idx) {
                              final recipe = _filtered[idx];
                              final cats = (recipe['categories'] as List?)
                                      ?.map((e) => e.toString())
                                      .toList() ??
                                  [];
                              final totalTime =
                                  ((recipe['preparationTime'] as num?)?.toInt() ??
                                          0) +
                                      ((recipe['cookingTime'] as num?)?.toInt() ??
                                          0);
                              final servings =
                                  (recipe['servings'] as num?)?.toInt() ?? 0;

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
                                    onTap: () => _showDetail(recipe),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Title + category chips
                                                Wrap(
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Text(
                                                      recipe['title'] as String? ??
                                                          '',
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                            0xFF1A1A1A),
                                                      ),
                                                    ),
                                                    ...cats.map((catName) {
                                                      final colorVal =
                                                          _colorForCategory(
                                                              catName);
                                                      final base =
                                                          Color(colorVal);
                                                      final hsl = HSLColor
                                                          .fromColor(base);
                                                      final textColor = hsl
                                                          .withLightness(
                                                              hsl.lightness >
                                                                      0.4
                                                                  ? 0.4
                                                                  : hsl.lightness)
                                                          .toColor();
                                                      return Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 8,
                                                            vertical: 3),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: base
                                                              .withOpacity(0.15),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(20),
                                                        ),
                                                        child: Text(
                                                          catName,
                                                          style: GoogleFonts
                                                              .poppins(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: textColor,
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  recipe['description']
                                                          as String? ??
                                                      '',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.grey[600],
                                                    fontSize: 13,
                                                    height: 1.4,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    _stat(
                                                        Icons
                                                            .access_time_rounded,
                                                        '$totalTime min',
                                                        const Color(
                                                            0xFF5C6BC0)),
                                                    const SizedBox(width: 20),
                                                    _stat(
                                                        Icons.pie_chart_rounded,
                                                        '$servings portions',
                                                        const Color(
                                                            0xFFFF8A65)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(
                                              Icons.chevron_right_rounded,
                                              color: Colors.black26),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700])),
      ],
    );
  }
}

// ── Detail bottom sheet ──────────────────────────────────────────────────────

class _PresetDetailSheet extends StatelessWidget {
  final Map<String, dynamic> recipe;
  final int Function(String) colorForCategory;
  final VoidCallback onSelect;

  const _PresetDetailSheet({
    required this.recipe,
    required this.colorForCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cats = (recipe['categories'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final ingredients =
        (recipe['ingredients'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
    final instructions =
        (recipe['instructions'] as List?)?.map((e) => e.toString()).toList() ??
            [];
    final prepTime =
        (recipe['preparationTime'] as num?)?.toInt() ?? 0;
    final cookTime = (recipe['cookingTime'] as num?)?.toInt() ?? 0;
    final servings = (recipe['servings'] as num?)?.toInt() ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                children: [
                  // Title
                  Text(
                    recipe['title'] as String? ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Category chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: cats.map((name) {
                      final colorVal = colorForCategory(name);
                      final base = Color(colorVal);
                      final hsl = HSLColor.fromColor(base);
                      final textColor = hsl
                          .withLightness(
                              hsl.lightness > 0.4 ? 0.4 : hsl.lightness)
                          .toColor();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: base.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Stats
                  Row(
                    children: [
                      _statBadge(Icons.timer_outlined,
                          'Préparation : ${prepTime} min', const Color(0xFF5C6BC0)),
                      const SizedBox(width: 12),
                      _statBadge(Icons.local_fire_department_outlined,
                          'Cuisson : ${cookTime} min', Colors.orange),
                      const SizedBox(width: 12),
                      _statBadge(Icons.pie_chart_outline,
                          '$servings portions', const Color(0xFFFF8A65)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  if ((recipe['description'] as String?)?.isNotEmpty == true)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        recipe['description'] as String,
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: Colors.black87, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Ingredients
                  Text(
                    'Ingrédients',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...ingredients.map((i) {
                    final name = i['name'] as String? ?? '';
                    final qty = (i['quantity'] as num?)?.toDouble() ?? 0;
                    final unit = i['unit'] as String? ?? '';
                    final type = i['type'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6A5AE0),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.poppins(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${qty % 1 == 0 ? qty.toInt() : qty} $unit',
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                          if (type.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF6A5AE0).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                type,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: const Color(0xFF6A5AE0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Instructions
                  if (instructions.isNotEmpty) ...[
                    Text(
                      'Instructions',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    ...instructions.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
                                '${e.key + 1}',
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
                                e.value,
                                style: GoogleFonts.poppins(
                                    fontSize: 14, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

            // Select button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  shadowColor: const Color(0xFF6A5AE0).withOpacity(0.4),
                  child: InkWell(
                    onTap: onSelect,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A5AE0),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              color: Colors.white),
                          const SizedBox(width: 10),
                          Text(
                            'Choisir cette recette',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
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
    );
  }

  Widget _statBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
