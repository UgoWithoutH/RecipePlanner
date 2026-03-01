/// Represents an authorized application user loaded from Firestore.
///
/// The Firestore document ID is the Firebase Auth UID.
/// Access is granted only if that document exists in `users/{uid}`.
class AppUser {
  final String uid;
  final String email;
  final String name;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
  });

  /// [uid] is both the Firestore document ID and the Firebase Auth UID.
  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  String toString() => 'AppUser(uid: $uid, email: $email, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppUser && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
