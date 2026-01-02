import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Effectue une authentification anonyme Firebase
  /// Retourne l'utilisateur authentifié ou null en cas d'erreur
  Future<User?> signInAnonymously() async {
    try {
      final UserCredential userCredential =
          await _auth.signInAnonymously();
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print('Erreur d\'authentification: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('Erreur inattendue: $e');
      return null;
    }
  }

  /// Récupère l'utilisateur actuellement authentifié
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  /// Obtient le flux d'état de l'utilisateur (utile pour StateNotifier)
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Retourne l'UID de l'utilisateur actuel
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Vérifie si un utilisateur est authentifié
  bool isUserAuthenticated() {
    return _auth.currentUser != null;
  }

  /// Déconnecte l'utilisateur (si besoin)
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
