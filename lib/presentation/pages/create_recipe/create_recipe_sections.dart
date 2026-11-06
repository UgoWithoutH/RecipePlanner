// ignore_for_file: invalid_use_of_protected_member
part of 'create_recipe_page.dart';

extension _CreateRecipeSections on _CreateRecipePageState {
  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ingrédients',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        // Add Form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Autocomplete<Map<String, String>>(
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  final query = textEditingValue.text.trim();
                  if (query.isEmpty) return <Map<String, String>>[];
                  // Use the centralized suggestion logic
                  return await IngredientAutocomplete.suggestIngredients(query);
                },
                displayStringForOption: (option) => option['name']!,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (controller.text != _ingredientNameController.text) {
                          controller.value = TextEditingValue(
                            text: _ingredientNameController.text,
                          );
                        }
                      });
                      controller.addListener(() {
                        _ingredientNameController.value = controller.value;
                        // Dès que l'utilisateur modifie le champ, on réinitialise l'id sélectionné
                        _selectedIngredientId = null;
                      });
                      return _buildModernInput(
                        controller,
                        'Nom (ex: Farine)',
                        focusNode: focusNode,
                      );
                    },
                onSelected: (selectedIngredient) {
                  _ingredientNameController.text = selectedIngredient['name']!;
                  _selectedIngredientId = selectedIngredient['id'];
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildModernInput(
                      _ingredientQuantityController,
                      'Qté',
                      inputType: TextInputType.number,
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
                          value: _selectedIngredientUnit,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                          dropdownColor: Colors.white,
                          hint: Text('Unité', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400])),
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
                          onChanged: (u) => setState(() => _selectedIngredientUnit = u),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.small(
                    onPressed: _addIngredient,
                    backgroundColor: const Color(0xFF6A5AE0),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildModernInput(
                _ingredientNotesController,
                'Préparation (ex: finement haché)',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _ingredients.isEmpty
            ? Text(
                'Aucun ingrédient ajouté',
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Column(
                children: _ingredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ingredient = entry.value;
                  // Cherche le type associé à l'ingrédient
                  final type = _ingredientTypes.firstWhere(
                    (t) => t.id == ingredient.ingredient.typeId,
                    orElse: () =>
                        IngredientType(id: '', name: '', color: 0xFFBDBDBD),
                  );
                  final hasType =
                      ingredient.ingredient.typeId != null &&
                      type.id.isNotEmpty;
                  // Couleur logique similaire aux catégories
                  final typeColor = Color(type.color).withOpacity(0.15);
                  final hsl = HSLColor.fromColor(Color(type.color));
                  final startLightness = hsl.lightness;
                  final textLightness = startLightness > 0.4
                      ? 0.4
                      : startLightness;
                  final textColor = hsl.withLightness(textLightness).toColor();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[100]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6A5AE0),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      ingredient.ingredient.name,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if (hasType) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: typeColor,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: Color(type.color),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              type.name,
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                                color: textColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    Text(
                                      '- ${fmtQty(ingredient.quantity)} ${ingredient.unit.label}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                if (ingredient.notes != null &&
                                    ingredient.notes!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      ingredient.notes!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _showEditIngredientDialog(index),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6A5AE0).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6A5AE0)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () async {
                                  final confirm = await _showDeleteConfirmSheet(
                                    title: 'Supprimer l\'ingrédient',
                                    message: 'Voulez-vous vraiment supprimer "${_ingredients[index].ingredient.name}" ?',
                                  );
                                  if (confirm == true) setState(() => _ingredients.removeAt(index));
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[400]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildInstructionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Instructions',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        // Inline add form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: _instructionController,
                    minLines: 3,
                    maxLines: 6,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87, height: 1.6),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                      hintText: 'Décrivez l\'étape ${_instructions.length + 1}...',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'addInstruction',
                onPressed: () {
                  final text = _instructionController.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    _instructions.add(text);
                    _instructionController.clear();
                  });
                },
                backgroundColor: const Color(0xFF6A5AE0),
                foregroundColor: Colors.white,
                elevation: 0,
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (_instructions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.format_list_numbered_rounded, size: 32, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    'Aucune étape ajoutée',
                    style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: _instructions.asMap().entries.map((entry) {
              final index = entry.key;
              final instruction = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[100]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF6A5AE0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          instruction,
                          style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _showEditInstructionDialog(index),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6A5AE0).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6A5AE0)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final confirm = await _showDeleteConfirmSheet(
                                title: 'Supprimer l\'étape',
                                message: 'Voulez-vous vraiment supprimer l\'étape ${index + 1} ?',
                              );
                              if (confirm == true) {
                                setState(() => _instructions.removeAt(index));
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[400]),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
