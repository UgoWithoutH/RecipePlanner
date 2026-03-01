import '../../domain/entities/app_user.dart';

/// Represents every possible state of the authentication lifecycle.
sealed class AuthState {
  const AuthState();
}

/// Initial state before any check has been performed.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// A sign-in or session-restore operation is in progress.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// The user is authenticated AND their UID exists in Firestore.
class AuthAuthenticated extends AuthState {
  final AppUser user;
  const AuthAuthenticated(this.user);
}

/// The user completed Google Sign-In but their UID is NOT in Firestore.
/// Access is refused and the Firebase session has been terminated.
class AuthDenied extends AuthState {
  const AuthDenied();
}

/// No active session (signed out or first launch).
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// An unexpected error occurred during sign-in.
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}
