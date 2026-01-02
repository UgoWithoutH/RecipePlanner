import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';

/// Exemples d'utilisation de l'authentification anonyme

// Exemple 1: Afficher l'ID utilisateur
class UserIdExample extends ConsumerWidget {
  const UserIdExample({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return authState.when(
      data: (user) => Text('ID utilisateur: ${user?.uid ?? "Non authentifié"}'),
      loading: () => const Text('Chargement...'),
      error: (error, stack) => const Text('Erreur'),
    );
  }
}

// Exemple 2: Accéder à l'utilisateur dans un widget
class UserInfoWidget extends ConsumerWidget {
  const UserInfoWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          return const Text('Pas d\'utilisateur');
        }
        return Column(
          children: [
            Text('Email: ${user.email ?? "Anonyme"}'),
            Text('UID: ${user.uid}'),
            Text('Anonyme: ${user.isAnonymous}'),
          ],
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Erreur: $error'),
    );
  }
}

// Exemple 3: Déconnexion (si besoin)
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        ref.read(authNotifierProvider.notifier).signOut();
      },
      child: const Text('Déconnexion'),
    );
  }
}

// Exemple 4: Utiliser l'UID pour Firestore
class FirestoreExampleWidget extends ConsumerWidget {
  const FirestoreExampleWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        // Vous pouvez maintenant utiliser user.uid pour
        // les requêtes Firestore spécifiques à cet utilisateur
        // Exemple:
        // FirebaseFirestore.instance
        //   .collection('users')
        //   .doc(user.uid)
        //   .collection('recipes')
        //   .snapshots()

        return Text('Utilisateur actif: ${user.uid}');
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => const Text('Erreur d\'authentification'),
    );
  }
}
