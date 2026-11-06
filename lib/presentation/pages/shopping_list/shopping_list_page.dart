import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/repositories/firebase_meal_plan_repository.dart';
import '../../../data/repositories/firebase_shopping_list_repository.dart';
import '../../../data/repositories/firebase_pantry_snapshot_repository.dart';
import '../../../data/repositories/firebase_ingredient_repository.dart';
import '../../../data/repositories/firebase_pantry_repository.dart';
import '../../../domain/entities/meal_plan.dart';
import '../../../domain/entities/pantry_item.dart';
import '../../../domain/entities/shopping_list.dart';
import '../../../domain/usecases/shopping_list_generator.dart';
import '../../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../../domain/entities/ingredient_type.dart';
import '../../../core/constants/unit.dart';
import '../../../core/utils/qty_format.dart';
import '../recipe_detail/recipe_detail_page.dart';

part 'shopping_list_validation.dart';
part 'shopping_list_edit_sheet.dart';

part 'shopping_list_item_card.dart';

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
      // Dédupliquer par id pour éviter les doublons Firestore
      final rawTypes = results[0] as List<IngredientType>;
      final seenIds = <String>{};
      _types = rawTypes.where((t) => seenIds.add(t.id)).toList();
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

    final item = _items[index];
    final nowChecked = !item.isChecked;

    // Empêcher de décocher un item déjà validé dans le frigo/placard
    if (!nowChecked && item.validatedQuantity != 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Cet article a déjà été validé. Utilisez le bouton d\'édition pour modifier la quantité.',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
            )),
          ]),
          backgroundColor: const Color(0xFF6A5AE0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ));
      }
      return;
    }

    setState(() {
      _items[index] = item.copyWith(isChecked: nowChecked);
    });

    try {
      final updatedList = _currentShoppingList!.copyWith(items: _items);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
    } catch (e) {}

    // Si l'item avait déjà été validé (validatedQuantity > 0) et qu'on le re-coche
    // (après décoché + modification quantité), appliquer le delta au frigo/placard.
    if (nowChecked && item.validatedQuantity > 0) {
      final delta = _items[index].quantity - item.validatedQuantity;
      if (delta.abs() > 0.001) {
        await _applyPantryDelta(item: _items[index], delta: delta);
        // Mettre à jour validatedQuantity
        final updatedItem = _items[index].copyWith(validatedQuantity: _items[index].quantity);
        setState(() => _items[index] = updatedItem);
        final updatedList = _currentShoppingList!.copyWith(items: _items);
        await FirebaseShoppingListRepository().saveShoppingList(updatedList);
        _currentShoppingList = updatedList;
      }
    }

    // Si tout est coché ET qu'il reste des items non traités, proposer la validation
    final hasPending = _items.any((i) =>
        i.isChecked && (
          i.validatedQuantity == 0 ||
          (i.validatedQuantity > 0 && (i.quantity - i.validatedQuantity).abs() > 0.001)
        ));
    if (_items.isNotEmpty && _items.every((i) => i.isChecked) && hasPending) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _showValidateDialog();
    }
  }

  /// Applique un delta (positif = ajouter, négatif = déduire) sur l'ingrédient dans le pantry.
  Future<void> _applyPantryDelta({required ShoppingItem item, required double delta}) async {
    try {
      final allIngredients = await FirebaseIngredientRepository().getAllIngredients();
      final key = item.name.toLowerCase().trim();
      final ing = allIngredients.cast<Map<String, dynamic>?>().firstWhere(
        (i) => (i!['name'] as String).toLowerCase().trim() == key,
        orElse: () => null,
      );
      if (ing == null) return;

      final pantryRepo = FirebasePantryRepository.instance;
      final pantryItems = await pantryRepo.getAll();
      final existing = pantryItems.cast<PantryItem?>().firstWhere(
        (p) => p!.name.toLowerCase().trim() == key,
        orElse: () => null,
      );

      final unit = Unit.values.firstWhere(
        (u) => u.name == item.unit,
        orElse: () => Unit.piece,
      );

      if (existing != null) {
        final newQty = existing.unit == unit
            ? (existing.quantity + delta).clamp(0.0, double.infinity)
            : (delta > 0 ? delta : 0.0);
        if (newQty <= 0) {
          await pantryRepo.delete(existing.id);
        } else {
          await pantryRepo.save(existing.copyWith(quantity: newQty, updatedAt: DateTime.now()));
        }
      } else if (delta > 0) {
        // Pas encore dans le pantry, créer avec le delta positif
        final typeId = ing['typeId'] as String? ?? '';
        final typeName = _types.cast<IngredientType?>()
            .firstWhere((t) => t!.id == typeId, orElse: () => null)
            ?.name ?? '';
        await pantryRepo.save(PantryItem(
          id: '',
          name: item.name,
          ingredientId: ing['id'] as String? ?? '',
          typeId: typeId,
          typeName: typeName,
          quantity: delta,
          unit: unit,
          isUrgent: false,
          updatedAt: DateTime.now(),
        ));
      }
    } catch (e) {}
  }


  Widget _buildAddFab() {
    return FloatingActionButton(
      onPressed: () => _showAddEditSheet(),
      backgroundColor: const Color(0xFF6A5AE0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.add_rounded, color: Colors.white),
    );
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
        floatingActionButton: _currentShoppingList != null ? _buildAddFab() : null,
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
      floatingActionButton: _currentShoppingList != null ? _buildAddFab() : null,
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
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

                // Bouton valider — uniquement s'il y a des items cochés non encore validés
                if (_currentShoppingList != null && _items.any((i) =>
                    i.isChecked && (
                      i.validatedQuantity == 0 ||
                      (i.validatedQuantity > 0 && (i.quantity - i.validatedQuantity).abs() > 0.001)
                    )))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _showValidateDialog,
                      icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                      label: Text('Valider les courses', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),

                // List content
                Expanded(
                  child: SlidableAutoCloseBehavior(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    children: [
                      // Empty state when all items are checked
                      if (groupedUnchecked.isEmpty && checkedItems.isNotEmpty)
                         Padding(
                           padding: const EdgeInsets.symmetric(vertical: 40),
                           child: Center(
                             child: Column(
                               children: [
                                 Icon(Icons.check_circle_outline_rounded, size: 60, color: Colors.green[300]),
                                 const SizedBox(height: 16),
                                 Text(
                                   checkedItems.every((i) => i.validatedQuantity != 0)
                                       ? 'Tout a été validé !'
                                       : 'Tout est coché !',
                                   style: GoogleFonts.poppins(fontSize: 18, color: Colors.green[700]),
                                 ),
                                 if (checkedItems.every((i) => i.validatedQuantity != 0))
                                   Padding(
                                     padding: const EdgeInsets.only(top: 6),
                                     child: Text(
                                       'Les articles ont été ajoutés au frigo/placard.',
                                       style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
                                       textAlign: TextAlign.center,
                                     ),
                                   ),
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
      onEditTap: () => _showAddEditSheet(item: item, index: originalIndex),
      onDeleteTap: () async {
        final isValidated = item.isChecked && item.validatedQuantity > 0;
        final confirmed = await showModalBottomSheet<bool>(
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
                Text('Supprimer l\'article',
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
                const SizedBox(height: 8),
                Text('Supprimer "${item.name}" de la liste ?',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
                if (isValidated) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cet article a déjà été validé. La quantité sera retirée de votre frigo/placard.',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
        if (confirmed == true) {
          if (isValidated) {
            await _applyPantryDelta(item: item, delta: -item.validatedQuantity);
          }
          _deleteItem(originalIndex);
        }
      },
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

