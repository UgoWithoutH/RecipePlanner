import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Effectue une authentification anonyme Firebase
  /// Retourne l'utilisateur authentifié ou null en cas d'erreur
    /// Performs anonymous Firebase authentication
    /// Returns the authenticated user or null in case of error
  Future<User?> signInAnonymously() async {
    try {
      final UserCredential userCredential =
          await _auth.signInAnonymously();
      return userCredential.user;
    } on FirebaseAuthException catch (e) { // ignore: unused_catch_clause
        // print('Authentication error: ${e.code} - ${e.message}');
      return null;
    } catch (_) {
        // print('Unexpected error');
      return null;
    }
  }

  /// Gets the currently authenticated user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  /// Gets the user state stream (useful for StateNotifier)
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Returns the current user's UID
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Checks if a user is authenticated
  bool isUserAuthenticated() {
    return _auth.currentUser != null;
  }

  /// Signs out the user (if needed)
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
