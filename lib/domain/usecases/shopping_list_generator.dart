import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/ingredient_name_cache.dart';
import '../../data/repositories/firebase_shopping_list_repository.dart';
import '../entities/meal_plan.dart';
import '../entities/shopping_list.dart';

class ShoppingListGenerator {
  final FirebaseShoppingListRepository _shoppingListRepo =
      FirebaseShoppingListRepository();

  Future<void> generateAndSaveShoppingList(MealPlan mealPlan) async {
    try {
      final firestore = FirebaseFirestore.instance;
      // Map of ingredientId -> ShoppingItem
      final Map<String, ShoppingItem> shoppingListMap = {};

      for (final meal in mealPlan.meals) {
        // Les repas "restes" n'ont pas besoin d'achat : les ingrédients ont déjà
        // été comptabilisés lors du repas original.
        if (meal.isLeftoverMeal) continue;

        // We need the FULL recipe to get ingredients
        Map<String, dynamic>? data;

        // A. Try fetch by ID
        final directDoc =
            await firestore.collection('recipes').doc(meal.recipe.id).get();
        if (directDoc.exists) {
          data = directDoc.data();
        }

        // B. Fallback: Query by 'id' field
        if (data == null) {
          final query = await firestore
              .collection('recipes')
              .where('id', isEqualTo: meal.recipe.id)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            data = query.docs.first.data();
          }
        }

        // C. Fallback: Query by Title
        if (data == null) {
          var titleQuery = await firestore
              .collection('recipes')
              .where('title', isEqualTo: meal.recipe.title)
              .limit(1)
              .get();

          if (titleQuery.docs.isEmpty && meal.recipe.title.isNotEmpty) {
            final t = meal.recipe.title;
            final capitalized = t[0].toUpperCase() + t.substring(1);
            if (capitalized != t) {
              titleQuery = await firestore
                  .collection('recipes')
                  .where('title', isEqualTo: capitalized)
                  .limit(1)
                  .get();
            }
          }

          if (titleQuery.docs.isNotEmpty) {
            data = titleQuery.docs.first.data();
          }
        }

        if (data == null) continue; // Skip if recipe not found

        // Parse ingredients
        final ingredientsRef = (data['ingredients'] as List<dynamic>?) ?? [];
        final baseServings = (data['servings'] as num?)?.toInt() ?? 1;

        // Calculate scaling factor
        // On base le ratio sur les portions CUISINÉES (recipeServings × recipeMultiplier),
        // pas sur les portions consommées (totalServings) qui peuvent être inférieures
        // quand il y a des restes. Ex : recette pour 8, on cuisine 1× = 8 portions,
        // on en mange 3 → on achète quand même les ingrédients pour 8.
        final cookedServings = baseServings * (meal.recipeMultiplier > 0 ? meal.recipeMultiplier : 1);
        final ratio = cookedServings / baseServings; // = recipeMultiplier

        for (final item in ingredientsRef) {
          if (item is! Map<String, dynamic>) continue;

          final id = item['ingredientId'] as String? ?? '';
          final name = item['ingredientName'] as String? ?? 'Inconnu';
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unit = item['unit'] as String? ?? '';
           final categoryid = item['category'] as String? ?? '';


          if (id.isEmpty && name == 'Inconnu') continue;

          // Use ID as key if available, otherwise name (normalized)
          final key = id.isNotEmpty ? id : name.toLowerCase().trim();

          if (shoppingListMap.containsKey(key)) {
            final oldItem = shoppingListMap[key]!;
            shoppingListMap[key] = oldItem.copyWith(
              quantity: oldItem.quantity + (qty * ratio),
            );
          } else {
            shoppingListMap[key] = ShoppingItem(
              name: name,
              quantity: qty * ratio,
              unit: unit,
              typeId: null, // Will be resolved later
              isChecked: false,
            );
          }
        }
      }

      // Resolve names and types via Firestore
      final idsToResolve = shoppingListMap.keys
          .where((k) => k.isNotEmpty)
          .toList();

      if (idsToResolve.isNotEmpty) {
        // Chunk requests
        final chunks = <List<String>>[];
        for (var i = 0; i < idsToResolve.length; i += 10) {
          chunks.add(idsToResolve.sublist(
              i, i + 10 > idsToResolve.length ? idsToResolve.length : i + 10));
        }

        for (final chunk in chunks) {
          try {
            final query = await firestore
                .collection('ingredients')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();

            for (final doc in query.docs) {
              final id = doc.id;
              final data = doc.data();
              final name = data['name'] as String? ?? 'Inconnu';
              final typeId = data['typeId'] as String?;

              if (shoppingListMap.containsKey(id)) {
                final oldItem = shoppingListMap[id]!;
                // Update name (if it was placeholder) and typeId
                shoppingListMap[id] = oldItem.copyWith(
                  name: oldItem.name == 'Inconnu' ? name : oldItem.name,
                  typeId: typeId,
                );
              }
            }
          } catch (e) {
          }
        }
      }

      // Apply pantry reductions (items I already have)
      // Units are normalised to a base unit before comparison:
      //   ml & l  → ml   |   g & kg → g
      // This allows e.g. "500 ml" in the pantry to correctly reduce "1 l" on the list.
      double _toBase(double qty, String unit) {
        if (unit == 'l') return qty * 1000;
        if (unit == 'kg') return qty * 1000;
        return qty; // ml, g, piece, etc. already in base
      }

      String _baseUnit(String unit) {
        if (unit == 'l') return 'ml';
        if (unit == 'kg') return 'g';
        return unit;
      }

      for (final pantryItem in mealPlan.pantryItems) {
        final pantryName = pantryItem.ingredient.name.trim().toLowerCase();
        final pantryBaseUnit = _baseUnit(pantryItem.unit.name);
        final pantryBaseQty = _toBase(pantryItem.quantity, pantryItem.unit.name);

        String? keyToRemove;
        String? keyToUpdate;
        double newQty = 0;
        String newUnit = '';

        for (final entry in shoppingListMap.entries) {
          final item = entry.value;
          final itemName = item.name.trim().toLowerCase();
          final itemBaseUnit = _baseUnit(item.unit);

          if (itemName == pantryName && itemBaseUnit == pantryBaseUnit) {
            final itemBaseQty = _toBase(item.quantity, item.unit);
            final remaining = itemBaseQty - pantryBaseQty;
            if (remaining <= 0) {
              keyToRemove = entry.key;
            } else {
              keyToUpdate = entry.key;
              // Convert back: if original unit was 'l' and remaining >= 1000, keep l; else use ml
              if (item.unit == 'l' || item.unit == 'ml') {
                if (remaining >= 1000) {
                  newQty = remaining / 1000;
                  newUnit = 'l';
                } else {
                  newQty = remaining;
                  newUnit = 'ml';
                }
              } else if (item.unit == 'kg' || item.unit == 'g') {
                if (remaining >= 1000) {
                  newQty = remaining / 1000;
                  newUnit = 'kg';
                } else {
                  newQty = remaining;
                  newUnit = 'g';
                }
              } else {
                newQty = remaining;
                newUnit = item.unit;
              }
            }
            break;
          }
        }

        if (keyToRemove != null) {
          shoppingListMap.remove(keyToRemove);
        } else if (keyToUpdate != null) {
          shoppingListMap[keyToUpdate] = shoppingListMap[keyToUpdate]!.copyWith(
            quantity: newQty,
            unit: newUnit,
          );
        }
      }

      // Create Shopping List Object
      // Check if one already exists for this meal plan to preserve checked items?
      // The user said: "if I check items it updates in DB... if I restart app".
      // But if I *regenerate* the plan, maybe we overwrite?
      // Since generation usually means "New Plan", overwriting is probably correct.
      // However, if the user just edited one meal in the plan, generating a wholly new list might wipe checks.
      // Better approach: Fetch existing list if any, and merge 'isChecked' status if item exists.
      
      final existingList = await _shoppingListRepo.getGroupShoppingList();
      
      List<ShoppingItem> finalItems = shoppingListMap.values.toList();
      
      if (existingList != null) {
          // Merge checked status
          finalItems = finalItems.map((newItem) {
              // Try to find matching item in existing list
              // Match by name or ID (key isn't stored in ShoppingItem, but name and unit usually match)
              try {
                  final oldItem = existingList.items.firstWhere(
                      (old) => old.name == newItem.name && old.unit == newItem.unit,
                  );
                  return newItem.copyWith(isChecked: oldItem.isChecked);
              } catch (e) {
                  return newItem;
              }
          }).toList();
      }

      final newList = ShoppingList(
        id: existingList?.id ?? firestore.collection('shopping_lists').doc().id, // Reuse ID if exists
        mealPlanId: mealPlan.id,
        createdAt: DateTime.now(),
        items: finalItems,
      );

      await _shoppingListRepo.saveShoppingList(newList);
      
    } catch (e) {
      rethrow;
    }
  }
}
