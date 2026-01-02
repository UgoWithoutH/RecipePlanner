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

  /// Initialise l'authentification au démarrage
  Future<void> _initializeAuth() async {
    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      // L'utilisateur est déjà authentifié
      state = AsyncValue.data(currentUser);
    } else {
      // Effectue une authentification anonyme
      await signInAnonymously();
    }
  }

  /// Effectue l'authentification anonyme
  Future<void> signInAnonymously() async {
    state = const AsyncValue.loading();
    try {
      final user = await _authService.signInAnonymously();
      state = AsyncValue.data(user);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Déconnecte l'utilisateur
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }
}

/// Provider qui gère l'état de l'authentification
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});