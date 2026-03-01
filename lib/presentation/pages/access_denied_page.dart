import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_notifier.dart';

/// Screen shown when the user has authenticated with Google but their UID
/// is NOT present in the Firestore `users` collection.
///
/// The Firebase session has already been terminated by [GoogleAuthService]
/// before this screen is displayed.
class AccessDeniedPage extends ConsumerWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Icon ──────────────────────────────────────────────────
              const Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 24),

              // ── Title ─────────────────────────────────────────────────
              Text(
                'Accès refusé',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2E2E2E),
                    ),
              ),
              const SizedBox(height: 16),

              // ── Explanation ───────────────────────────────────────────
              Text(
                'Ce compte Google ne dispose pas des autorisations '
                'nécessaires pour accéder à cette application.\n\n'
                'Si vous pensez qu\'il s\'agit d\'une erreur, '
                'veuillez contacter l\'administrateur.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 48),

              // ── Retry with a different account ────────────────────────
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  // Reset state to unauthenticated so the LoginPage is shown.
                  ref.read(authNotifierProvider.notifier).signOut();
                },
                child: const Text(
                  'Utiliser un autre compte',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
