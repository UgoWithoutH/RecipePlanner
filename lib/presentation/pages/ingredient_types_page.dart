import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/ingredient_type.dart';
import '../../data/repositories/firebase_ingredient_type_repository.dart';

class IngredientTypesPage extends StatefulWidget {
  const IngredientTypesPage({super.key});

  @override
  State<IngredientTypesPage> createState() => _IngredientTypesPageState();
}

class _IngredientTypesPageState extends State<IngredientTypesPage> {
  final FirebaseIngredientTypeRepository _repo = FirebaseIngredientTypeRepository();

  List<IngredientType> _types = [];
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() => _isLoading = true);
    try {
      final types = await _repo.getTypes();
      if (mounted) setState(() => _types = types);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addType() async {
    final controller = TextEditingController();
    int selectedColor = 0xFF6A5AE0;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Ajouter un type',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom du type',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Couleur', 
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)
              ),
              const SizedBox(height: 12),
              _buildColorPicker(
                selectedColor: selectedColor,
                onColorSelected: (color) => setStateDialog(() => selectedColor = color),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey))
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Ajouter', 
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF6A5AE0))
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      setState(() => _isUpdating = true);
      try {
        await _repo.addType(name, selectedColor);
        final updated = await _repo.getTypes();
        if (mounted) setState(() => _types = updated);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _editType(String id, String oldName, int oldColor) async {
    final controller = TextEditingController(text: oldName);
    int selectedColor = oldColor;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Modifier le type',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  labelText: 'Nom du type',
                  labelStyle: GoogleFonts.poppins(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Couleur', 
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)
              ),
              const SizedBox(height: 12),
              _buildColorPicker(
                selectedColor: selectedColor,
                onColorSelected: (color) => setStateDialog(() => selectedColor = color),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey))
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: Text(
                'Enregistrer', 
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF6A5AE0))
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      setState(() => _isUpdating = true);
      try {
        await _repo.updateType(id, newName, selectedColor);
        final updated = await _repo.getTypes();
        if (mounted) setState(() => _types = updated);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteType(String id) async {
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
            Text('Supprimer ce type ?',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Attention, les ingrédients utilisant ce type perdront leur classification.',
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

    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        await _repo.deleteType(id);
        final updated = await _repo.getTypes();
        if (mounted) setState(() => _types = updated);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Widget _buildColorPicker({
    required int selectedColor,
    required ValueChanged<int> onColorSelected,
  }) {
    final colors = [
      0xFFE57373, 0xFFF06292, 0xFFBA68C8, 0xFF9575CD, 0xFF7986CB,
      0xFF64B5F6, 0xFF4FC3F7, 0xFF4DD0E1, 0xFF4DB6AC, 0xFF81C784,
      0xFFAED581, 0xFFFFD54F, 0xFFFFB74D, 0xFFFF8A65, 0xFFA1887F,
      0xFF90A4AE, 0xFF6A5AE0,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected = selectedColor == color;
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: isSelected 
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Types d\'ingrédients',
            style: GoogleFonts.poppins(
                color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          // List
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _types.isEmpty
                  ? Center(
                      child: Text('Aucun type défini',
                          style: GoogleFonts.poppins(color: Colors.grey)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                      itemCount: _types.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final type = _types[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                            border:
                                Border.all(color: Colors.grey.withOpacity(0.1)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(type.color).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.label,
                                  color: Color(type.color), size: 20),
                            ),
                            title: Text(type.name,
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _editType(type.id, type.name, type.color),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6A5AE0).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6A5AE0)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _deleteType(type.id),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[400]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

          if (_isUpdating)
            Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator())),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: Colors.transparent,
          child: InkWell(
            onTap: _addType,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6A5AE0).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Nouveau type',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
