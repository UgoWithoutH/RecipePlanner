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
    final types = await _repo.getTypes();
    if (mounted) {
      setState(() {
        _types = types;
        _isLoading = false;
      });
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
      await _repo.addType(name, selectedColor);
      
      final updated = await _repo.getTypes();
      if (mounted) {
        setState(() {
          _types = updated;
          _isUpdating = false;
        });
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
      await _repo.updateType(id, newName, selectedColor);

      final updated = await _repo.getTypes();
      if (mounted) {
        setState(() {
          _types = updated;
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _deleteType(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce type ?'),
        content: const Text(
          'Attention, si des ingrédients utilisent ce type, ils perdront leur classification.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Annuler')
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Supprimer')
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isUpdating = true); // Loader
      try {
        await _repo.deleteType(id);
      } catch (e) {
        // Handle error?
      }
      final updated = await _repo.getTypes();
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _types = updated;
        });
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
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded,
                                      color: Colors.blueAccent),
                                  onPressed: () => _editType(
                                      type.id, type.name, type.color),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.redAccent),
                                  onPressed: () => _deleteType(type.id),
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
