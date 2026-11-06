// ignore_for_file: invalid_use_of_protected_member
part of 'shopping_list_page.dart';

extension _ShoppingListEditSheet on _ShoppingListPageState {
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
    // Normalise: keep typeId only if it exists in the dropdown (excludes 'Autre'-named types)
    final _validTypeIds = _types
        .where((t) => t.name != 'Autre' && t.id.isNotEmpty)
        .map((t) => t.id)
        .toSet();
    String? selectedTypeId = (item?.typeId != null && _validTypeIds.contains(item!.typeId))
        ? item.typeId
        : null;
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
                    onChanged: (v) => setSheetState(() => selectedTypeId = v),
                    // _types is already deduplicated — filter 'Autre'-named and empty-id entries
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Autre', style: GoogleFonts.poppins(fontSize: 14)),
                      ),
                      ..._types
                          .where((t) => t.name != 'Autre' && t.id.isNotEmpty)
                          .map((t) => DropdownMenuItem<String?>(
                            value: t.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 10, height: 10,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                      color: Color(t.color), shape: BoxShape.circle),
                                ),
                                Text(t.name,
                                    style: GoogleFonts.poppins(fontSize: 14)),
                              ],
                            ),
                          )),
                    ],
                    selectedItemBuilder: (context) {
                      final validTypes =
                          _types.where((t) => t.name != 'Autre' && t.id.isNotEmpty).toList();
                      final allIds = <String?>[null, ...validTypes.map((t) => t.id)];
                      return allIds.map((id) {
                        final name = id == null
                            ? 'Autre'
                            : validTypes
                                .firstWhere((t) => t.id == id,
                                    orElse: () =>
                                        IngredientType(id: '', name: 'Autre', color: 0))
                                .name;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Catégorie (optionnel)',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: Colors.grey[500])),
                            Text(name,
                                style:
                                    GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                          ],
                        );
                      }).toList();
                    },
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
}
