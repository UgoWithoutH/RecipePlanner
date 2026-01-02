import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseIngredientRepository {
  final CollectionReference _ingredients =
      FirebaseFirestore.instance.collection('ingredients');

  /// Fetch all ingredients or those starting with a specific query
  Future<List<Map<String, String>>> searchIngredients(String query) async {
    final snap = await _ingredients
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .get();

    return snap.docs
        .map((doc) => {'id': doc.id, 'name': doc.get('name') as String})
        .toList();
  }

  /// Get the ID of an existing ingredient, or create it if it doesn't exist
  Future<String> getOrCreateIngredientId(String name) async {
    final query = await _ingredients.where('name', isEqualTo: name).limit(1).get();
    if (query.docs.isNotEmpty) return query.docs.first.id;

    final doc = await _ingredients.add({'name': name});
    return doc.id;
  }
}