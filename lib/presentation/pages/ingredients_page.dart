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
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFEFFC), Colors.white], // Very subtle purple fading to white
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.maybePop(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04), 
                                blurRadius: 4, 
                                offset: const Offset(0, 2)
                              )
                            ]
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Ingredients',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100),
                          itemCount: _ingredients.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final ing = _ingredients[index];
                            final name = ing['name'] as String;
                            final id = ing['id'] as String;

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.06),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                title: Text(
                                  name,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: const Color(0xFF2D2D2D),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent),
                                      onPressed: () => _editIngredientName(id, name),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                      onPressed: () => _deleteIngredient(id),
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
        ],
      ),

      // FAB
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          elevation: 6,
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFF6A5AE0),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A5AE0).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _addIngredient,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Add',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}