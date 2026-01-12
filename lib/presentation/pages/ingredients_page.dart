import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/ingredient_name_cache.dart';

class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> {
  List<Map<String, dynamic>> _ingredients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    final snap =
        await FirebaseFirestore.instance.collection('ingredients').get();

    if (!mounted) return;
    setState(() {
      _ingredients = snap.docs
          .map((doc) => {
                'id': doc.id,
                'name': doc.get('name'),
              })
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _addIngredient() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ajouter un ingrédient'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(labelText: 'Nom de l\'ingrédient'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      final docRef = await FirebaseFirestore.instance
          .collection('ingredients')
          .add({'name': name});

      IngredientNameCache.instance.setName(docRef.id, name);
      _loadIngredients();
    }
  }

  Future<void> _editIngredientName(String id, String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier l\'ingrédient'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .update({'name': newName});

      IngredientNameCache.instance.setName(id, newName);
      _loadIngredients();
    }
  }

  Future<void> _deleteIngredient(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'ingrédient'),
        content:
            const Text('Voulez-vous vraiment supprimer cet ingrédient ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('ingredients')
          .doc(id)
          .delete();

      IngredientNameCache.instance.remove(id);
      _loadIngredients();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 HEADER STYLE IDENTICAL TO RECIPES PAGE
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ingrédients',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            // 🔹 LISTE
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _ingredients.length,
                      itemBuilder: (_, index) {
                        final ing = _ingredients[index];
                        final name = ing['name'] as String;
                        final id = ing['id'] as String;

                        return Card(
                          margin:
                              const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            title: Text(
                              name,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _editIngredientName(id, name),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () =>
                                      _deleteIngredient(id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // 🔹 Consistent FAB
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: FloatingActionButton(
          onPressed: _addIngredient,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}