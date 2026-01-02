import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Load all ingredients from Firestore
  Future<void> _loadIngredients() async {
    final snap = await FirebaseFirestore.instance.collection('ingredients').get();
    final ingredients = snap.docs.map((doc) {
      return {
        'id': doc.id,
        'name': doc.get('name'), // keep as dynamic
      };
    }).toList();

    setState(() {
      _ingredients = ingredients;
      _isLoading = false;
    });
  }

  // Add a new ingredient
  Future<void> _addIngredient() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Ingredient'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Ingredient Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();

      // Add to Firestore
      final docRef = await FirebaseFirestore.instance.collection('ingredients').add({'name': name});

      // Add to cache
      IngredientNameCache.instance.setName(docRef.id, name);

      // Refresh list
      _loadIngredients();
    }
  }

  // Edit ingredient name
  Future<void> _editIngredientName(String id, String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Ingredient Name'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();

      // Update Firestore
      await FirebaseFirestore.instance.collection('ingredients').doc(id).update({'name': newName});

      // Update local cache
      IngredientNameCache.instance.setName(id, newName);

      // Refresh list
      _loadIngredients();
    }
  }

  // Delete ingredient
  Future<void> _deleteIngredient(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Ingredient'),
        content: const Text('Are you sure you want to delete this ingredient?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('ingredients').doc(id).delete();

      // Remove from cache
      IngredientNameCache.instance.remove(id);

      // Refresh list
      _loadIngredients();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('Ingredients')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _ingredients.length,
        itemBuilder: (context, index) {
          final ing = _ingredients[index];
          final name = ing['name'] as String;
          final id = ing['id'] as String;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              title: Text(name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editIngredientName(id, name),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteIngredient(id),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addIngredient,
        child: const Icon(Icons.add),
      ),
    );
  }
}