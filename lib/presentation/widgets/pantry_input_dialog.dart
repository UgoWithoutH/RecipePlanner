import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Controller for the "new item" input
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  Unit _selectedUnit = Unit.piece;
  String _selectedId = '';

  int? _editingIndex; // Track which item is being edited (null = adding new)

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    _quantityController.text = '1';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _addOrUpdateItem() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final quantity = double.tryParse(_quantityController.text) ?? 1.0;
    
    final newItem = RecipeIngredient(
      ingredient: Ingredient(id: _selectedId, name: name),
      quantity: quantity,
      unit: _selectedUnit,
    );

    setState(() {
      if (_editingIndex != null) {
        // Update existing
        _items[_editingIndex!] = newItem;
        _editingIndex = null; // Exit edit mode
      } else {
        // Add new
        _items.add(newItem);
      }

      // Reset inputs
      _nameController.clear();
      _quantityController.text = '1';
      _selectedUnit = Unit.piece;
      _selectedId = '';
    });
  }

  void _editItem(int index) {
    final item = _items[index];
    setState(() {
      _editingIndex = index;
      _nameController.text = item.ingredient.name;
      _selectedId = item.ingredient.id;
      _quantityController.text = item.quantity.toString().replaceAll(RegExp(r'\.0$'), '');
      _selectedUnit = item.unit;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
      _nameController.clear();
      _quantityController.text = '1';
      _selectedUnit = Unit.piece;
      _selectedId = '';
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      if (_editingIndex == index) {
        _cancelEdit();
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // --- Header ---
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withOpacity(0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.kitchen,
                        color: Color(0xFF6A5AE0), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mon Frigo / Placard',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          'Ajoutez ce que vous avez déjà',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),

            // --- Scrollable Content ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _editingIndex != null ? 'Modifier l\'ingrédient' : 'Ajouter un ingrédient',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              if (_editingIndex != null)
                                TextButton(
                                  onPressed: _cancelEdit,
                                  child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Autocomplete Field
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Autocomplete<Map<String, String>>(
                                optionsBuilder: (textEditingValue) {
                                  return IngredientAutocomplete
                                      .suggestIngredients(
                                          textEditingValue.text);
                                },
                                displayStringForOption: (option) =>
                                    option['name']!,
                                onSelected: (option) {
                                  setState(() {
                                    _nameController.text = option['name']!;
                                    _selectedId = option['id']!;
                                  });
                                },
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  // Sync controllers manually if needed
                                  if (controller.text != _nameController.text) {
                                    controller.text = _nameController.text;
                                    // Move cursor to end
                                    controller.selection =
                                        TextSelection.fromPosition(TextPosition(
                                            offset: controller.text.length));
                                  }
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    onChanged: (val) {
                                      _nameController.text = val;
                                      _selectedId = ''; // Clear ID on manual edit
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Pommes, Riz, Lait...',
                                      hintStyle: GoogleFonts.poppins(
                                          color: Colors.grey[400]),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      prefixIcon: Icon(Icons.search,
                                          color: Colors.grey[400], size: 20),
                                    ),
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  );
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 8,
                                      shadowColor: Colors.black12,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: constraints.maxWidth,
                                        constraints: const BoxConstraints(
                                            maxHeight: 200),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (BuildContext context,
                                              int index) {
                                            final option =
                                                options.elementAt(index);
                                            return ListTile(
                                              title: Text(
                                                option['name'] ?? '',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 14),
                                              ),
                                              onTap: () => onSelected(option),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              hoverColor: Colors.grey[50],
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
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Quantity
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _quantityController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Qté',
                                    labelStyle: GoogleFonts.poppins(
                                        color: Colors.grey[500], fontSize: 13),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Unit Dropdown
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<Unit>(
                                      value: _selectedUnit,
                                      icon: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.grey[500]),
                                      isExpanded: true,
                                      items: Unit.values.map((u) {
                                        return DropdownMenuItem(
                                          value: u,
                                          child: Text(
                                            u.label,
                                            style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Colors.black87),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null)
                                          setState(() => _selectedUnit = val);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _addOrUpdateItem,
                            icon: Icon(_editingIndex != null ? Icons.save_rounded : Icons.add_circle_outline_rounded, size: 20),
                            label: Text(
                              _editingIndex != null ? 'Mettre à jour' : 'Ajouter à ma liste',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16), // Reduced spacing

                    // List Header
                    Row(
                      children: [
                        Text(
                          'Ingrédients ajoutés',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A5AE0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_items.length}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6A5AE0),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // List Items
                    if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(Icons.shopping_basket_outlined,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'Votre liste est vide',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          // Format quantity nicely (remove .0 if integer)
                          final qtyStr =
                              item.quantity.toString().replaceAll(RegExp(r'\.0$'), '');
                          
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.withOpacity(0.15)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    const Color(0xFF6A5AE0).withOpacity(0.1),
                                child: Text(
                                  item.ingredient.name.isNotEmpty
                                      ? item.ingredient.name[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF6A5AE0),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                item.ingredient.name,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              subtitle: Text(
                                '$qtyStr ${item.unit.label}',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                                    onPressed: () => _editItem(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        color: Colors.redAccent),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            // --- Bottom Validation Bar ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // If we are editing, finish the edit first
                    if (_editingIndex != null) {
                       _addOrUpdateItem();
                       // Then return
                       Navigator.pop(context, _items);
                       return;
                    }
                    
                    // Check if there is pending text in the input
                    // We also count pending item in the button label logic below
                    final pendingName = _nameController.text.trim();
                    final allItems = List<RecipeIngredient>.from(_items);

                    if (pendingName.isNotEmpty && _editingIndex == null) {
                      // Auto-add the pending item
                      final qty =
                          double.tryParse(_quantityController.text) ?? 1.0;
                      allItems.add(RecipeIngredient(
                        ingredient:
                            Ingredient(id: _selectedId, name: pendingName),
                        quantity: qty,
                        unit: _selectedUnit,
                      ));
                    }
                    Navigator.pop(context, allItems);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0), // Changed to Purple (complementary) instead of black
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Builder(
                    builder: (context) {
                      final pendingCount = _nameController.text.trim().isNotEmpty ? 1 : 0;
                      return Text(
                        'Valider ma liste (${_items.length + pendingCount})',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      );
                    }
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

