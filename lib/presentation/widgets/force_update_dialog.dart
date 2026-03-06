import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog bloquant affiché lorsqu'une mise à jour obligatoire est disponible.
/// L'utilisateur ne peut pas fermer le dialog — il doit mettre à jour l'app.
class ForceUpdateDialog extends StatelessWidget {
  final String? storeUrl;

  const ForceUpdateDialog({super.key, this.storeUrl});

  static const _purple = Color(0xFF6A5AE0);
  static const _purpleLight = Color(0xFFEDE8FF);
  static const _purpleSurface = Color(0xFFF5F3FF);

  Future<void> _openStore() async {
    final url = storeUrl ?? 'https://play.google.com/store';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Empêche la fermeture par le bouton retour Android
      canPop: false,
      child: Dialog(
        backgroundColor: _purpleSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _purpleLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: _purple,
                  size: 38,
                ),
              ),
              const SizedBox(height: 20),

              // Titre
              Text(
                'Mise à jour requise',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _purple,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Message
              Text(
                'Une nouvelle version de l\'application est disponible. '
                'Veuillez mettre à jour pour continuer à l\'utiliser.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Bouton
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  label: Text(
                    'Mettre à jour',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
