import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/ingredient_name_cache.dart';
import '../recipe_detail/recipe_detail_page.dart';
import '../../../domain/entities/recipe.dart';
import '../../../core/constants/unit.dart' show Unit;
import '../../../core/constants/meal_time.dart';
import '../../../domain/entities/ingredient.dart';
import '../../../domain/entities/recipe_ingredient.dart';
import '../ingredient_types_page.dart';
import '../../../domain/entities/ingredient_type.dart';
import '../../../data/repositories/firebase_ingredient_repository.dart';
import '../../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../../data/repositories/firebase_shopping_list_repository.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../data/repositories/firebase_stats_repository.dart';

part 'ingredients_crud.dart';
part 'ingredients_filters.dart';

part 'ingredients_widgets.dart';

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

