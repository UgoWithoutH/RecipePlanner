// ignore_for_file: invalid_use_of_protected_member
part of 'create_recipe_page.dart';

extension _CreateRecipeIngredientDialogs on _CreateRecipePageState {
  Future<void> _addIngredient() async {
    if (_ingredientNameController.text.isEmpty ||
        _ingredientQuantityController.text.isEmpty ||
        _selectedIngredientUnit == null) {
      _showError('Remplissez tous les champs ingrédient');
      return;
    }

    String inputName = _ingredientNameController.text.trim();
    // Vérifie si un ingrédient avec le même nom existe déjà dans la recette (case-insensitive)
    final duplicate = _ingredients.any(
      (ri) => ri.ingredient.name.toLowerCase() == inputName.toLowerCase(),
    );
    if (duplicate) {
      _showError('Cet ingrédient a déjà été ajouté à la recette.');
      return;
    }

    String? id = _selectedIngredientId;
    String? selectedTypeId;
    String? existingTypeId;
    String nameToUse = inputName;

    // Check if ingredient exists
    if (id == null) {
      // Cherche l'ingrédient existant (non sensible à la casse)
      final existing = await _ingredientRepo.getIngredientByNameCaseInsensitive(
        inputName,
      );
      if (existing != null) {
        id = existing['id'];
        existingTypeId = existing['typeId'];
        nameToUse = existing['name'] ?? inputName;
      } else {
        // Prompt for type selection
        selectedTypeId = await _showTypeSelectionDialog(inputName);
        if (selectedTypeId == null) {
          // User cancelled
          return;
        }
        // Ajoute à la liste temporaire, id sera résolu à la sauvegarde
        final pending = PendingIngredient(
          name: inputName,
          typeId: selectedTypeId,
          quantity: parseQty(_ingredientQuantityController.text),
          unit: _selectedIngredientUnit!,
          notes: _ingredientNotesController.text.isEmpty
              ? null
              : _ingredientNotesController.text,
        );
        setState(() {
          _pendingIngredients.add(pending);
          _ingredients.add(
            RecipeIngredient(
              ingredient: Ingredient(
                id: '', // temporaire, sera remplacé à la sauvegarde
                name: inputName,
                typeId: selectedTypeId,
              ),
              quantity: pending.quantity,
              unit: pending.unit,
              notes: pending.notes,
            ),
          );
          _ingredientNameController.clear();
          _ingredientQuantityController.clear();
          _ingredientNotesController.clear();
          _selectedIngredientUnit = null;
          _selectedIngredientId = null;
        });
        return;
      }
    } else {
      // Si on a un id, on va chercher le type
      final existing = await _ingredientRepo.getIngredientByNameCaseInsensitive(
        inputName,
      );
      if (existing != null) {
        existingTypeId = existing['typeId'];
        nameToUse = existing['name'] ?? inputName;
      }
    }

    // Ajoute l'ingrédient existant (ou modifié) à la liste
    setState(() {
      _ingredients.add(
        RecipeIngredient(
          ingredient: Ingredient(
            id: id!,
            name: nameToUse,
            typeId: existingTypeId,
          ),
          quantity: parseQty(_ingredientQuantityController.text),
          unit: _selectedIngredientUnit!,
          notes: _ingredientNotesController.text.isEmpty
              ? null
              : _ingredientNotesController.text,
        ),
      );

      _ingredientNameController.clear();
      _ingredientQuantityController.clear();
      _ingredientNotesController.clear();
      _selectedIngredientUnit = null;
      _selectedIngredientId = null;
    });
  }

  // ── Delete confirmation sheet ─────────────────────────────────────────────

  Future<bool?> _showDeleteConfirmSheet({required String title, required String message}) {
    return showModalBottomSheet<bool>(
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
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Icône rouge
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit ingredient ────────────────────────────────────────────────────────

  Future<void> _showEditIngredientDialog(int index) async {
    final ingredient = _ingredients[index];
    final nameController = TextEditingController(text: ingredient.ingredient.name);
    final qtyController = TextEditingController(text: fmtQty(ingredient.quantity));
    final notesController = TextEditingController(text: ingredient.notes ?? '');
    Unit selectedUnit = ingredient.unit;
    String resolvedId = ingredient.ingredient.id;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget inputBox({
              required TextEditingController ctrl,
              required String hint,
              TextInputType? inputType,
              List<TextInputFormatter>? formatters,
            }) =>
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: ctrl,
                    keyboardType: inputType,
                    inputFormatters: formatters,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: GoogleFonts.poppins(
                          color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                );

            return Padding(
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
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF6A5AE0)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Modifier l\'ingrédient',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Nom avec autocomplete
                  Autocomplete<Map<String, String>>(
                    initialValue: TextEditingValue(text: nameController.text),
                    optionsBuilder: (tv) async {
                      final q = tv.text.trim();
                      if (q.isEmpty) return [];
                      return await IngredientAutocomplete.suggestIngredients(q);
                    },
                    displayStringForOption: (o) => o['name']!,
                    fieldViewBuilder: (ctx2, ctrl, fn, _) {
                      ctrl.addListener(() {
                        nameController.text = ctrl.text;
                        resolvedId = '';
                      });
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: ctrl,
                          focusNode: fn,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: InputBorder.none,
                            hintText: 'Nom de l\'ingrédient',
                            hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                          ),
                        ),
                      );
                    },
                    optionsViewBuilder: (ctx2, onSel, opts) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            children: opts.map((o) => ListTile(
                              dense: true,
                              title: Text(o['name']!, style: GoogleFonts.poppins(fontSize: 13)),
                              onTap: () => onSel(o),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                    onSelected: (o) {
                      nameController.text = o['name']!;
                      resolvedId = o['id'] ?? '';
                    },
                  ),
                  const SizedBox(height: 12),
                  // Quantité + Unité
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: inputBox(
                          ctrl: qtyController,
                          hint: 'Qté',
                          inputType: const TextInputType.numberWithOptions(decimal: true),
                          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
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
                              items: Unit.values.map((u) => DropdownMenuItem<Unit>(
                                value: u,
                                child: Text(u.label, style: GoogleFonts.poppins(fontSize: 14)),
                              )).toList(),
                              onChanged: (u) { if (u != null) setStateDialog(() => selectedUnit = u); },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  inputBox(ctrl: notesController, hint: 'Préparation (ex: finement haché)'),
                  const SizedBox(height: 16),
                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final newName = nameController.text.trim();
                            final newQty = parseQty(qtyController.text, fallback: ingredient.quantity);
                            if (newName.isEmpty) return;
                            setState(() {
                              _ingredients[index] = RecipeIngredient(
                                ingredient: ingredient.ingredient.copyWith(name: newName, id: resolvedId),
                                quantity: newQty,
                                unit: selectedUnit,
                                notes: notesController.text.isEmpty ? null : notesController.text,
                              );
                              final pIdx = _pendingIngredients.indexWhere(
                                  (p) => p.name == ingredient.ingredient.name);
                              if (pIdx != -1) {
                                final old = _pendingIngredients[pIdx];
                                _pendingIngredients[pIdx] = PendingIngredient(
                                  name: newName,
                                  typeId: old.typeId,
                                  quantity: newQty,
                                  unit: selectedUnit,
                                  notes: notesController.text.isEmpty ? null : notesController.text,
                                );
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6A5AE0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Enregistrer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Edit instruction ─────────────────────────────────────────────────────────

  Future<String?> _showTypeSelectionDialog(String ingredientName) async {
    String? selectedTypeId;
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Nouveau ingrédient',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L\'ingrédient "$ingredientName" n\'existe pas. Sélectionnez un type pour le créer.',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                const SizedBox(height: 20),
                Text(
                  'Type',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedTypeId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Aucun type',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    ),
                    ..._ingredientTypes.map((type) {
                      return DropdownMenuItem(
                        value: type.id,
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Color(type.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(type.name, style: GoogleFonts.poppins()),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) =>
                      setStateDialog(() => selectedTypeId = val),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(
                  'Annuler',
                  style: GoogleFonts.poppins(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, selectedTypeId),
                child: Text(
                  'Créer',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6A5AE0),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
