import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/cache_warmer.dart';
import '../../core/utils/web_firestore_config.dart';
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
      // On web release only: check if we're returning from a Google redirect.
      // Skipped on iOS (Safari/Chrome on iOS use popup, not redirect).
      // In debug mode we use signInWithPopup so there's no redirect to handle.
      if (kIsWeb && kReleaseMode && !isIOSBrowser()) {
        final redirectUser = await _service.checkRedirectResult();
        if (redirectUser != null) {
          debugPrint('[Auth] _restoreSession: résultat redirect → uid=${redirectUser.uid}');
          state = AuthAuthenticated(redirectUser);
          CacheWarmer.warmAll();
          return;
        }
      }

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
  /// On web: triggers a page redirect — result handled in _restoreSession on reload.
  /// On mobile: completes inline.
  Future<void> signInWithGoogle() async {
    state = const AuthLoading();
    debugPrint('[Auth] signInWithGoogle: début du flux Google Sign-In...');
    try {
      if (kIsWeb && kReleaseMode) {
        // Triggers full-page redirect — page reloads, _restoreSession picks up the result.
        await _service.signInWithGoogle();
        return;
      }
      final appUser = await _service.signInWithGoogle();
      debugPrint('[Auth] signInWithGoogle: connexion réussie → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
      state = AuthAuthenticated(appUser);
      CacheWarmer.warmAll();
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