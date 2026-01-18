import 'package:flutter/material.dart';
import 'package:recipe_planner/domain/entities/category.dart';
import '../../data/repositories/firebase_category_repository.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();

  List<Category> _categories = []; // List of categories
  bool _isLoading = true; // Initial loading
  bool _isUpdating = false; // Inline loading for add/edit/delete

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// Load all categories from repository
  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final categories = await _categoryRepo.getCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  /// Add a new category
  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();

      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.addCategory(name);

      // Refresh the list after adding
      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  /// Edit category name
  Future<void> _editCategory(String id, String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit category'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();

      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.updateCategory(id, newName);

      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  /// Delete category
  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete category'),
        content: const Text('Do you really want to delete this category?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.deleteCategory(id);

      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Column(
        children: [
          // Inline loader for add/edit/delete actions
          if (_isUpdating)
            const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator()) // Full screen on initial load
                : _categories.isEmpty
                  ? const Center(child: Text('No categories yet'))
                  : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final name = cat.name;
                          final id = cat.id;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              title: Text(name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editCategory(id, name),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteCategory(id),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addCategory,
        child: const Icon(Icons.add),
      ),
    );
  }
}