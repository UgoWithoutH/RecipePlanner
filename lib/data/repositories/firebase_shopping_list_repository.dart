import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/shopping_list.dart';
import 'group_repository.dart';

class FirebaseShoppingListRepository {
  final CollectionReference _collection =
      FirebaseFirestore.instance.collection('shopping_lists');

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    return groupId;
  }

  Future<void> saveShoppingList(ShoppingList shoppingList) async {
    final groupId = await _getGroupId();
    final data = shoppingList.toMap();
    data['groupId'] = groupId;
    await _collection.doc(shoppingList.id).set(data);
  }

  Future<ShoppingList?> getShoppingListByMealPlanId(String mealPlanId) async {
    final groupId = await _getGroupId();
    final querySnapshot = await _collection
        .where('groupId', isEqualTo: groupId)
        .where('mealPlanId', isEqualTo: mealPlanId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      return ShoppingList.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    }
    return null;
  }
  
  Stream<ShoppingList?> streamShoppingListByMealPlanId(String mealPlanId) async* {
    final groupId = await _getGroupId();
    yield* _collection
        .where('groupId', isEqualTo: groupId)
        .where('mealPlanId', isEqualTo: mealPlanId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final doc = snapshot.docs.first;
            return ShoppingList.fromMap(doc.id, doc.data() as Map<String, dynamic>);
          }
          return null;
        });
  }

  Future<void> updateShoppingItem(String listId, ShoppingItem item) async {
    // This is tricky with Firestore array updates if we don't have unique IDs for items.
    // However, since we're just updating the whole list often, or we can just replace the whole array.
    // Given the structure, likely easiest to read -> modify -> save the whole list for now.
    // Or, more efficiently, if we knew the index. But for a shopping list (~20-50 items) reading and writing the doc is fine.
    
    // Actually, let's expose updateShoppingList which takes the whole list.
  }

  /// Update typeId for all shopping list items referencing a given ingredient name
  Future<void> updateShoppingItemsTypeForIngredient(String ingredientName, String? newTypeId) async {
    final groupId = await _getGroupId();
    final snapshot = await _collection
        .where('groupId', isEqualTo: groupId)
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final list = ShoppingList.fromMap(doc.id, data);
      bool updated = false;
      final updatedItems = list.items.map((item) {
        if (item.name.trim().toLowerCase() == ingredientName.trim().toLowerCase()) {
          updated = true;
          return item.copyWith(typeId: newTypeId);
        }
        return item;
      }).toList();
      if (updated) {
        final updatedList = list.copyWith(items: updatedItems);
        await saveShoppingList(updatedList);
      }
    }
  }
}
