import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/group_repository.dart';

// In-memory cache: groupId → list of all ingredients for that group.
// Avoids repeated Firestore reads while the user is typing.
final Map<String, List<Map<String, String>>> _ingredientCache = {};

Future<List<Map<String, String>>> _fetchAllIngredients(String groupId) async {
  if (_ingredientCache.containsKey(groupId)) return _ingredientCache[groupId]!;
  final snap = await FirebaseFirestore.instance
      .collection('ingredients')
      .where('groupId', isEqualTo: groupId)
      .get();
  final list = snap.docs
      .map((doc) => {'id': doc.id, 'name': doc.get('name') as String})
      .toList();
  _ingredientCache[groupId] = list;
  return list;
}

class IngredientAutocomplete extends StatefulWidget {
  /// Call this to invalidate the cache (e.g. after adding a new ingredient).
  static void invalidateCache() => _ingredientCache.clear();

  /// Static method to expose the suggestion logic for reuse in other widgets.
  static Future<List<Map<String, String>>> suggestIngredients(String query, {Set<String>? excludeIds}) async {
    if (query.isEmpty) return [];
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return [];
    final all = await _fetchAllIngredients(groupId);
    final lower = query.toLowerCase();
    return all
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
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) return [];
    final all = await _fetchAllIngredients(groupId);
    final lower = query.toLowerCase();
    return all
        .where((ing) =>
            (widget.selectedIngredientIds == null || !widget.selectedIngredientIds!.contains(ing['id'])) &&
            (ing['name'] ?? '').toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth;
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
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: fieldWidth,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: options.map((option) {
                          return InkWell(
                            onTap: () => onSelected(option),
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Text(
                                  option['name'] ?? '',
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          onSelected: (ingredient) {
            if (widget.onIngredientSelected != null) widget.onIngredientSelected!(ingredient);
            if (widget.onSelected != null) widget.onSelected!(ingredient);
            if (widget.controller != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.controller!.clear();
              });
            }
          },
        );
      },
    );
  }
}
