// ignore_for_file: invalid_use_of_protected_member
part of 'ingredients_page.dart';

extension _IngredientsCrud on _IngredientsPageState {
  Future<void> _addIngredient() async {
    final controller = TextEditingController();
    String? selectedTypeId;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Ajouter un ingrédient',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom de l\'ingrédient',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Type',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedTypeId,
                decoration: InputDecoration(
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: [
                   DropdownMenuItem<String>(
                    value: null,
                    child: Text('Aucun type', style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                  ..._types.map((type) {
                  return DropdownMenuItem(
                    value: type.id,
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                              color: Color(type.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(type.name, style: GoogleFonts.poppins()),
                      ],
                    ),
                  );
                })],
                onChanged: (val) => setStateDialog(() => selectedTypeId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler',
                    style: GoogleFonts.poppins(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Ajouter',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0)))),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();

      // Check for duplicate name (case-insensitive)
      final alreadyExists = _ingredients.any(
        (ing) => (ing['name'] as String).toLowerCase() == name.toLowerCase(),
      );
      if (alreadyExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Un ingrédient avec ce nom existe déjà.',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final data = <String, dynamic>{'name': name};
      if (selectedTypeId != null) {
        data['typeId'] = selectedTypeId;
      }

      final gid = await GroupRepository.instance.getCurrentGroupId();
      if (gid != null) data['groupId'] = gid;
      final docRef = await FirebaseFirestore.instance
          .collection('ingredients')
          .add(data);

      IngredientNameCache.instance.setName(docRef.id, name);
      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }

  Future<void> _editIngredient(String id, String oldName, String? oldTypeId) async {
    final controller = TextEditingController(text: oldName);
    String? selectedTypeId = oldTypeId;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Modifier l\'ingrédient',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Type',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _types.any((t) => t.id == selectedTypeId)
                    ? selectedTypeId
                    : null,
                decoration: InputDecoration(
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: [
                   DropdownMenuItem<String>(
                    value: null,
                    child: Text('Aucun type', style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                  ..._types.map((type) {
                    return DropdownMenuItem(
                      value: type.id,
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                                color: Color(type.color), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(type.name, style: GoogleFonts.poppins()),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setStateDialog(() => selectedTypeId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler',
                    style: GoogleFonts.poppins(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Enregistrer',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0)))),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();

      // Check for duplicate name (case-insensitive), excluding the current ingredient
      final alreadyExists = _ingredients.any(
        (ing) =>
            ing['id'] != id &&
            (ing['name'] as String).toLowerCase() == newName.toLowerCase(),
      );
      if (alreadyExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Un ingrédient avec ce nom existe déjà.',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final updates = <String, dynamic>{'name': newName};
      updates['typeId'] = selectedTypeId; // Can be null to remove type

      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .update(updates);

      IngredientNameCache.instance.setName(id, newName);

      // Update all shopping list items with this ingredient's name
      // (Assumes shopping list items use the ingredient name as key)
      await _shoppingListRepo.updateShoppingItemsTypeForIngredient(newName, selectedTypeId);

      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }

  Future<void> _deleteIngredient(String id) async {
    // Vérifie si l'ingrédient est utilisé dans une recette du groupe
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId != null) {
      final recipesSnap = await FirebaseFirestore.instance
          .collection('recipes')
          .where('groupId', isEqualTo: groupId)
          .get();
      final isUsed = recipesSnap.docs.any((doc) {
        final ingredients = (doc.data()['ingredients'] as List<dynamic>? ?? []);
        return ingredients.any((i) => i['ingredientId'] == id);
      });
      if (isUsed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Impossible de supprimer : cet ingrédient est utilisé dans une ou plusieurs recettes du groupe.',
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    final confirm = await showModalBottomSheet<bool>(
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
            Text('Supprimer l\'ingrédient',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous vraiment supprimer cet ingrédient ?',
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
                child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
              )),
            ]),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .delete();

      IngredientNameCache.instance.remove(id);
      FirebaseIngredientRepository.invalidateCache();
      _loadIngredients();
    }
  }
}
