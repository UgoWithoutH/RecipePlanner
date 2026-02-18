import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/datasources/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final AuthService _authService;

  AuthNotifier(this._authService)
      : super(const AsyncValue.loading()) {
    _initializeAuth();
  }

  /// Initializes authentication at startup
  Future<void> _initializeAuth() async {
    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      // The user is already authenticated
      state = AsyncValue.data(currentUser);
    } else {
      // Perform anonymous authentication
      await signInAnonymously();
    }
  }

  /// Performs anonymous authentication
  Future<void> signInAnonymously() async {
    state = const AsyncValue.loading();
    try {
      final user = await _authService.signInAnonymously();
      state = AsyncValue.data(user);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Signs out the user
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }
}

/// Provider that manages the authentication state
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});