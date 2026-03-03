import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user_recipe_serving.dart';
import 'group_repository.dart';

class FirebaseUserRecipeServingRepository {
  final CollectionReference _users = FirebaseFirestore.instance.collection(
    'users',
  );
  final CollectionReference _recipes = FirebaseFirestore.instance.collection(
    'recipes',
  );

  /// Fetch all UserRecipeServing for every member of the current user's group.
  /// Does not require a prior getUsers() call.
  Future<List<UserRecipeServing>> fetchAllGroupServings() async {
    final memberIds = await GroupRepository.instance.getGroupMemberIds();
    if (memberIds.isEmpty) return [];
    final all = <UserRecipeServing>[];
    for (final uid in memberIds) {
      final snapshot = await _users
          .doc(uid)
          .collection('recipeServings')
          .get();
      for (final doc in snapshot.docs) {
        all.add(UserRecipeServing.fromFirestore(
          doc.data(),
          userId: uid,
          recipeId: doc.id,
        ));
      }
    }
    return all;
  }

  Future<List<UserRecipeServing>> fetchServingsForRecipe(
    String recipeId,
  ) async {
    final snapshot = await _recipes
        .doc(recipeId)
        .collection('userServings')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return UserRecipeServing(
        userId: doc.id,
        recipeId: recipeId,
        lunchServings: data['lunchServings'] ?? 0,
        dinnerServings: data['dinnerServings'] ?? 0,
        userName: data['userName'] ?? '',
        recipeTitle: data['recipeTitle'] ?? '',
      );
    }).toList();
  }

  /// Save or update a UserRecipeServing for both user and recipe
  Future<void> save(UserRecipeServing serving) async {
    final batch = FirebaseFirestore.instance.batch();

    // Reference for user's collection
    final userRef = _users
        .doc(serving.userId)
        .collection('recipeServings')
        .doc(serving.recipeId);

    // Reference for recipe's collection
    final recipeRef = _recipes
        .doc(serving.recipeId)
        .collection('userServings')
        .doc(serving.userId);

    final data = serving.toFirestore();

    batch.set(userRef, data);
    batch.set(recipeRef, data);

    await batch.commit();
  }

  /// Watch all UserRecipeServing for a given user
  /// Returns a stream of UserRecipeServing list
  Stream<List<UserRecipeServing>> watchForUser(String userId) {
    return _users
        .doc(userId)
        .collection('recipeServings')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            return UserRecipeServing.fromFirestore(
              doc.data(),
              userId: userId,
              recipeId: doc.id,
            );
          }).toList(),
        );
  }

  /// Watch all UserRecipeServing for a given recipe
  /// Returns a stream of UserRecipeServing list
  Stream<List<UserRecipeServing>> watchForRecipe(String recipeId) {
    return _recipes
        .doc(recipeId)
        .collection('userServings')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            return UserRecipeServing.fromFirestore(
              doc.data(),
              userId: doc.id,
              recipeId: recipeId,
            );
          }).toList(),
        );
  }
}
