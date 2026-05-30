import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart' show Category;
import 'group_repository.dart';

class FirebaseCategoryRepository {
  final CollectionReference _categories = FirebaseFirestore.instance.collection(
    'categories',
  );

  static final Map<String, List<Category>> _cache = {};

  static void invalidateCache() => _cache.clear();

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    return groupId;
  }

  // ignore: unintended_html_in_doc_comment
  /// Fetch all categories from Firestore and convert to List<Map<String, String\u003c\u003e>>
  Future<List<Category>> getCategories() async {
    final groupId = await _getGroupId();
    if (_cache.containsKey(groupId)) return _cache[groupId]!;

    final snap = await _categories
        .where('groupId', isEqualTo: groupId)
        .get();

    final categories = snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Category.fromFirestore(doc.id, data);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    _cache[groupId] = categories;
    return categories;
  }

  /// Add a new category
  Future<void> addCategory(String name, int color) async {
    final groupId = await _getGroupId();
    await _categories.add({'name': name, 'color': color, 'groupId': groupId});
    invalidateCache();
  }

  /// Update category name and potentially color.
  /// No propagation needed: recipes reference categories by ID, not by name.
  Future<void> updateCategory(String id, String newName, int color) async {
    await _categories.doc(id).update({'name': newName, 'color': color});
    invalidateCache();
  }

  /// Delete a category
  Future<void> deleteCategory(String id) async {
    await _categories.doc(id).delete();
    invalidateCache();
  }
}
