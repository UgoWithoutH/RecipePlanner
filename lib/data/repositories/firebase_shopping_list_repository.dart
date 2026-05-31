import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/shopping_list.dart';
import 'group_repository.dart';

class FirebaseShoppingListRepository {
  final CollectionReference _collection =
      FirebaseFirestore.instance.collection('shopping_lists');

  static ShoppingList? _cache;
  static String? _cacheGroupId;

  static void invalidateCache() {
    _cache = null;
    _cacheGroupId = null;
  }

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
    invalidateCache();
  }

  /// Retourne le document de liste de courses du groupe (un seul par groupe).
  Future<ShoppingList?> getGroupShoppingList() async {
    final groupId = await _getGroupId();
    if (_cacheGroupId == groupId && _cache != null) return _cache;
    final querySnapshot = await _collection
        .where('groupId', isEqualTo: groupId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      final result = ShoppingList.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      _cache = result;
      _cacheGroupId = groupId;
      return result;
    }
    _cache = null;
    _cacheGroupId = groupId;
    return null;
  }

  Future<ShoppingList?> getShoppingListByMealPlanId(String mealPlanId) async {
    return getGroupShoppingList();
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

  /// Deletes the shopping list document for the current group.
  Future<void> deleteGroupShoppingList() async {
    final groupId = await _getGroupId();
    final snapshot = await _collection.where('groupId', isEqualTo: groupId).limit(1).get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
    invalidateCache();
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
