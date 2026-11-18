import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart';
import '../../core/constants/ingredient_equivalence.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/pantry_item.dart';
import 'group_repository.dart';

class FirebasePantryRepository {
  static final FirebasePantryRepository instance =
      FirebasePantryRepository._internal();
  FirebasePantryRepository._internal();

  final CollectionReference _pantry =
      FirebaseFirestore.instance.collection('pantry');

  static final Map<String, List<PantryItem>> _cache = {};

  static void invalidateCache() => _cache.clear();

  Future<String?> _getGroupId() async {
    return GroupRepository.instance.getCurrentGroupId();
  }

  /// Returns all pantry items for the current group, sorted by urgent first then by name.
  Future<List<PantryItem>> getAll() async {
    final groupId = await _getGroupId();
    if (groupId == null) return [];
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    final snapshot =
        await _pantry.where('groupId', isEqualTo: groupId).get();
    final items = snapshot.docs
        .map((doc) => PantryItem.fromFirestore(
            doc.id, doc.data() as Map<String, dynamic>))
        .toList();
    // Urgent items first, then alphabetically
    items.sort((a, b) {
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _cache[groupId] = items;
    return items;
  }

  /// Saves (creates or updates) a pantry item. Returns the saved item with its Firestore ID.
  Future<PantryItem> save(PantryItem item) async {
    final groupId = await _getGroupId();
    if (groupId == null) throw Exception('Pas de groupe assigné.');
    if (item.id.isNotEmpty) {
      await _pantry.doc(item.id).set(item.toFirestore(groupId));
      invalidateCache();
      return item;
    } else {
      final docRef = _pantry.doc();
      await docRef.set(item.toFirestore(groupId));
      invalidateCache();
      return item.copyWith(id: docRef.id);
    }
  }

  /// Toggles the urgent flag of an item.
  Future<PantryItem> toggleUrgent(PantryItem item) async {
    final updated = item.copyWith(
      isUrgent: !item.isUrgent,
      updatedAt: DateTime.now(),
    );
    return save(updated);
  }

  /// Deletes a single pantry item by ID.
  Future<void> delete(String id) async {
    await _pantry.doc(id).delete();
    invalidateCache();
  }

  /// Deletes all pantry items for the current group.
  Future<void> deleteAll() async {
    final groupId = await _getGroupId();
    if (groupId == null) return;
    final snapshot =
        await _pantry.where('groupId', isEqualTo: groupId).get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
    invalidateCache();
  }

  /// Remet les ingrédients d'une liste de repas dans le frigo/placard
  /// (ex : annulation d'un repas historisé — plat non cuisiné).
  /// Si l'item existe → additionne la quantité. Sinon → crée un nouvel item.
  /// Ne traite que les unités identiques.
  // ── Helpers de conversion d'unités ──────────────────────────────────────
  /// Convertit une quantité vers l'unité de base de sa famille (selon les
  /// correspondances d'unités du groupe).
  double _toBase(String name, double qty, Unit unit) =>
      IngredientEquivalences.toBaseFor(name, qty, unit);

  /// Convertit une quantité en base vers l'unité cible d'un item frigo.
  /// Renvoie la quantité dans l'unité d'origine du pantryItem.
  double _fromBase(String name, double baseQty, Unit targetUnit) =>
      IngredientEquivalences.fromBaseFor(name, baseQty, targetUnit);

  /// Vérifie si deux unités sont compatibles (même famille).
  bool _unitsCompatible(String name, Unit a, Unit b) =>
      IngredientEquivalences.isSameDimensionFor(name, a, b);

  Future<void> restoreFromMeals(List<Meal> meals) async {
    final pantryItems = await getAll();

    final Map<String, PantryItem> byId = {
      for (final item in pantryItems)
        if (item.ingredientId.isNotEmpty) item.ingredientId: item,
    };
    final Map<String, PantryItem> byName = {
      for (final item in pantryItems) item.name.toLowerCase().trim(): item,
    };

    for (final meal in meals) {
      for (final ingredient in meal.recipe.ingredients) {
        PantryItem? existing =
            ingredient.ingredient.id.isNotEmpty ? byId[ingredient.ingredient.id] : null;
        existing ??= byName[ingredient.ingredient.name.toLowerCase().trim()];
        final eqName = existing?.name ?? ingredient.ingredient.name;
        final ingredientQtyBase = _toBase(
            eqName, ingredient.quantity * meal.recipeMultiplier, ingredient.unit);

        if (existing != null) {
          if (!_unitsCompatible(eqName, existing.unit, ingredient.unit)) continue;
          // Convertit la quantité à remettre vers l'unité du pantryItem
          final restoredInPantryUnit = _fromBase(eqName, ingredientQtyBase, existing.unit);
          final updated = existing.copyWith(
            quantity: existing.quantity + restoredInPantryUnit,
            updatedAt: DateTime.now(),
          );
          await save(updated);
          if (existing.ingredientId.isNotEmpty) byId[existing.ingredientId] = updated;
          byName[existing.name.toLowerCase().trim()] = updated;
        } else {
          // Récupérer typeId/typeName depuis le document ingredient Firestore
          String typeId = '';
          String typeName = '';
          if (ingredient.ingredient.id.isNotEmpty) {
            try {
              final doc = await FirebaseFirestore.instance
                  .collection('ingredients')
                  .doc(ingredient.ingredient.id)
                  .get();
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>;
                typeId = data['typeId'] as String? ?? '';
                if (typeId.isNotEmpty) {
                  final typeDoc = await FirebaseFirestore.instance
                      .collection('ingredient_types')
                      .doc(typeId)
                      .get();
                  if (typeDoc.exists) {
                    typeName = (typeDoc.data() as Map<String, dynamic>)['name'] as String? ?? '';
                  }
                }
              }
            } catch (_) {}
          }
          // Créer un nouvel item dans l'unité de la recette
          final newItem = PantryItem(
            id: '',
            name: ingredient.ingredient.name,
            ingredientId: ingredient.ingredient.id,
            typeId: typeId,
            typeName: typeName,
            quantity: ingredient.quantity * meal.recipeMultiplier,
            unit: ingredient.unit,
            updatedAt: DateTime.now(),
          );
          final saved = await save(newItem);
          if (saved.ingredientId.isNotEmpty) byId[saved.ingredientId] = saved;
          byName[saved.name.toLowerCase().trim()] = saved;
        }
      }
    }
  }

  /// Déduit les ingrédients consommés par une liste de repas du frigo/placard.
  /// Gère les conversions ml↔l et g↔kg.
  /// Supprime l'item si la quantité atteint 0.
  Future<void> deductFromMeals(List<Meal> meals) async {
    final pantryItems = await getAll();

    final Map<String, PantryItem> byId = {
      for (final item in pantryItems)
        if (item.ingredientId.isNotEmpty) item.ingredientId: item,
    };
    final Map<String, PantryItem> byName = {
      for (final item in pantryItems)
        item.name.toLowerCase().trim(): item,
    };

    for (final meal in meals) {
      for (final ingredient in meal.recipe.ingredients) {
        PantryItem? pantryItem =
            ingredient.ingredient.id.isNotEmpty ? byId[ingredient.ingredient.id] : null;
        pantryItem ??= byName[ingredient.ingredient.name.toLowerCase().trim()];

        if (pantryItem == null) continue;
        final eqName = pantryItem.name;
        if (!_unitsCompatible(eqName, pantryItem.unit, ingredient.unit)) continue;
        final consumedBase = _toBase(
            eqName, ingredient.quantity * meal.recipeMultiplier, ingredient.unit);

        // Convertit le pantryItem en base pour la soustraction
        final pantryBase = _toBase(eqName, pantryItem.quantity, pantryItem.unit);
        final remainingBase = pantryBase - consumedBase;

        if (remainingBase <= 0) {
          await delete(pantryItem.id);
          byId.remove(pantryItem.ingredientId);
          byName.remove(pantryItem.name.toLowerCase().trim());
        } else {
          // Reconvertit le résultat vers l'unité d'origine du pantryItem
          final newQty = _fromBase(eqName, remainingBase, pantryItem.unit);
          final updated = pantryItem.copyWith(
            quantity: newQty,
            updatedAt: DateTime.now(),
          );
          await save(updated);
          if (pantryItem.ingredientId.isNotEmpty) byId[pantryItem.ingredientId] = updated;
          byName[pantryItem.name.toLowerCase().trim()] = updated;
        }
      }
    }
  }
}
