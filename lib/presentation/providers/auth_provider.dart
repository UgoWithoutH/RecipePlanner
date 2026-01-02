import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/datasources/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Provider qui émet l'état de l'authentification
final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.userStream;
});

/// Provider pour gérer l'authentification anonyme
final anonymousAuthProvider =
    FutureProvider.family<User?, void>((ref, _) async {
  final authService = ref.watch(authServiceProvider);
  return await authService.signInAnonymously();
});

/// Provider pour obtenir l'utilisateur courant
final currentUserProvider = Provider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentUser();
});

/// Provider pour obtenir l'UID de l'utilisateur
final currentUserIdProvider = Provider<String?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentUserId();
});