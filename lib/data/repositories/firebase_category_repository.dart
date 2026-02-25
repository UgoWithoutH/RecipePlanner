import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart' show Category;

class FirebaseCategoryRepository {
  final CollectionReference _categories = FirebaseFirestore.instance.collection(
    'categories',
  );

  // ignore: unintended_html_in_doc_comment
  /// Fetch all categories from Firestore and convert to List<Map<String, String\u003c\u003e>>
  Future<List<Category>> getCategories() async {
    final snap = await _categories.orderBy('name').get();

    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Category.fromFirestore(doc.id, data);
    }).toList();
  }

  /// Add a new category
  Future<void> addCategory(String name, int color) async {
    await _categories.add({'name': name, 'color': color});
  }

  /// Update category name and potentially color.
  /// No propagation needed: recipes reference categories by ID, not by name.
  Future<void> updateCategory(String id, String newName, int color) async {
    await _categories.doc(id).update({'name': newName, 'color': color});
  }

  /// Delete a category
  Future<void> deleteCategory(String id) async {
    await _categories.doc(id).delete();
  }
}
