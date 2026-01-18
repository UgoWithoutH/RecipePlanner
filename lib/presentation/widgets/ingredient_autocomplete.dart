import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class IngredientAutocomplete extends StatefulWidget {
  /// Static method to expose the suggestion logic for reuse in other widgets
  static Future<List<Map<String, String>>> suggestIngredients(String query, {Set<String>? excludeIds}) async {
    if (query.isEmpty) return [];
    List<Map<String, String>> allResults = [];
    if (query.length < 2) {
      final snap = await FirebaseFirestore.instance.collection('ingredients').limit(50).get();
      allResults = snap.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String}).toList();
    } else {
      final snap = await FirebaseFirestore.instance
          .collection('ingredients')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      allResults = snap.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String}).toList();
      if (allResults.length < 10) {
        final snapAll = await FirebaseFirestore.instance.collection('ingredients').limit(50).get();
        final extra = snapAll.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String});
        for (final ing in extra) {
          if (!allResults.any((e) => e['id'] == ing['id'])) {
            allResults.add(ing);
          }
        }
      }
    }
    final lower = query.toLowerCase();
    return allResults
        .where((ing) =>
            (excludeIds == null || !excludeIds.contains(ing['id'])) &&
            (ing['name'] ?? '').toLowerCase().contains(lower))
        .toList();
  }
  final void Function(Map<String, String>)? onIngredientSelected;
  final Set<String>? selectedIngredientIds;
  final TextEditingController? controller;
  final String hintText;
  final void Function(Map<String, String>)? onSelected;

  const IngredientAutocomplete({
    super.key,
    this.onIngredientSelected,
    this.selectedIngredientIds,
    this.controller,
    this.hintText = 'Ajouter un ingrédient au filtre...',
    this.onSelected,
  });

  @override
  State<IngredientAutocomplete> createState() => _IngredientAutocompleteState();
}

class _IngredientAutocompleteState extends State<IngredientAutocomplete> {
  Future<List<Map<String, String>>> _searchIngredients(String query) async {
    if (query.isEmpty) return [];
    List<Map<String, String>> allResults = [];
    if (query.length < 2) {
      final snap = await FirebaseFirestore.instance.collection('ingredients').limit(50).get();
      allResults = snap.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String}).toList();
    } else {
      final snap = await FirebaseFirestore.instance
          .collection('ingredients')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      allResults = snap.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String}).toList();
      if (allResults.length < 10) {
        final snapAll = await FirebaseFirestore.instance.collection('ingredients').limit(50).get();
        final extra = snapAll.docs.map((doc) => {'id': doc.id, 'name': doc.get('name') as String});
        for (final ing in extra) {
          if (!allResults.any((e) => e['id'] == ing['id'])) {
            allResults.add(ing);
          }
        }
      }
    }
    final lower = query.toLowerCase();
    return allResults
        .where((ing) =>
            (widget.selectedIngredientIds == null || !widget.selectedIngredientIds!.contains(ing['id'])) &&
            (ing['name'] ?? '').toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, String>>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        return await _searchIngredients(textEditingValue.text.trim());
      },
      displayStringForOption: (option) => option['name']!,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (widget.controller != null && controller != widget.controller) {
          controller.text = widget.controller!.text;
          controller.selection = widget.controller!.selection;
          widget.controller!.addListener(() {
            if (controller.text != widget.controller!.text) {
              controller.text = widget.controller!.text;
              controller.selection = widget.controller!.selection;
            }
          });
        }
        return TextField(
          controller: widget.controller ?? controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            children: options.map((option) {
              return ListTile(
                title: Text(option['name'] ?? ''),
                onTap: () => onSelected(option),
              );
            }).toList(),
          ),
        );
      },
      onSelected: (ingredient) {
        if (widget.onIngredientSelected != null) widget.onIngredientSelected!(ingredient);
        if (widget.onSelected != null) widget.onSelected!(ingredient);
        // Clear the controller if provided
        if (widget.controller != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.controller!.clear();
          });
        }
      },
    );
  }
}
