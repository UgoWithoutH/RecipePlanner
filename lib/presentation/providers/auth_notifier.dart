import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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

  void _authLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  AuthNotifier(this._service) : super(const AuthInitial()) {
    _restoreSession();
  }

  // -------------------------------------------------------------------------
  // Session restore (called once at startup)
  // -------------------------------------------------------------------------

  Future<void> _restoreSession() async {
    state = const AuthLoading();
    _authLog('[Auth] _restoreSession: tentative de restauration de session...');
    try {
      // No redirect flow — signInWithPopup is used for all web platforms.
      // Session is persisted in Firebase Auth's localStorage; verifyCurrentUser()
      // restores it on page reload without any redirect result to check.
      final appUser = await _service.verifyCurrentUser();
      if (appUser != null) {
        _authLog('[Auth] _restoreSession: session restaurée → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
        state = AuthAuthenticated(appUser);
        CacheWarmer.warmAll(); // fire-and-forget warm-up
      } else {
        _authLog('[Auth] _restoreSession: aucune session active → état non authentifié.');
        state = const AuthUnauthenticated();
      }
    } on AccessDeniedException {
      // The session existed but the UID is no longer in Firestore.
      _authLog('[Auth] _restoreSession: AccessDeniedException → accès refusé.');
      state = const AuthDenied();
    } catch (e) {
      _authLog('[Auth] _restoreSession: erreur inattendue → $e');
      state = const AuthUnauthenticated();
    }
  }

  // -------------------------------------------------------------------------
  // Public actions
  // -------------------------------------------------------------------------

  /// Launches the Google Sign-In flow and performs the Firestore access check.
  /// Uses signInWithPopup on all platforms (redirect flow removed).
  Future<void> signInWithGoogle() async {
    state = const AuthLoading();
    _authLog('[Auth] signInWithGoogle: début du flux Google Sign-In...');
    try {
      final appUser = await _service.signInWithGoogle();
      _authLog('[Auth] signInWithGoogle: connexion réussie → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
      state = AuthAuthenticated(appUser);
      CacheWarmer.warmAll();
    } on SignInCancelledException {
      // User dismissed the picker – go back to sign-in screen silently.
      _authLog('[Auth] signInWithGoogle: connexion annulée par l\'utilisateur.');
      state = const AuthUnauthenticated();
    } on AccessDeniedException {
      _authLog('[Auth] signInWithGoogle: AccessDeniedException → accès refusé.');
      state = const AuthDenied();
    } on PlatformException catch (e) {
      // Native errors (e.g. Out of Memory, network, cancelled from OS)
      if (e.code == 'network_error' ||
          e.message?.toLowerCase().contains('cancel') == true ||
          e.message?.toLowerCase().contains('memory') == true) {
        _authLog('[Auth] signInWithGoogle: PlatformException récupérée (cancel/network/memory) → ${e.message}');
        state = const AuthUnauthenticated();
      } else {
        _authLog('[Auth] signInWithGoogle: PlatformException non gérée → code=${e.code}, message=${e.message}');
        state = AuthError(e.message ?? e.code);
      }
    } catch (e) {
      _authLog('[Auth] signInWithGoogle: erreur inattendue → $e');
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