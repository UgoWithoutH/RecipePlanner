import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../data/repositories/firebase_pantry_snapshot_repository.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/usecases/shopping_list_generator.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../core/constants/unit.dart';
import '../../core/utils/qty_format.dart';
import 'recipe_detail_page.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  MealPlan? _mealPlan;
  ShoppingList? _currentShoppingList;
  bool _isLoading = true;
  List<ShoppingItem> _items = [];
  List<IngredientType> _types = [];
  List<PantrySnapshotItem> _pantrySnapshot = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 0. Load types in parallel or before
      final typeRepo = FirebaseIngredientTypeRepository();
      final results = await Future.wait([
        typeRepo.getTypes(),
        FirebasePantrySnapshotRepository.instance.get(),
      ]);
      _types = results[0] as List<IngredientType>;
      _pantrySnapshot = results[1] as List<PantrySnapshotItem>;

      // 1. Load the latest meal plan
      final planRepo = FirebaseMealPlanRepository();
      final plans = await planRepo.getAllMealPlans();
      
      if (plans.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }


      // Sort by date descending to get the latest
      plans.sort((a, b) => b.startDate.compareTo(a.startDate));
      _mealPlan = plans.first;

      // 2. Fetch Shopping List from DB
      final shoppingRepo = FirebaseShoppingListRepository();
      var shoppingList = await shoppingRepo.getGroupShoppingList();

      // 3. Migration / Fallback: If no list exists, generate it
      if (shoppingList == null) {
         await ShoppingListGenerator().generateAndSaveShoppingList(_mealPlan!);
         shoppingList = await shoppingRepo.getGroupShoppingList();
      }

      if (shoppingList != null) {
        _currentShoppingList = shoppingList;
        _items = List.from(shoppingList.items);
      }

    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleItem(int index) async {
    if (_currentShoppingList == null) return;
    
    setState(() {
      final item = _items[index];
      // Create a modified copy
      _items[index] = item.copyWith(isChecked: !item.isChecked);
    });

    // Save update to DB
    try {
      final updatedList = _currentShoppingList!.copyWith(items: _items);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.remove_shopping_cart_outlined, size: 60, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                "Votre liste est vide",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group items logic
    final uncheckedItems = _items.where((i) => !i.isChecked).toList();
    final checkedItems = _items.where((i) => i.isChecked).toList();

    // Sort unchecked items by name for consistency
    uncheckedItems.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Group unchecked by typeId
    final Map<String?, List<ShoppingItem>> groupedUnchecked = {};
    for (final item in uncheckedItems) {
      final key = item.typeId;
      groupedUnchecked.putIfAbsent(key, () => []).add(item);
    }

    // Sort groups ? Maybe prioritize Types that exist in _types
    // Order: Types in _types order, then 'Other' (null)
    final sortedKeys = groupedUnchecked.keys.toList();
    sortedKeys.sort((a, b) {
      if (a == null) return 1; // Null last
      if (b == null) return -1;
      final typeA = _types.indexWhere((t) => t.id == a);
      final typeB = _types.indexWhere((t) => t.id == b);
      if (typeA == -1 && typeB == -1) return 0;
      if (typeA == -1) return 1;
      if (typeB == -1) return -1;
      return typeA.compareTo(typeB);
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 200,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ma Liste',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            _mealPlan != null 
                              ? '${uncheckedItems.length} articles à acheter'
                              : 'Aucun plan actif',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: Color(0xFF6A5AE0),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress bar
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: checkedItems.length / _items.length,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6A5AE0)),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${checkedItems.length} / ${_items.length} cochés',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),

                // List content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    children: [
                      // Empty state for "All done" but items exist
                      if (groupedUnchecked.isEmpty && checkedItems.isNotEmpty)
                         Padding(
                           padding: const EdgeInsets.symmetric(vertical: 40),
                           child: Center(
                             child: Column(
                               children: [
                                 Icon(Icons.check_circle_outline_rounded, size: 60, color: Colors.green[300]),
                                 const SizedBox(height: 16),
                                 Text("Tout est prêt !", style: GoogleFonts.poppins(fontSize: 18, color: Colors.green[700])),
                               ],
                             ),
                           ),
                         ),

                      ...sortedKeys.map((typeId) {
                        final itemsInGroup = groupedUnchecked[typeId]!;
                        // Find Type info
                        String headerTitle = 'Autre';
                        Color headerColor = Colors.grey;
                        
                        if (typeId != null) {
                           final type = _types.cast<IngredientType?>().firstWhere(
                             (t) => t?.id == typeId, 
                             orElse: () => null
                           );
                           if (type != null) {
                             headerTitle = type.name;
                             headerColor = Color(type.color);
                           }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Row(
                                children: [
                                  if (typeId != null) ...[
                                    // Modern arrow shape for type color (flèche vers la droite)
                                    CustomPaint(
                                      size: const Size(18, 18),
                                      painter: _ArrowTypePainterRight(headerColor),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    headerTitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${itemsInGroup.length})',
                                     style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                                  )
                                ],
                              ),
                            ),
                            ...itemsInGroup.map((item) {
                               final originalIndex = _items.indexOf(item);
                               return Padding(
                                 padding: const EdgeInsets.only(bottom: 12),
                                 child: _buildShoppingListItem(item, originalIndex),
                               );
                            }),
                          ],
                        );
                      }),
                      
                      // Checked Items (Completed)
                      if (checkedItems.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Déjà pris',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ...checkedItems.map((item) {
                           final originalIndex = _items.indexOf(item);
                           return Padding(
                             padding: const EdgeInsets.only(bottom: 12),
                             child: _buildShoppingListItem(item, originalIndex),
                           );
                        }),
                        const SizedBox(height: 40), // Bottom padding
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingListItem(ShoppingItem item, int originalIndex) {
    final pantryMatch = _findPantryMatch(item);
    return _ShoppingListItemCard(
      item: item,
      onCheckTap: () => _toggleItem(originalIndex),
      pantryMatch: pantryMatch,
      contributions: item.contributions,
      formatQuantity: _formatQuantity,
    );
  }

  PantrySnapshotItem? _findPantryMatch(ShoppingItem item) {
    return _pantrySnapshot.cast<PantrySnapshotItem?>().firstWhere(
      (p) => p!.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
      orElse: () => null,
    );
  }

  String _formatQuantity(double qty) => fmtQty(qty);
}

class _ShoppingListItemCard extends StatefulWidget {
  final ShoppingItem item;
  final VoidCallback onCheckTap;
  final PantrySnapshotItem? pantryMatch;
  final List<RecipeContribution> contributions;
  final String Function(double) formatQuantity;

  const _ShoppingListItemCard({
    required this.item,
    required this.onCheckTap,
    required this.pantryMatch,
    required this.contributions,
    required this.formatQuantity,
  });

  @override
  State<_ShoppingListItemCard> createState() => _ShoppingListItemCardState();
}

class _ShoppingListItemCardState extends State<_ShoppingListItemCard> {
  bool _expanded = false;

  String _formatBase(double base, String displayUnit) {
    final isVolume = displayUnit == 'l' || displayUnit == 'ml';
    final isMass = displayUnit == 'kg' || displayUnit == 'g';
    if (isVolume && base >= 1000) return '${fmtQty(base / 1000)} l';
    if (isVolume) return '${fmtQty(base)} ml';
    if (isMass && base >= 1000) return '${fmtQty(base / 1000)} kg';
    if (isMass) return '${fmtQty(base)} g';
    return '${fmtQty(base)} ${Unit.labelOf(displayUnit)}';
  }

  void _showContributionsSheet(BuildContext context) {
    final item = widget.item;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Row(
                children: [
                  const Icon(Icons.restaurant_menu_rounded,
                      size: 18, color: Color(0xFF6A5AE0)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Recettes du plan de repas',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            Divider(height: 1, color: Colors.grey.withOpacity(0.15)),
            ...widget.contributions.map((c) {
              final qty = c.quantity > 0 && c.unit.isNotEmpty
                  ? '${fmtQty(c.quantity)} ${Unit.labelOf(c.unit)}'
                  : '';
              final canNavigate = c.recipeId.isNotEmpty;
              return InkWell(
                onTap: canNavigate
                    ? () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeDetailPage(recipeId: c.recipeId),
                          ),
                        );
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.menu_book_rounded,
                            size: 18, color: Color(0xFF6A5AE0)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.recipeName,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF1A1A1A)),
                            ),
                            if (qty.isNotEmpty)
                              Text(
                                qty,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ),
                      if (canNavigate)
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.grey[400]),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDetail = !item.isChecked &&
        (item.totalRequiredBase > 0 || widget.pantryMatch != null);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: item.isChecked ? Colors.grey[50] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? const Color(0xFF6A5AE0).withOpacity(0.25)
              : item.isChecked
                  ? Colors.transparent
                  : Colors.grey.withOpacity(0.1),
          width: _expanded ? 1.5 : 1.0,
        ),
        boxShadow: item.isChecked || _expanded
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(15))
                  : BorderRadius.circular(15),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onCheckTap,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: item.isChecked
                              ? const Color(0xFF6A5AE0)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: item.isChecked
                                ? const Color(0xFF6A5AE0)
                                : Colors.grey[400]!,
                            width: 2,
                          ),
                        ),
                        child: item.isChecked
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: item.isChecked
                                  ? Colors.grey[400]
                                  : const Color(0xFF1A1A1A),
                              decoration:
                                  item.isChecked ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.grey[400],
                            ),
                          ),

                        ],
                      ),
                    ),

                    if (item.quantity > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.isChecked
                              ? Colors.transparent
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.formatQuantity(item.quantity)} ${Unit.labelOf(item.unit)}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: item.isChecked
                                ? Colors.grey[400]
                                : const Color(0xFF6A5AE0),
                          ),
                        ),
                      ),
                    if (!item.isChecked && widget.contributions.isNotEmpty) ...[  
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showContributionsSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.info_outline_rounded,
                              size: 18,
                              color: const Color(0xFF6A5AE0).withOpacity(0.55)),
                        ),
                      ),
                    ],
                    if (hasDetail) ...[
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded,
                            size: 20, color: Colors.grey[400]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded ? _buildDetail() : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail() {
    final item = widget.item;
    final pantry = widget.pantryMatch;
    final hasTotal = item.totalRequiredBase > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.withOpacity(0.12)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FF),
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  children: [
                    if (hasTotal)
                      _qRow(
                          'Total requis',
                          _formatBase(item.totalRequiredBase, item.unit),
                          Colors.grey[700]!),
                    if (pantry != null) ...[
                      if (hasTotal) const SizedBox(height: 6),
                      _qRow(
                          'Placard / frigo',
                          '${fmtQty(pantry.quantity)} ${pantry.unit.label}',
                          const Color(0xFF26A69A)),
                    ],
                    if (hasTotal || pantry != null) ...[
                      const SizedBox(height: 6),
                      Divider(
                          height: 1,
                          color: Colors.grey.withOpacity(0.15)),
                      const SizedBox(height: 6),
                    ],
                    _qRow(
                        'À acheter',
                        item.quantity > 0
                            ? '${fmtQty(item.quantity)} ${Unit.labelOf(item.unit)}'
                            : '—',
                        const Color(0xFF6A5AE0),
                        bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qRow(String label, String value, Color color, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[600]))),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// En dehors de la classe _ShoppingListPageState, ajouter ce painter :

class _ArrowTypePainterRight extends CustomPainter {
  final Color color;
  _ArrowTypePainterRight(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
