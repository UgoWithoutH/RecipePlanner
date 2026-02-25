import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/usecases/shopping_list_generator.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
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
      debugPrint('Error loading shopping list: $e');
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
      debugPrint("Error updating item: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sort items: Unchecked first, then Checked
    // Within those groups, alphabetical
    final displayItems = List<ShoppingItem>.from(_items);
    displayItems.sort((a, b) {
      if (a.isChecked != b.isChecked) {
        return a.isChecked ? 1 : -1; // Unchecked first (false < true)
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
                              ? '${_items.length} articles à acheter'
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

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? Center(
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
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              itemCount: displayItems.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = displayItems[index];
                                // Use key to find original index or just pass the item logic
                                final originalIndex = _items.indexOf(item);
                                return _buildShoppingListItem(item, originalIndex);
                              },
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
                    '${widget.formatQuantity(item.quantity)} ${item.unit}',
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
