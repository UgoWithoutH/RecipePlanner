import 'package:cloud_firestore/cloud_firestore.dart';
import 'group_repository.dart';

/// Calcule les statistiques d'utilisation à partir de l'historique des repas.
///
/// Les compteurs sont mis en cache en mémoire pour la durée de la session.
/// Appelez [invalidateCache] pour forcer un rechargement.
class FirebaseStatsRepository {
  static final instance = FirebaseStatsRepository._();
  FirebaseStatsRepository._();

  Map<String, int>? _cachedRecipeCounts;
  Map<String, int>? _cachedIngredientCounts;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Nombre de fois que chaque recette a été mangée (hors restes).
  /// Lit le champ [usageCount] directement dans chaque document recette.
  Future<Map<String, int>> getRecipeUsageCounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedRecipeCounts != null) return _cachedRecipeCounts!;

    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      _cachedRecipeCounts = {};
      return {};
    }

    final snap = await FirebaseFirestore.instance
        .collection('recipes')
        .where('groupId', isEqualTo: groupId)
        .get();

    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final usage = (doc.data()['usageCount'] as num?)?.toInt() ?? 0;
      if (usage > 0) counts[doc.id] = usage;
    }

    _cachedRecipeCounts = counts;
    return counts;
  }

  /// Nombre de fois que chaque ingrédient a été utilisé.
  /// Lit le champ [usageCount] directement dans chaque document ingrédient.
  Future<Map<String, int>> getIngredientUsageCounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedIngredientCounts != null) return _cachedIngredientCounts!;

    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      _cachedIngredientCounts = {};
      return {};
    }

    final snap = await FirebaseFirestore.instance
        .collection('ingredients')
        .where('groupId', isEqualTo: groupId)
        .get();

    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final usage = (doc.data()['usageCount'] as num?)?.toInt() ?? 0;
      if (usage > 0) counts[doc.id] = usage;
    }

    _cachedIngredientCounts = counts;
    return counts;
  }

  /// Vide le cache (appelé automatiquement après chaque ajout à l'historique).
  void invalidateCache() {
    _cachedRecipeCounts = null;
    _cachedIngredientCounts = null;
  }
}
