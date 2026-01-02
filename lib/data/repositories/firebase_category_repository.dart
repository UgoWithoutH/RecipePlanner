import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart' show Category;

class FirebaseCategoryRepository {
  final CollectionReference _categories = FirebaseFirestore.instance.collection(
    'categories',
  );

  /// Fetch all categories from Firestore and convert to List<Map<String, String>>
  Future<List<Category>> getCategories() async {
    final snap = await _categories.get();

    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Category.fromFirestore(doc.id, data);
    }).toList();
  }

  /// Add a new category
  Future<void> addCategory(String name) async {
    await _categories.add({'name': name});
  }

  /// Update category name
  Future<void> updateCategory(String id, String newName) async {
    await _categories.doc(id).update({'name': newName});
  }

  /// Delete a category
  Future<void> deleteCategory(String id) async {
    await _categories.doc(id).delete();
  }
}
