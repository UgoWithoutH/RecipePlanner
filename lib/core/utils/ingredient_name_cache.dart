import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple singleton cache to fetch ingredient names by id using chunked `whereIn` queries.
class IngredientNameCache {
  IngredientNameCache._privateConstructor();
  static final IngredientNameCache instance =
      IngredientNameCache._privateConstructor();

  final Map<String, String> _cache = {};

  /// Fetch names for the given ids. Uses the cache and only queries missing ids.
  Future<Map<String, String>> fetchNamesForIds(List<String> ids) async {
    final Map<String, String> result = {};
    final missing = <String>[];

    for (final id in ids) {
      if (_cache.containsKey(id)) {
        result[id] = _cache[id]!;
      } else {
        missing.add(id);
      }
    }

    if (missing.isEmpty) return result;

    const int chunkSize = 10; // Firestore whereIn limit
    for (var i = 0; i < missing.length; i += chunkSize) {
      final end = (i + chunkSize) > missing.length
          ? missing.length
          : (i + chunkSize);
      final chunk = missing.sublist(i, end);
      try {
        final q = await FirebaseFirestore.instance
            .collection('ingredients')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in q.docs) {
          final name = doc.get('name') as String?;
          if (name != null) {
            _cache[doc.id] = name;
            result[doc.id] = name;
          }
        }
      } catch (_) {
        // ignore errors and continue; missing ids will simply not be in the result
      }
    }

    return result;
  }

  /// Optional helper to prefill or update the cache.
  void setName(String id, String name) {
    _cache[id] = name;
  }

  /// Remove an ingredient from the cache
  void remove(String id) {
    _cache.remove(id);
  }

  /// Clear the entire cache (called on sign-out)
  void clear() {
    _cache.clear();
  }
}
