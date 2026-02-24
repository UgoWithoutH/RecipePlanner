import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/unit.dart';
import '../../../domain/entities/ingredient.dart';
import '../../../domain/entities/recipe_ingredient.dart';
import 'ingredient_autocomplete.dart';

class PantryInputDialog extends StatefulWidget {
  final List<RecipeIngredient> initialItems;

  const PantryInputDialog({
    super.key,
    this.initialItems = const [],
  });

  @override
  State<PantryInputDialog> createState() => _PantryInputDialogState();
}

class _PantryInputDialogState extends State<PantryInputDialog> {
  late List<RecipeIngredient> _items;
  // Temporary storage for the "new" ingredient being typed
  RecipeIngredient _newItem = RecipeIngredient(
    ingredient: Ingredient(id: '', name: ''),
    quantity: 1,
    unit: Unit.piece,
  );

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
  }

  void _addNewItem() {
    if (_newItem.ingredient.name.trim().isEmpty) return;

    setState(() {
      _items.add(_newItem);
      // Reset the "new" item to a clean state
      _newItem = RecipeIngredient(
        ingredient: Ingredient(id: '', name: ''),
        quantity: 1,
        unit: Unit.piece,
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _updateItem(int index, RecipeIngredient newItem) {
    setState(() {
      _items[index] = newItem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mes Ingrédients (Frigo / Placard)',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Renseignez ici ce que vous avez déjà pour réduire la liste de courses.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            // Header for Input Area
            Text(
              'Ajouter un ingrédient',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6A5AE0),
              ),
            ),
            const SizedBox(height: 8),
            // The "Input Row" is always present at the top
            Container(
              // Removed background decoration as per user request
              child: Row(
                children: [
                  Expanded(
                    child: _PantryItemRow(
                      // Use a special key for the input row so it rebuilds/clears on add
                      key: ValueKey('input_row_${_items.length}'), 
                      item: _newItem,
                      onChanged: (val) {
                        // Update the temporary new item state
                        _newItem = val;
                      },
                      onDelete: () {}, // No delete button for the input row
                      isInputRow: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _addNewItem,
                    backgroundColor: const Color(0xFF6A5AE0),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ingrédients ajoutés (${_items.length})',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        'Aucun ingrédient ajouté',
                        style: GoogleFonts.poppins(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _PantryItemRow(
                          key: ValueKey('pantry_item_$index'), 
                          item: item,
                          onChanged: (newItem) => _updateItem(index, newItem),
                          onDelete: () => _removeItem(index),
                          isInputRow: false,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                      // Auto-add the input row if it has content
                      final pending = _newItem;
                      final allItems = List<RecipeIngredient>.from(_items);
                      if (pending.ingredient.name.trim().isNotEmpty) {
                        allItems.add(pending);
                      }
                      Navigator.pop(context, allItems);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Valider'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PantryItemRow extends StatefulWidget {
  final RecipeIngredient item;
  final ValueChanged<RecipeIngredient> onChanged;
  final VoidCallback onDelete;
  final bool isInputRow;

  const _PantryItemRow({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    this.isInputRow = false,
  });

  @override
  State<_PantryItemRow> createState() => _PantryItemRowState();
}

class _PantryItemRowState extends State<_PantryItemRow> {
  // Local mutable copy — always in sync, avoids stale closure issues
  late RecipeIngredient _local;

  @override
  void initState() {
    super.initState();
    _local = widget.item;
  }

  @override
  void didUpdateWidget(_PantryItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent resets the row (e.g. after add), sync local state
    if (widget.item != oldWidget.item) {
      _local = widget.item;
    }
  }

  void _update(RecipeIngredient updated) {
    setState(() => _local = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name — autocomplete
        Expanded(
          flex: 3,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Autocomplete<Map<String, String>>(
                initialValue: TextEditingValue(text: _local.ingredient.name),
                optionsBuilder: (textEditingValue) {
                  return IngredientAutocomplete.suggestIngredients(
                      textEditingValue.text);
                },
                displayStringForOption: (option) => option['name']!,
                onSelected: (option) {
                  // Use _local (always current) to preserve quantity/unit
                  final updated = _local.copyWith(
                    ingredient: _local.ingredient.copyWith(
                      id: option['id'],
                      name: option['name'],
                    ),
                  );
                  _update(updated);
                },
                fieldViewBuilder:
                    (context, acController, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: acController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      final updated = _local.copyWith(
                        ingredient: _local.ingredient.copyWith(
                          id: '',
                          name: val,
                        ),
                      );
                      _update(updated);
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                          maxHeight: 200,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option['name'] ?? ''),
                              onTap: () => onSelected(option),
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        // Quantity
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: _local.quantity.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Qté',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (val) {
              final q = double.tryParse(val) ?? 0;
              _update(_local.copyWith(quantity: q));
            },
          ),
        ),
        const SizedBox(width: 8),
        // Unit
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<Unit>(
            value: _local.unit,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            isExpanded: true,
            items: Unit.values.map((u) {
              return DropdownMenuItem(value: u, child: Text(u.label));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                _update(_local.copyWith(unit: val));
              }
            },
          ),
        ),
        if (!widget.isInputRow)
          IconButton(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete, color: Colors.red),
          ),
      ],
    );
  }
}
