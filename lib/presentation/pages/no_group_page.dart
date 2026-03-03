import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_notifier.dart';

/// Screen shown when the authenticated user belongs to no group in Firestore.
/// The user is blocked from accessing the app until an admin adds them to a group.
class NoGroupPage extends ConsumerWidget {
  const NoGroupPage({super.key});

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
                Icons.group_off_rounded,
                size: 80,
                color: Color(0xFF6A5AE0),
              ),
              const SizedBox(height: 24),

              // ── Title ─────────────────────────────────────────────────
              Text(
                'Aucun groupe',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2E2E2E),
                ),
              ),
              const SizedBox(height: 16),

              // ── Explanation ───────────────────────────────────────────
              Text(
                'Votre compte n\'est associé à aucun groupe.\n\n'
                'Demandez à un administrateur de vous ajouter à un groupe '
                'pour accéder à l\'application.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 48),

              // ── Sign out ──────────────────────────────────────────────
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A5AE0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  'Se déconnecter',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: () {
                  ref.read(authNotifierProvider.notifier).signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
