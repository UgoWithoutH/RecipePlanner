import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/ingredient_type.dart';
import 'group_repository.dart';

class FirebaseIngredientTypeRepository {
  final CollectionReference _types =
      FirebaseFirestore.instance.collection('ingredient_types');

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    return groupId;
  }

  Future<List<IngredientType>> getTypes() async {
    final groupId = await _getGroupId();
    final snapshot = await _types
        .where('groupId', isEqualTo: groupId)
        .get();
    final types = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return IngredientType.fromFirestore(doc.id, data);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return types;
  }

  Future<void> addType(String name, int color) async {
    final groupId = await _getGroupId();
    await _types.add({
      'name': name,
      'color': color,
      'groupId': groupId,
    });
  }

  Future<void> updateType(String id, String name, int color) async {
    await _types.doc(id).update({
      'name': name,
      'color': color,
    });
  }

  Future<void> deleteType(String id) async {
    await _types.doc(id).delete();
  }
}
