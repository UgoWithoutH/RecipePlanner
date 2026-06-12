import 'package:cloud_firestore/cloud_firestore.dart';
import 'group_repository.dart';

class FirebaseIngredientRepository {
  final CollectionReference _ingredients =
      FirebaseFirestore.instance.collection('ingredients');

  static final Map<String, List<Map<String, dynamic>>> _cache = {};

  static void invalidateCache() => _cache.clear();

  Future<String?> _getGroupId() async {
    return GroupRepository.instance.getCurrentGroupId();
  }

  /// Retourne tous les ingrédients du groupe (avec cache).
  Future<List<Map<String, dynamic>>> getAllIngredients() async {
    final groupId = await _getGroupId();
    if (groupId == null) return [];
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    final snap = await _ingredients.where('groupId', isEqualTo: groupId).get();
    final result = snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return <String, dynamic>{
        'id': doc.id,
        'name': data['name'],
        'typeId': data.containsKey('typeId') ? data['typeId'] : null,
        'usageCount': (data['usageCount'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    _cache[groupId] = result;
    return result;
  }

  /// Retourne l'ingrédient (id, name, typeId) correspondant à un nom (non sensible à la casse), ou null si absent
  Future<Map<String, String>?> getIngredientByNameCaseInsensitive(String name) async {
    final groupId = await _getGroupId();
    if (groupId == null) return null;
    final snap = await _ingredients
        .where('groupId', isEqualTo: groupId)
        .get();
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

  /// Fetch all ingredients or those starting with a specific query
  Future<List<Map<String, String>>> searchIngredients(String query) async {
    final groupId = await _getGroupId();
    if (groupId == null) return [];
    final snap = await _ingredients
        .where('groupId', isEqualTo: groupId)
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uF8FF')
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
    final groupId = await _getGroupId();
    if (groupId == null) throw Exception('Pas de groupe assigné.');
    final query = await _ingredients
        .where('groupId', isEqualTo: groupId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) return query.docs.first.id;

    final doc = await _ingredients.add({'name': name, 'groupId': groupId});
    invalidateCache();
    return doc.id;
  }

  /// Returns the ID of an existing ingredient (case-insensitive), or creates it with the given typeId.
  Future<String> createIngredientWithType(String name, String? typeId) async {
    final groupId = await _getGroupId();
    if (groupId == null) throw Exception('Pas de groupe assigné.');
    // Check if an ingredient with the same name (case-insensitive) already exists
    final snap = await _ingredients
        .where('groupId', isEqualTo: groupId)
        .get();
    final lowerName = name.trim().toLowerCase();
    for (final doc in snap.docs) {
      final docName = (doc.get('name') as String?)?.toLowerCase();
      if (docName == lowerName) return doc.id;
    }
    final data = <String, dynamic>{'name': name, 'groupId': groupId};
    if (typeId != null) {
      data['typeId'] = typeId;
    }
    final doc = await _ingredients.add(data);
    invalidateCache();
    return doc.id;
  }
}