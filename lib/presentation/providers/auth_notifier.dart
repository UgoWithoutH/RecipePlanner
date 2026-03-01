import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    try {
      final appUser = await _service.verifyCurrentUser();
      state = appUser != null
          ? AuthAuthenticated(appUser)
          : const AuthUnauthenticated();
    } on AccessDeniedException {
      // The session existed but the UID is no longer in Firestore.
      state = const AuthDenied();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  // -------------------------------------------------------------------------
  // Public actions
  // -------------------------------------------------------------------------

  /// Launches the Google Sign-In flow and performs the Firestore access check.
  Future<void> signInWithGoogle() async {
    state = const AuthLoading();
    try {
      final appUser = await _service.signInWithGoogle();
      state = AuthAuthenticated(appUser);
    } on SignInCancelledException {
      // User dismissed the picker – go back to sign-in screen silently.
      state = const AuthUnauthenticated();
    } on AccessDeniedException {
      state = const AuthDenied();
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  /// Signs out from Google and Firebase, then resets to unauthenticated.
  Future<void> signOut() async {
    await _service.signOut();
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