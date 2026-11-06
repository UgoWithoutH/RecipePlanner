// ignore_for_file: invalid_use_of_protected_member
part of 'fridge_pantry_page.dart';

extension _FridgePantryForm on _FridgePantryPageState {
  Future<void> _confirmDeleteAll() async {
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
              child: Icon(Icons.delete_sweep_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text('Tout vider ?',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous supprimer tous les articles du frigo / placard ?',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
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
                child: Text('Tout vider', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
              )),
            ]),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteAll();
      if (!mounted) return;
      setState(() => _items.clear());
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Form sheet (add / edit)
  // ---------------------------------------------------------------------------

  Widget _buildFormSheet(BuildContext ctx) {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _editingItem != null
                      ? 'Modifier l\'article'
                      : 'Ajouter un article',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 20),
                // Autocomplete ingredient name
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<Map<String, String>>(
                      optionsBuilder: (textEditingValue) =>
                          IngredientAutocomplete.suggestIngredients(
                              textEditingValue.text),
                      displayStringForOption: (option) => option['name']!,
                      onSelected: (option) {
                        setSheetState(() {
                          _nameController.text = option['name']!;
                          _selectedIngredientId = option['id']!;
                          _selectedTypeId = '';
                          _selectedTypeName = '';
                        });
                        final ingId = option['id']!;
                        if (ingId.isNotEmpty) {
                          FirebaseFirestore.instance
                              .collection('ingredients')
                              .doc(ingId)
                              .get()
                              .then((doc) {
                            if (!doc.exists) return;
                            final typeId =
                                (doc.data())?['typeId'] as String? ?? '';
                            if (typeId.isEmpty) return;
                            final type = _typesById[typeId];
                            if (type != null && mounted) {
                              setSheetState(() {
                                _selectedTypeId = typeId;
                                _selectedTypeName = type.name;
                              });
                            }
                          }).catchError((_) {});
                        }
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        if (controller.text != _nameController.text) {
                          controller.text = _nameController.text;
                          controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length));
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (val) {
                            _nameController.text = val;
                            _selectedIngredientId = '';
                          },
                          decoration: InputDecoration(
                            hintText: 'Pommes, Riz, Lait...',
                            hintStyle:
                                GoogleFonts.poppins(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
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
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8,
                            shadowColor: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: constraints.maxWidth,
                              constraints:
                                  const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Text(
                                        option['name']!,
                                        style: GoogleFonts.poppins(
                                            fontSize: 14),
                                      ),
                                    ),
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
                if (_selectedTypeName.isNotEmpty) ...[  
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(Icons.label_rounded,
                          size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(
                        'Catégorie : $_selectedTypeName',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Quantity + Unit row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Quantité',
                          hintStyle:
                              GoogleFonts.poppins(color: Colors.grey[400]),
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
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Unit>(
                            value: _selectedUnit,
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
                            onChanged: (u) => setSheetState(() => _selectedUnit = u ?? Unit.piece),
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
                const SizedBox(height: 16),
                // Urgent toggle
                GestureDetector(
                  onTap: () =>
                      setSheetState(() => _formIsUrgent = !_formIsUrgent),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _formIsUrgent
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _formIsUrgent
                            ? Colors.orange.shade300
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _formIsUrgent
                              ? Icons.local_fire_department_rounded
                              : Icons.local_fire_department_outlined,
                          color: _formIsUrgent
                              ? Colors.orange[700]
                              : Colors.grey[400],
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Utiliser en priorité',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _formIsUrgent
                                      ? Colors.orange[800]
                                      : const Color(0xFF1A1A1A),
                                ),
                              ),
                              Text(
                                'L\'algorithme privilégiera les recettes\nqui utilisent cet ingrédient.',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: _formIsUrgent
                                      ? Colors.orange[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _formIsUrgent,
                          onChanged: (v) =>
                              setSheetState(() => _formIsUrgent = v),
                          activeColor: Colors.orange[700],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Save button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _editingItem != null ? 'Enregistrer' : 'Ajouter',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
