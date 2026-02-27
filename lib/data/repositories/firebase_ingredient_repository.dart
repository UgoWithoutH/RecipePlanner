import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseIngredientRepository {
      /// Retourne l'ingrédient (id, name, typeId) correspondant à un nom (non sensible à la casse), ou null si absent
      Future<Map<String, String>?> getIngredientByNameCaseInsensitive(String name) async {
        final snap = await _ingredients.get();
        final lowerName = name.toLowerCase();
        for (final doc in snap.docs) {
          final docName = (doc.get('name') as String?)?.toLowerCase();
          if (docName == lowerName) {
            final data = doc.data() as Map<String, dynamic>?;
            return {
              'id': doc.id,
              'name': doc.get('name') as String,
              'typeId': (data != null && data.containsKey('typeId')) ? data['typeId'] as String : '',
            };
          }
        }
        return null;
      }
  final CollectionReference _ingredients =
      FirebaseFirestore.instance.collection('ingredients');

  /// Fetch all ingredients or those starting with a specific query
  Future<List<Map<String, String>>> searchIngredients(String query) async {
    final snap = await _ingredients
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .get();

    return snap.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return {
            'id': doc.id,
            'name': doc.get('name') as String,
            'typeId': (data != null && data.containsKey('typeId')) ? data['typeId'] as String : '',
          };
        })
        .toList();
  }


  /// Get the ID of an existing ingredient, or create it if it doesn't exist
  Future<String> getOrCreateIngredientId(String name) async {
    final query = await _ingredients.where('name', isEqualTo: name).limit(1).get();
    if (query.docs.isNotEmpty) return query.docs.first.id;

    final doc = await _ingredients.add({'name': name});
    return doc.id;
  }

  /// Create a new ingredient with a typeId
  Future<String> createIngredientWithType(String name, String? typeId) async {
    final data = {'name': name};
    if (typeId != null) {
      data['typeId'] = typeId;
    }
    final doc = await _ingredients.add(data);
    return doc.id;
  }
}