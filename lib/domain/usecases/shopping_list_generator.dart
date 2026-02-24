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
        final servingsNeeded = meal.totalServings > 0 ? meal.totalServings : 1;
        final ratio = servingsNeeded / baseServings;

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
              category: categoryid, // We'll resolve category name if needed, but entity has ID often
              isChecked: false,
            );
          }
        }
      }

      // Resolve names via Cache if needed
      final idsToResolve = shoppingListMap.entries
          .where((e) =>
              e.key.isNotEmpty &&
              (e.value.name == 'Inconnu' || e.value.name.isEmpty))
          .map((e) => e.key)
          .toList();

      if (idsToResolve.isNotEmpty) {
        final names =
            await IngredientNameCache.instance.fetchNamesForIds(idsToResolve);
        for (final id in names.keys) {
          if (shoppingListMap.containsKey(id)) {
            final oldItem = shoppingListMap[id]!;
            shoppingListMap[id] = oldItem.copyWith(name: names[id]!);
          }
        }
      }

      // Apply pantry reductions (items I already have)
      for (final pantryItem in mealPlan.pantryItems) {
        final pantryName = pantryItem.ingredient.name.trim().toLowerCase();
        final pantryUnit = pantryItem.unit.name;
        final pantryQty = pantryItem.quantity;

        // Find matching item in shopping list
        String? keyToRemove;
        String? keyToUpdate;
        double newQty = 0;

        for (final entry in shoppingListMap.entries) {
          final item = entry.value;
          final itemName = item.name.trim().toLowerCase();

          // Simple match: name and unit
          if (itemName == pantryName && item.unit == pantryUnit) {
            newQty = item.quantity - pantryQty;
            if (newQty <= 0) {
              keyToRemove = entry.key;
            } else {
              keyToUpdate = entry.key;
            }
            break;
          }
        }

        if (keyToRemove != null) {
          shoppingListMap.remove(keyToRemove);
        } else if (keyToUpdate != null) {
          shoppingListMap[keyToUpdate] = shoppingListMap[keyToUpdate]!.copyWith(quantity: newQty);
        }
      }

      // Create Shopping List Object
      // Check if one already exists for this meal plan to preserve checked items?
      // The user said: "if I check items it updates in DB... if I restart app".
      // But if I *regenerate* the plan, maybe we overwrite?
      // Since generation usually means "New Plan", overwriting is probably correct.
      // However, if the user just edited one meal in the plan, generating a wholly new list might wipe checks.
      // Better approach: Fetch existing list if any, and merge 'isChecked' status if item exists.
      
      final existingList = await _shoppingListRepo.getShoppingListByMealPlanId(mealPlan.id);
      
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
      debugPrint("Error generating shopping list: $e");
      rethrow;
    }
  }
}
