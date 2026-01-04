import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user.dart';

class FirebaseUserRepository {
  final CollectionReference _users =
      FirebaseFirestore.instance.collection('users');

  /// Fetch all users from Firestore
  Future<List<User>> getUsers() async {
    final snap = await _users.get();
    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return User.fromFirestore(doc.id, data);
    }).toList();
  }

  /// Add a new user
  Future<void> addUser(String name) async {
    await _users.add({'name': name});
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