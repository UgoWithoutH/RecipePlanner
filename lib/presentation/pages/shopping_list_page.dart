import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/usecases/shopping_list_generator.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../core/constants/unit.dart';

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
      _types = await typeRepo.getTypes();

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
      var shoppingList = await shoppingRepo.getShoppingListByMealPlanId(_mealPlan!.id);

      // 3. Migration / Fallback: If no list exists for this plan, generate it
      if (shoppingList == null) {
         await ShoppingListGenerator().generateAndSaveShoppingList(_mealPlan!);
         shoppingList = await shoppingRepo.getShoppingListByMealPlanId(_mealPlan!.id);
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
    return _ShoppingListItemCard(
      item: item,
      onTap: () => _toggleItem(originalIndex),
      formatQuantity: _formatQuantity,
    );
  }

  String _formatQuantity(double qty) {
    if (qty == qty.toInt()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(1);
  }
}

// ── Press/scale animation wrapper for shopping list items ──
class _ShoppingListItemCard extends StatefulWidget {
  final ShoppingItem item;
  final VoidCallback onTap;
  final String Function(double) formatQuantity;

  const _ShoppingListItemCard({
    required this.item,
    required this.onTap,
    required this.formatQuantity,
  });

  @override
  State<_ShoppingListItemCard> createState() => _ShoppingListItemCardState();
}

class _ShoppingListItemCardState extends State<_ShoppingListItemCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: item.isChecked ? Colors.grey[50] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isChecked ? Colors.transparent : Colors.grey.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: item.isChecked
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(_pressed ? 0.01 : 0.04),
                      blurRadius: _pressed ? 4 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Checkbox
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.isChecked ? const Color(0xFF6A5AE0) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: item.isChecked ? const Color(0xFF6A5AE0) : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: item.isChecked
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 16),
              // Text
              Expanded(
                child: Text(
                  item.name,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: item.isChecked ? Colors.grey[400] : const Color(0xFF1A1A1A),
                    decoration: item.isChecked ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.grey[400],
                  ),
                ),
              ),
              // Quantity
              if (item.quantity > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.isChecked ? Colors.transparent : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.formatQuantity(item.quantity)} ${Unit.labelOf(item.unit)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.isChecked ? Colors.grey[400] : const Color(0xFF6A5AE0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
