import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/unit.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/pantry_item.dart';
import 'group_repository.dart';

class FirebasePantryRepository {
  static final FirebasePantryRepository instance =
      FirebasePantryRepository._internal();
  FirebasePantryRepository._internal();

  final CollectionReference _pantry =
      FirebaseFirestore.instance.collection('pantry');

  Future<String> _getGroupId() async {
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      throw Exception('Aucun groupe trouvé pour cet utilisateur.');
    }
    return groupId;
  }

  /// Returns all pantry items for the current group, sorted by urgent first then by name.
  Future<List<PantryItem>> getAll() async {
    final groupId = await _getGroupId();
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
    return items;
  }

  /// Saves (creates or updates) a pantry item. Returns the saved item with its Firestore ID.
  Future<PantryItem> save(PantryItem item) async {
    final groupId = await _getGroupId();
    if (item.id.isNotEmpty) {
      await _pantry.doc(item.id).set(item.toFirestore(groupId));
      return item;
    } else {
      final docRef = _pantry.doc();
      await docRef.set(item.toFirestore(groupId));
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
  }

  /// Deletes all pantry items for the current group.
  Future<void> deleteAll() async {
    final groupId = await _getGroupId();
    final snapshot =
        await _pantry.where('groupId', isEqualTo: groupId).get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Remet les ingrédients d'une liste de repas dans le frigo/placard
  /// (ex : annulation d'un repas historisé — plat non cuisiné).
  /// Si l'item existe → additionne la quantité. Sinon → crée un nouvel item.
  /// Ne traite que les unités identiques.
  // ── Helpers de conversion d'unités ──────────────────────────────────────
  /// Convertit une quantité vers l'unité de base (ml pour liquides, g pour poids).
  double _toBase(double qty, Unit unit) {
    if (unit == Unit.l) return qty * 1000;
    if (unit == Unit.kg) return qty * 1000;
    return qty;
  }

  /// Retourne l'unité de base correspondante.
  Unit _baseUnit(Unit unit) {
    if (unit == Unit.l) return Unit.ml;
    if (unit == Unit.kg) return Unit.g;
    return unit;
  }

  /// Convertit une quantité en base vers l'unité cible d'un item frigo.
  /// Renvoie la quantité dans l'unité d'origine du pantryItem.
  double _fromBase(double baseQty, Unit targetUnit) {
    if (targetUnit == Unit.l || targetUnit == Unit.ml) {
      return targetUnit == Unit.l ? baseQty / 1000 : baseQty;
    }
    if (targetUnit == Unit.kg || targetUnit == Unit.g) {
      return targetUnit == Unit.kg ? baseQty / 1000 : baseQty;
    }
    return baseQty;
  }

  /// Vérifie si deux unités sont compatibles (même famille).
  bool _unitsCompatible(Unit a, Unit b) {
    if (a == b) return true;
    final liquids = {Unit.ml, Unit.l};
    final weights = {Unit.g, Unit.kg};
    if (liquids.contains(a) && liquids.contains(b)) return true;
    if (weights.contains(a) && weights.contains(b)) return true;
    return false;
  }

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
        final ingredientQtyBase =
            _toBase(ingredient.quantity * meal.recipeMultiplier, ingredient.unit);

        PantryItem? existing =
            ingredient.ingredient.id.isNotEmpty ? byId[ingredient.ingredient.id] : null;
        existing ??= byName[ingredient.ingredient.name.toLowerCase().trim()];

        if (existing != null) {
          if (!_unitsCompatible(existing.unit, ingredient.unit)) continue;
          // Convertit la quantité à remettre vers l'unité du pantryItem
          final restoredInPantryUnit = _fromBase(ingredientQtyBase, existing.unit);
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
        final consumedBase =
            _toBase(ingredient.quantity * meal.recipeMultiplier, ingredient.unit);

        PantryItem? pantryItem =
            ingredient.ingredient.id.isNotEmpty ? byId[ingredient.ingredient.id] : null;
        pantryItem ??= byName[ingredient.ingredient.name.toLowerCase().trim()];

        if (pantryItem == null) continue;
        if (!_unitsCompatible(pantryItem.unit, ingredient.unit)) continue;

        // Convertit le pantryItem en base pour la soustraction
        final pantryBase = _toBase(pantryItem.quantity, pantryItem.unit);
        final remainingBase = pantryBase - consumedBase;

        if (remainingBase <= 0) {
          await delete(pantryItem.id);
          byId.remove(pantryItem.ingredientId);
          byName.remove(pantryItem.name.toLowerCase().trim());
        } else {
          // Reconvertit le résultat vers l'unité d'origine du pantryItem
          final newQty = _fromBase(remainingBase, pantryItem.unit);
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
