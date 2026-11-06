import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/repositories/firebase_pantry_repository.dart';
import '../../../core/constants/unit.dart';
import '../../../data/repositories/firebase_ingredient_type_repository.dart';
import '../../../domain/entities/pantry_item.dart';
import '../../../domain/entities/ingredient_type.dart';
import '../../../core/utils/qty_format.dart';
import '../../widgets/ingredient_autocomplete.dart';

part 'fridge_pantry_form.dart';
part 'fridge_pantry_list.dart';

class FridgePantryPage extends StatefulWidget {
  const FridgePantryPage({super.key});

  @override
  State<FridgePantryPage> createState() => _FridgePantryPageState();
}

const _purple = Color(0xFF6A5AE0);
const _purpleSurface = Color(0xFFF5F3FF);

class _FridgePantryPageState extends State<FridgePantryPage> {
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


}
