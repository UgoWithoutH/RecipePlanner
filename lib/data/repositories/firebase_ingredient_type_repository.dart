import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/ingredient_type.dart';
import 'group_repository.dart';

class FirebaseIngredientTypeRepository {
  final CollectionReference _types =
      FirebaseFirestore.instance.collection('ingredient_types');

  /// In-memory cache: groupId -> sorted list of types.
  static final Map<String, List<IngredientType>> _cache = {};

  /// Clears the cache (call after add/update/delete).
  static void invalidateCache() => _cache.clear();

  Future<String?> _getGroupId() async {
    return GroupRepository.instance.getCurrentGroupId();
  }

  Future<List<IngredientType>> getTypes() async {
    final groupId = await _getGroupId();
    if (groupId == null) return [];
    if (_cache.containsKey(groupId)) return _cache[groupId]!;

    final snapshot = await _types
        .where('groupId', isEqualTo: groupId)
        .get();
    final types = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return IngredientType.fromFirestore(doc.id, data);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cache[groupId] = types;
    return types;
  }

  Future<void> addType(String name, int color) async {
    final groupId = await _getGroupId();
    if (groupId == null) return;
    await _types.add({
      'name': name,
      'color': color,
      'groupId': groupId,
    });
    invalidateCache();
  }

  Future<void> updateType(String id, String name, int color) async {
    await _types.doc(id).update({
      'name': name,
      'color': color,
    });
    invalidateCache();
  }

  Future<void> deleteType(String id) async {
    await _types.doc(id).delete();
    invalidateCache();
  }
}
