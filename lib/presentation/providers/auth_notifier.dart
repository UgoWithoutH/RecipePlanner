import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/cache_warmer.dart';
import '../../data/datasources/google_auth_service.dart';
import 'auth_state.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

/// Provides a singleton [GoogleAuthService] to the Riverpod tree.
final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the full authentication lifecycle with binary Firestore access
/// control. On creation it immediately checks whether a valid session already
/// exists (app restart / hot-reload scenario).
class AuthNotifier extends StateNotifier<AuthState> {
  final GoogleAuthService _service;

  AuthNotifier(this._service) : super(const AuthInitial()) {
    _restoreSession();
  }

  // -------------------------------------------------------------------------
  // Session restore (called once at startup)
  // -------------------------------------------------------------------------

  Future<void> _restoreSession() async {
    state = const AuthLoading();
    debugPrint('[Auth] _restoreSession: tentative de restauration de session...');
    try {
      final appUser = await _service.verifyCurrentUser();
      if (appUser != null) {
        debugPrint('[Auth] _restoreSession: session restaurée → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
        state = AuthAuthenticated(appUser);
        CacheWarmer.warmAll(); // fire-and-forget warm-up
      } else {
        debugPrint('[Auth] _restoreSession: aucune session active → état non authentifié.');
        state = const AuthUnauthenticated();
      }
    } on AccessDeniedException {
      // The session existed but the UID is no longer in Firestore.
      debugPrint('[Auth] _restoreSession: AccessDeniedException → accès refusé.');
      state = const AuthDenied();
    } catch (e) {
      debugPrint('[Auth] _restoreSession: erreur inattendue → $e');
      state = const AuthUnauthenticated();
    }
  }

  // -------------------------------------------------------------------------
  // Public actions
  // -------------------------------------------------------------------------

  /// Launches the Google Sign-In flow and performs the Firestore access check.
  Future<void> signInWithGoogle() async {
    state = const AuthLoading();
    debugPrint('[Auth] signInWithGoogle: début du flux Google Sign-In...');
    try {
      final appUser = await _service.signInWithGoogle();
      debugPrint('[Auth] signInWithGoogle: connexion réussie → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
      state = AuthAuthenticated(appUser);
      CacheWarmer.warmAll(); // fire-and-forget warm-up
    } on SignInCancelledException {
      // User dismissed the picker – go back to sign-in screen silently.
      debugPrint('[Auth] signInWithGoogle: connexion annulée par l\'utilisateur.');
      state = const AuthUnauthenticated();
    } on AccessDeniedException {
      debugPrint('[Auth] signInWithGoogle: AccessDeniedException → accès refusé.');
      state = const AuthDenied();
    } on PlatformException catch (e) {
      // Native errors (e.g. Out of Memory, network, cancelled from OS)
      if (e.code == 'network_error' ||
          e.message?.toLowerCase().contains('cancel') == true ||
          e.message?.toLowerCase().contains('memory') == true) {
        debugPrint('[Auth] signInWithGoogle: PlatformException récupérée (cancel/network/memory) → ${e.message}');
        state = const AuthUnauthenticated();
      } else {
        debugPrint('[Auth] signInWithGoogle: PlatformException non gérée → code=${e.code}, message=${e.message}');
        state = AuthError(e.message ?? e.code);
      }
    } catch (e) {
      debugPrint('[Auth] signInWithGoogle: erreur inattendue → $e');
      state = AuthError(e.toString());
    }
  }

  /// Signs out from Google and Firebase, then resets to unauthenticated.
  Future<void> signOut() async {
    await _service.signOut();
    CacheWarmer.clearAll();
    state = const AuthUnauthenticated();
  }
}

// ---------------------------------------------------------------------------
// StateNotifier provider
// ---------------------------------------------------------------------------

/// The main provider consumed by the UI to react to authentication state.
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final service = ref.watch(googleAuthServiceProvider);
  return AuthNotifier(service);
});