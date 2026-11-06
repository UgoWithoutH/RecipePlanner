// ignore_for_file: invalid_use_of_protected_member
part of 'shopping_list_page.dart';

extension _ShoppingListValidation on _ShoppingListPageState {
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
}
