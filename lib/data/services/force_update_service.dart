import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Résultat de la vérification de mise à jour forcée.
class ForceUpdateResult {
  final bool updateRequired;
  final String? storeUrl;
  final int? minBuildNumber;

  const ForceUpdateResult({
    required this.updateRequired,
    this.storeUrl,
    this.minBuildNumber,
  });
}

/// Service qui vérifie si une mise à jour obligatoire est disponible.
///
/// La configuration est stockée dans Firestore sous :
///   /appConfig/forceUpdate
/// avec les champs :
///   - minBuildNumber (int)  : numéro de build minimum requis
///   - storeUrl (String)     : URL Play Store (ou App Store)
class ForceUpdateService {
  static final ForceUpdateService _instance = ForceUpdateService._internal();
  factory ForceUpdateService() => _instance;
  ForceUpdateService._internal();

  Future<ForceUpdateResult> checkForUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('forceUpdate')
          .get();

      if (!doc.exists) return const ForceUpdateResult(updateRequired: false);

      final data = doc.data()!;
      final storeUrl = data['storeUrl'] as String?;
      final minBuildNumber = (data['minBuildNumber'] as num?)?.toInt();

      if (storeUrl == null || storeUrl.isEmpty) {
        return const ForceUpdateResult(updateRequired: false);
      }

      // Si minBuildNumber n'est pas défini, on ne force pas la MAJ
      if (minBuildNumber == null) {
        return const ForceUpdateResult(updateRequired: false);
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (currentBuild < minBuildNumber) {
        return ForceUpdateResult(
          updateRequired: true,
          storeUrl: storeUrl,
          minBuildNumber: minBuildNumber,
        );
      }
      return const ForceUpdateResult(updateRequired: false);
    } catch (_) {
      // En cas d'erreur réseau ou Firestore, on laisse passer
      return const ForceUpdateResult(updateRequired: false);
    }
  }
}
