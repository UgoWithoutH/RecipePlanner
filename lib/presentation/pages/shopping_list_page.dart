import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/firebase_meal_plan_repository.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../../data/repositories/firebase_pantry_snapshot_repository.dart';
import '../../data/repositories/firebase_ingredient_repository.dart';
import '../../data/repositories/firebase_pantry_repository.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/pantry_item.dart';
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

  void _showValidateDialog() {
    final checkedItems = _items.where((i) => i.isChecked).toList();
    final uncheckedItems = _items.where((i) => !i.isChecked).toList();
    // Items réellement en attente de validation (jamais validés ou quantité modifiée)
    final newItems = checkedItems.where((i) => i.validatedQuantity == 0).toList();
    final updateItems = checkedItems.where((i) => i.validatedQuantity > 0 && (i.quantity - i.validatedQuantity).abs() > 0.001).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF4CAF50), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'Valider les courses',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (checkedItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange[700]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Aucun article coché. Cochez les articles achetés avant de valider.',
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          if (newItems.isNotEmpty) '${newItems.length} article(s) ajouté(s) au frigo/placard.',
                          if (updateItems.isNotEmpty) '${updateItems.length} article(s) mis à jour dans le frigo/placard.',
                          if (newItems.isEmpty && updateItems.isEmpty) 'Aucun changement à appliquer.',
                        ].join('  '),
                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF2E7D32)),
                      ),
                    ),
                  ],
                ),
              ),
              if (uncheckedItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange[700]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${uncheckedItems.length} article(s) non coché(s) ne seront pas ajoutés.',
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey[700], fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _validateShoppingList();
                      },
                      child: Text('Valider', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
      ),
    );
  }

  Future<void> _validateShoppingList() async {
    debugPrint('[VALIDATE] ===== _validateShoppingList START =====');
    debugPrint('[VALIDATE] total items=${_items.length} checked=${_items.where((i) => i.isChecked).length}');

    // 1. Récupérer tous les ingrédients connus
    final allIngredients = await FirebaseIngredientRepository().getAllIngredients();
    final ingredientNames = <String, Map<String, dynamic>>{};
    for (final ing in allIngredients) {
      ingredientNames[(ing['name'] as String).toLowerCase().trim()] = ing;
    }

    // 2. Récupérer le pantry existant
    final pantryRepo = FirebasePantryRepository.instance;
    final pantryItems = await pantryRepo.getAll();

    int added = 0;
    int skipped = 0;

    for (final item in _items.where((i) => i.isChecked)) {
      final key = item.name.toLowerCase().trim();
      debugPrint('[VALIDATE] item="${item.name}" qty=${item.quantity} unit=${item.unit} validatedQty=${item.validatedQuantity} knownIngredient=${ingredientNames.containsKey(key)}');

      // Vérifier que l'ingrédient existe dans l'application
      if (!ingredientNames.containsKey(key)) {
        debugPrint('[VALIDATE]   → SKIPPED (ingrédient inconnu)');
        skipped++;
        continue;
      }
      final ing = ingredientNames[key]!;
      final typeId = ing['typeId'] as String? ?? '';
      final typeName = _types.cast<IngredientType?>()
          .firstWhere((t) => t!.id == typeId, orElse: () => null)
          ?.name ?? '';
      final unit = Unit.values.firstWhere(
        (u) => u.name == item.unit,
        orElse: () => Unit.piece,
      );

      // Unité utilisée lors de la dernière validation (pour défaire la contribution précédente)
      final validatedUnit = item.validatedUnit.isNotEmpty
          ? Unit.values.firstWhere((u) => u.name == item.validatedUnit, orElse: () => unit)
          : unit;
      final unitChanged = item.validatedQuantity > 0 && validatedUnit != unit;

      // Chercher si déjà dans le pantry
      final existing = pantryItems.cast<PantryItem?>().firstWhere(
        (p) => p!.name.toLowerCase().trim() == key,
        orElse: () => null,
      );

      // Calculer la quantité à appliquer
      // Si unité changée : qtyToApply n'a pas de sens, on gère séparément
      final qtyToApply = (!unitChanged && item.validatedQuantity > 0)
          ? item.quantity - item.validatedQuantity
          : item.quantity;

      debugPrint('[VALIDATE]   → existing=${existing != null ? "${existing.quantity} ${existing.unit.name}" : "null"} qtyToApply=$qtyToApply unitChanged=$unitChanged validatedUnit=${validatedUnit.name}');

      // Si delta nul (même quantité ET même unité que déjà validée), rien à faire
      if (!unitChanged && qtyToApply.abs() < 0.001 && item.validatedQuantity > 0) {
        debugPrint('[VALIDATE]   → SKIP (delta nul, déjà validé à même quantité)');
        added++;
        continue;
      }

      if (existing != null) {
        if (unitChanged) {
          final pantryInOldUnit = existing.unit == validatedUnit;
          if (pantryInOldUnit) {
            final remaining = existing.quantity - item.validatedQuantity;
            debugPrint('[VALIDATE]   → UNIT CHANGE ${validatedUnit.name}→${unit.name}: undo ${item.validatedQuantity} ${validatedUnit.name}, remaining=$remaining');
            if (remaining <= 0.001) {
              await pantryRepo.delete(existing.id);
              final (normQty, normUnit) = unit.normalize(item.quantity);
              debugPrint('[VALIDATE]   → CREATE (replace): $normQty ${normUnit.name}');
              await pantryRepo.save(PantryItem(
                id: '',
                name: item.name,
                ingredientId: ing['id'] as String? ?? '',
                typeId: typeId,
                typeName: typeName,
                quantity: normQty,
                unit: normUnit,
                isUrgent: false,
                updatedAt: DateTime.now(),
              ));
            } else {
              final remainingConverted = validatedUnit.convertTo(remaining, unit);
              if (remainingConverted != null) {
                final merged = remainingConverted + item.quantity;
                final (normQty, normUnit) = unit.normalize(merged);
                debugPrint('[VALIDATE]   → MERGE: $remaining ${validatedUnit.name} → $remainingConverted ${unit.name} + ${item.quantity} ${unit.name} = $normQty ${normUnit.name}');
                await pantryRepo.save(existing.copyWith(
                  quantity: normQty,
                  unit: normUnit,
                  updatedAt: DateTime.now(),
                ));
              } else {
                final (normQty, normUnit) = unit.normalize(item.quantity);
                debugPrint('[VALIDATE]   → INCOMPATIBLE units, replace: $normQty ${normUnit.name}');
                await pantryRepo.save(existing.copyWith(
                  quantity: normQty,
                  unit: normUnit,
                  updatedAt: DateTime.now(),
                ));
              }
            }
          } else {
            final total = existing.quantity + item.quantity;
            final (normQty, normUnit) = unit.normalize(total);
            debugPrint('[VALIDATE]   → UNIT CHANGE but pantry already in ${existing.unit.name}, adding ${item.quantity} ${unit.name} → $normQty ${normUnit.name}');
            await pantryRepo.save(existing.copyWith(
              quantity: normQty,
              unit: normUnit,
              updatedAt: DateTime.now(),
            ));
          }
        } else {
          // Même unité : appliquer le delta
          final rawQty = (existing.quantity + qtyToApply).clamp(0.0, double.infinity);
          final (normQty, normUnit) = unit.normalize(rawQty);
          debugPrint('[VALIDATE]   → UPDATE pantry: ${existing.quantity} ${existing.unit.name} + $qtyToApply → $normQty ${normUnit.name}');
          if (normQty <= 0) {
            await pantryRepo.delete(existing.id);
          } else {
            await pantryRepo.save(existing.copyWith(
              quantity: normQty,
              unit: normUnit,
              updatedAt: DateTime.now(),
            ));
          }
        }
      } else {
        final (normQty, normUnit) = unit.normalize(item.quantity);
        debugPrint('[VALIDATE]   → CREATE pantry: $normQty ${normUnit.name}');
        await pantryRepo.save(PantryItem(
          id: '',
          name: item.name,
          ingredientId: ing['id'] as String? ?? '',
          typeId: typeId,
          typeName: typeName,
          quantity: normQty,
          unit: normUnit,
          isUrgent: false,
          updatedAt: DateTime.now(),
        ));
      }
      added++;
    }

    debugPrint('[VALIDATE] END added=$added skipped=$skipped');

    // Sauvegarder validatedQuantity pour chaque item coché
    int actualCreated = 0;
    int actualUpdated = 0;

    // Sauvegarder validatedQuantity pour chaque item coché (même ceux ignorés = ingrédient inconnu)
    // validatedQuantity = quantity pour les items ajoutés au pantry
    // validatedQuantity = -1 pour les items cochés mais ingrédient inconnu (marqués "traités")
    if (_currentShoppingList != null) {
      final updatedItems = _items.map((item) {
        if (!item.isChecked) return item;
        if (ingredientNames.containsKey(item.name.toLowerCase().trim())) {
          final wasNew = item.validatedQuantity == 0;
          final wasDifferent = item.validatedQuantity > 0 && (item.quantity - item.validatedQuantity).abs() > 0.001;
          if (wasNew) actualCreated++;
          if (wasDifferent) actualUpdated++;
          return item.copyWith(validatedQuantity: item.quantity, validatedUnit: item.unit);
        } else {
          return item.copyWith(validatedQuantity: -1, validatedUnit: item.unit);
        }
      }).toList();
      if (mounted) setState(() => _items = updatedItems);
      final updatedList = _currentShoppingList!.copyWith(items: updatedItems);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
      debugPrint('[VALIDATE] validatedQuantity saved to Firestore');
    }

    if (mounted) {
      final parts = [
        if (actualCreated > 0) '$actualCreated article(s) ajouté(s) au frigo/placard',
        if (actualUpdated > 0) '$actualUpdated article(s) mis à jour dans le frigo/placard',
        if (skipped > 0) '$skipped ignoré(s) (ingrédient inconnu)',
      ];
      final msg = parts.isNotEmpty ? parts.join(' · ') : 'Aucun changement à appliquer.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _deleteItem(int index) async {
    if (_currentShoppingList == null) return;
    final updated = List<ShoppingItem>.from(_items)..removeAt(index);
    setState(() => _items = updated);
    try {
      final updatedList = _currentShoppingList!.copyWith(items: updated);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
    } catch (e) {}
  }

  Future<void> _saveItemEdit(int index, ShoppingItem newItem) async {
    if (_currentShoppingList == null) return;
    final updated = List<ShoppingItem>.from(_items);
    updated[index] = newItem;
    setState(() => _items = updated);
    try {
      final updatedList = _currentShoppingList!.copyWith(items: updated);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
    } catch (e) {}
  }

  Future<void> _saveNewItem(ShoppingItem newItem) async {
    if (_currentShoppingList == null) return;
    final updated = [..._items, newItem];
    setState(() => _items = updated);
    try {
      final updatedList = _currentShoppingList!.copyWith(items: updated);
      await FirebaseShoppingListRepository().saveShoppingList(updatedList);
      _currentShoppingList = updatedList;
    } catch (e) {}
  }

  void _showAddEditSheet({ShoppingItem? item, int? index}) {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final qtyCtrl = TextEditingController(
      text: (item != null && item.quantity > 0) ? fmtQty(item.quantity) : '',
    );
    Unit selectedUnit = Unit.values.firstWhere(
      (u) => u.name == (item?.unit ?? ''),
      orElse: () => Unit.piece,
    );
    String? selectedTypeId = item?.typeId;
    List<Map<String, dynamic>> suggestions = [];
    bool showSuggestions = false;

    Future<void> fetchSuggestions(String query, void Function(void Function()) setSheetState) async {
      if (query.trim().isEmpty) {
        setSheetState(() { suggestions = []; showSuggestions = false; });
        return;
      }
      final all = await FirebaseIngredientRepository().getAllIngredients();
      final lower = query.toLowerCase();
      final filtered = all
          .where((i) => (i['name'] as String).toLowerCase().contains(lower))
          .take(6)
          .toList();
      setSheetState(() { suggestions = filtered; showSuggestions = filtered.isNotEmpty; });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  item == null ? 'Ajouter un article' : 'Modifier l\'article',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: TextField(
                            controller: nameCtrl,
                            autofocus: item == null,
                            textCapitalization: TextCapitalization.sentences,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: InputBorder.none,
                              hintText: 'Nom',
                              hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                            ),
                            onChanged: (v) => fetchSuggestions(v, setSheetState),
                          ),
                        ),
                        const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'Qté',
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Unit>(
                          value: selectedUnit,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                          dropdownColor: Colors.white,
                          selectedItemBuilder: (context) => Unit.values.map((u) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Unité', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                              Text(u.label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                            ],
                          )).toList(),
                          onChanged: (u) { if (u != null) setSheetState(() => selectedUnit = u); },
                          items: Unit.values.map((u) => DropdownMenuItem<Unit>(
                            value: u,
                            child: Text(u.label, style: GoogleFonts.poppins(fontSize: 14)),
                          )).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedTypeId,
                    isExpanded: true,
                    icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                    dropdownColor: Colors.white,
                    selectedItemBuilder: (context) {
                      final allIds = <String?>[null, ..._types.where((t) => t.name != 'Autre').map((t) => t.id)];
                      return allIds.map((id) {
                        final name = id == null ? 'Autre' : _types.firstWhere((t) => t.id == id, orElse: () => IngredientType(id: '', name: 'Autre', color: 0)).name;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Catégorie (optionnel)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                            Text(name, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                          ],
                        );
                      }).toList();
                    },
                    onChanged: (v) => setSheetState(() => selectedTypeId = v),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Autre', style: GoogleFonts.poppins(fontSize: 14)),
                      ),
                      ..._types.where((t) => t.name != 'Autre').map((t) => DropdownMenuItem<String?>(
                        value: t.id,
                        child: Row(
                          children: [
                            Container(
                              width: 10, height: 10,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(color: Color(t.color), shape: BoxShape.circle),
                            ),
                            Text(t.name, style: GoogleFonts.poppins(fontSize: 14)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A5AE0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final qty = double.tryParse(
                          qtyCtrl.text.replaceAll(',', '.').replaceAll('\u00a0', '').replaceAll(' ', '')) ??
                      0.0;
                  final newItem = ShoppingItem(
                    name: name,
                    quantity: qty,
                    unit: selectedUnit.name,
                    typeId: selectedTypeId,
                    isChecked: item?.isChecked ?? false,
                    contributions: item?.contributions ?? [],
                    totalRequiredBase: item?.totalRequiredBase ?? 0,
                    validatedQuantity: item?.validatedQuantity ?? 0,
                    validatedUnit: item?.validatedUnit ?? '',
                  );
                  Navigator.pop(ctx);
                  if (index != null) {
                    await _saveItemEdit(index, newItem);
                  } else {
                    await _saveNewItem(newItem);
                  }
                },
                child: Text(
                  item == null ? 'Ajouter' : 'Enregistrer',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (showSuggestions)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: suggestions.map((s) {
                        final name = s['name'] as String;
                        final typeId = s['typeId'] as String?;
                        final typeName = typeId != null
                            ? _types.firstWhere((t) => t.id == typeId, orElse: () => IngredientType(id: '', name: '', color: 0)).name
                            : null;
                        return InkWell(
                          onTap: () {
                            nameCtrl.text = name;
                            setSheetState(() {
                              showSuggestions = false;
                              suggestions = [];
                              if (typeId != null && typeId.isNotEmpty) selectedTypeId = typeId;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(name, style: GoogleFonts.poppins(fontSize: 14)),
                                ),
                                if (typeName != null && typeName.isNotEmpty)
                                  Text(
                                    typeName,
                                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
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

class _ShoppingListItemCard extends StatefulWidget {
  final ShoppingItem item;
  final VoidCallback onCheckTap;
  final VoidCallback onEditTap;
  final VoidCallback onDeleteTap;
  final PantrySnapshotItem? pantryMatch;
  final List<RecipeContribution> contributions;
  final String Function(double) formatQuantity;

  const _ShoppingListItemCard({
    required this.item,
    required this.onCheckTap,
    required this.onEditTap,
    required this.onDeleteTap,
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
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.info_outline_rounded,
                              size: 22,
                              color: const Color(0xFF6A5AE0).withOpacity(0.55)),
                        ),
                      ),
                    ],
                    if (item.isChecked) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onEditTap,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.edit_outlined,
                              size: 22,
                              color: const Color(0xFF6A5AE0).withOpacity(0.5)),
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDeleteTap,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 22,
                              color: Colors.red[200]),
                        ),
                      ),
                    ],
                    if (!item.isChecked) ...[  
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onEditTap,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.edit_outlined,
                              size: 22,
                              color: Colors.grey[400]),
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDeleteTap,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 22,
                              color: Colors.red[300]),
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
