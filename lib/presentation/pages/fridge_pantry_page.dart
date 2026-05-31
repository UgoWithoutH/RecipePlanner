import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/firebase_pantry_repository.dart';
import '../../core/constants/unit.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../domain/entities/pantry_item.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../core/utils/qty_format.dart';
import '../widgets/ingredient_autocomplete.dart';

class FridgePantryPage extends StatefulWidget {
  const FridgePantryPage({super.key});

  @override
  State<FridgePantryPage> createState() => _FridgePantryPageState();
}

class _FridgePantryPageState extends State<FridgePantryPage> {
  static const _purple = Color(0xFF6A5AE0);
  static const _purpleSurface = Color(0xFFF5F3FF);

  final _repo = FirebasePantryRepository.instance;
  final _typeRepo = FirebaseIngredientTypeRepository();

  List<PantryItem> _items = [];
  Map<String, IngredientType> _typesById = {};
  bool _isLoading = true;
  bool _isSaving = false;

  // Form state
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  Unit _selectedUnit = Unit.piece;
  String _selectedIngredientId = '';
  String _selectedTypeId = '';
  String _selectedTypeName = '';
  bool _formIsUrgent = false;
  PantryItem? _editingItem;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repo.getAll(),
        _typeRepo.getTypes(),
      ]);
      final items = results[0] as List<PantryItem>;
      final types = results[1] as List<IngredientType>;
      if (mounted) {
        setState(() {
          _items = items;
          _typesById = {for (final t in types) t.id: t};
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Erreur de chargement : $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startEdit(PantryItem item) {
    setState(() {
      _editingItem = item;
      _nameController.text = item.name;
      _quantityController.text = fmtQty(item.quantity);
      _selectedUnit = item.unit;
      _selectedIngredientId = item.ingredientId;
      _selectedTypeId = item.typeId;
      _selectedTypeName = item.typeName;
      _formIsUrgent = item.isUrgent;
    });
    _openFormSheet();
  }

  void _resetForm() {
    _editingItem = null;
    _nameController.clear();
    _quantityController.text = '1';
    _selectedUnit = Unit.piece;
    _selectedIngredientId = '';
    _selectedTypeId = '';
    _selectedTypeName = '';
    _formIsUrgent = false;
  }

  Future<void> _saveItem() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final quantity =
        double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1.0;

    setState(() => _isSaving = true);
    try {
      final item = PantryItem(
        id: _editingItem?.id ?? '',
        name: name,
        ingredientId: _selectedIngredientId,
        typeId: _selectedTypeId,
        typeName: _selectedTypeName,
        quantity: quantity,
        unit: _selectedUnit,
        isUrgent: _formIsUrgent,
        updatedAt: DateTime.now(),
      );
      await _repo.save(item);
      if (mounted) Navigator.of(context).pop();
      await _loadItems();
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleUrgent(PantryItem item) async {
    try {
      final updated = await _repo.toggleUrgent(item);
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) _items[idx] = updated;
      });
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    }
  }

  Future<void> _deleteItem(PantryItem item) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text('Supprimer cet article ?',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous retirer "${item.name}" du frigo / placard ?',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400], foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Supprimer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
              )),
            ]),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.delete(item.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i.id == item.id));
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    }
  }

  void _openFormSheet({bool isNew = false}) {
    if (isNew) _resetForm();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildFormSheet(ctx),
    ).then((_) => _resetForm());
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: isError ? Colors.red[700] : _purple,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _purpleSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _purple))
                  : _items.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openFormSheet(isNew: true),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('Ajouter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildCountBadge({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _purpleSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.kitchen_rounded, color: _purple, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frigo / Placard',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                Row(
                  children: [
                    _buildCountBadge(
                      label:
                          '${_items.where((i) => !i.isUrgent).length} normaux',
                      color: const Color(0xFF6A5AE0),
                    ),
                    if (_items.any((i) => i.isUrgent)) ...[
                      const SizedBox(width: 6),
                      _buildCountBadge(
                        label:
                            '${_items.where((i) => i.isUrgent).length} urgents',
                        color: Colors.orange.shade700,
                        icon: Icons.local_fire_department_rounded,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty)
            IconButton(
              onPressed: _confirmDeleteAll,
              icon: Icon(Icons.delete_sweep_rounded, color: Colors.red[400]),
              tooltip: 'Tout vider',
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.kitchen_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Frigo et placard vides',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez ce que vous avez déjà\npour optimiser vos plans de repas.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final urgentItems = _items.where((i) => i.isUrgent).toList();
    final normalItems = _items.where((i) => !i.isUrgent).toList();

    Map<String, List<PantryItem>> _groupByCategory(List<PantryItem> items) {
      final Map<String, List<PantryItem>> grouped = {};
      for (final item in items) {
        final key = item.typeName.isNotEmpty ? item.typeName : 'Autre';
        grouped.putIfAbsent(key, () => []).add(item);
      }
      // Sort alphabetically within each category
      for (final key in grouped.keys) {
        grouped[key]!.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      return grouped;
    }

    List<String> _sortedKeys(Map<String, List<PantryItem>> grouped) {
      return grouped.keys.toList()
        ..sort((a, b) {
          if (a == 'Autre') return 1;
          if (b == 'Autre') return -1;
          return a.compareTo(b);
        });
    }

    final urgentGrouped = _groupByCategory(urgentItems);
    final urgentKeys = _sortedKeys(urgentGrouped);
    final normalGrouped = _groupByCategory(normalItems);
    final normalKeys = _sortedKeys(normalGrouped);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (urgentItems.isNotEmpty) ...[
          _buildSuperSectionLabel('🔥 Urgents', Colors.orange.shade700),
          for (final key in urgentKeys) ...[
            _buildSectionLabel(key),
            ...urgentGrouped[key]!.map(_buildItemCard),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
        ],
        if (normalItems.isNotEmpty) ...[
          if (urgentItems.isNotEmpty)
            _buildSuperSectionLabel('Normaux', const Color(0xFF6A5AE0)),
          for (final key in normalKeys) ...[
            _buildSectionLabel(key),
            ...normalGrouped[key]!.map(_buildItemCard),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildSuperSectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    final type =
        _typesById.values.where((t) => t.name == label).firstOrNull;
    final color =
        type != null ? Color(type.color) : const Color(0xFF6A5AE0);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(PantryItem item) {
    final isUrgent = item.isUrgent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isUrgent
            ? Border.all(color: Colors.orange.shade300, width: 1.5)
            : Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isUrgent) ...[  
                        Icon(Icons.local_fire_department_rounded,
                            size: 13, color: Colors.orange[700]),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          item.name,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmtQty(item.quantity)} ${item.unit.label}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _toggleUrgent(item),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? Colors.orange.withOpacity(0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUrgent
                          ? Icons.local_fire_department_rounded
                          : Icons.local_fire_department_outlined,
                      size: 13,
                      color: isUrgent
                          ? Colors.orange[700]
                          : Colors.grey[400],
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Urgent',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isUrgent
                            ? Colors.orange[700]
                            : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.edit_rounded,
                  size: 17, color: Colors.grey[400]),
              onPressed: () => _startEdit(item),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 17, color: Colors.red[300]),
              onPressed: () => _deleteItem(item),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.delete_sweep_rounded, color: Colors.red[400], size: 28),
            ),
            const SizedBox(height: 16),
            Text('Tout vider ?',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Voulez-vous supprimer tous les articles du frigo / placard ?',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 14)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400], foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Tout vider', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
              )),
            ]),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteAll();
      if (!mounted) return;
      setState(() => _items.clear());
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Form sheet (add / edit)
  // ---------------------------------------------------------------------------

  Widget _buildFormSheet(BuildContext ctx) {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _editingItem != null
                      ? 'Modifier l\'article'
                      : 'Ajouter un article',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 20),
                // Autocomplete ingredient name
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<Map<String, String>>(
                      optionsBuilder: (textEditingValue) =>
                          IngredientAutocomplete.suggestIngredients(
                              textEditingValue.text),
                      displayStringForOption: (option) => option['name']!,
                      onSelected: (option) {
                        setSheetState(() {
                          _nameController.text = option['name']!;
                          _selectedIngredientId = option['id']!;
                          _selectedTypeId = '';
                          _selectedTypeName = '';
                        });
                        final ingId = option['id']!;
                        if (ingId.isNotEmpty) {
                          FirebaseFirestore.instance
                              .collection('ingredients')
                              .doc(ingId)
                              .get()
                              .then((doc) {
                            if (!doc.exists) return;
                            final typeId =
                                (doc.data())?['typeId'] as String? ?? '';
                            if (typeId.isEmpty) return;
                            final type = _typesById[typeId];
                            if (type != null && mounted) {
                              setSheetState(() {
                                _selectedTypeId = typeId;
                                _selectedTypeName = type.name;
                              });
                            }
                          }).catchError((_) {});
                        }
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        if (controller.text != _nameController.text) {
                          controller.text = _nameController.text;
                          controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length));
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (val) {
                            _nameController.text = val;
                            _selectedIngredientId = '';
                          },
                          decoration: InputDecoration(
                            hintText: 'Pommes, Riz, Lait...',
                            hintStyle:
                                GoogleFonts.poppins(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.search,
                                color: Colors.grey[400], size: 20),
                          ),
                          style: GoogleFonts.poppins(fontSize: 14),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8,
                            shadowColor: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: constraints.maxWidth,
                              constraints:
                                  const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Text(
                                        option['name']!,
                                        style: GoogleFonts.poppins(
                                            fontSize: 14),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                if (_selectedTypeName.isNotEmpty) ...[  
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(Icons.label_rounded,
                          size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(
                        'Catégorie : $_selectedTypeName',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Quantity + Unit row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Quantité',
                          hintStyle:
                              GoogleFonts.poppins(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Unit>(
                            value: _selectedUnit,
                            isExpanded: true,
                            icon: Icon(Icons.expand_more_rounded, color: Colors.grey[600], size: 20),
                            dropdownColor: Colors.white,
                            selectedItemBuilder: (context) => Unit.values.map((u) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Unité', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500])),
                                Text(u.label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
                              ],
                            )).toList(),
                            onChanged: (u) => setSheetState(() => _selectedUnit = u ?? Unit.piece),
                            items: Unit.values.map((u) => DropdownMenuItem<Unit>(
                              value: u,
                              child: Text(u.label, style: GoogleFonts.poppins(fontSize: 14)),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Urgent toggle
                GestureDetector(
                  onTap: () =>
                      setSheetState(() => _formIsUrgent = !_formIsUrgent),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _formIsUrgent
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _formIsUrgent
                            ? Colors.orange.shade300
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _formIsUrgent
                              ? Icons.local_fire_department_rounded
                              : Icons.local_fire_department_outlined,
                          color: _formIsUrgent
                              ? Colors.orange[700]
                              : Colors.grey[400],
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Utiliser en priorité',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _formIsUrgent
                                      ? Colors.orange[800]
                                      : const Color(0xFF1A1A1A),
                                ),
                              ),
                              Text(
                                'L\'algorithme privilégiera les recettes\nqui utilisent cet ingrédient.',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: _formIsUrgent
                                      ? Colors.orange[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _formIsUrgent,
                          onChanged: (v) =>
                              setSheetState(() => _formIsUrgent = v),
                          activeColor: Colors.orange[700],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Save button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _editingItem != null ? 'Enregistrer' : 'Ajouter',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
