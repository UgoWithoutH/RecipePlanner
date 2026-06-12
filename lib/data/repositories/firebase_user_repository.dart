import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user.dart';
import 'group_repository.dart';

class FirebaseUserRepository {
  final CollectionReference _users =
      FirebaseFirestore.instance.collection('users');

  /// Fetch all users that belong to the same group as the current user.
  Future<List<User>> getUsers() async {
    final memberIds = await GroupRepository.instance.getGroupMemberIds();
    if (memberIds.isEmpty) return [];

    final results = await Future.wait(
      memberIds.map((uid) => _users.doc(uid).get()),
    );

    return results
        .where((doc) => doc.exists)
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return User.fromFirestore(doc.id, data);
        })
        .toList();
  }

  /// Autorise un utilisateur en créant un document dans `users` avec son email.
  /// À sa première connexion, le service auth migre ce doc vers users/{uid}.
  Future<void> addUser(String email) async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    await FirebaseFirestore.instance.collection('users').add({
      'email': email,
      'name': '',
      'role': 'user',
      if (groupId != null) 'groupId': groupId,
    });
  }

  /// Update user name
  Future<void> updateUser(String id, String newName) async {
    await _users.doc(id).update({'name': newName});
  }

  /// Delete a user
  Future<void> deleteUser(String id) async {
    await _users.doc(id).delete();
  }
}