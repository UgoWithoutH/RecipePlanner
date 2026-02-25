import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/ingredient_type.dart';

class FirebaseIngredientTypeRepository {
  final CollectionReference _types =
      FirebaseFirestore.instance.collection('ingredient_types');

  Future<List<IngredientType>> getTypes() async {
    final snapshot = await _types.orderBy('name').get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return IngredientType.fromFirestore(doc.id, data);
    }).toList();
  }

  Future<void> addType(String name, int color) async {
    await _types.add({
      'name': name,
      'color': color,
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
