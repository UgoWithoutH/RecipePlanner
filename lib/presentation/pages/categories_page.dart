import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recipe_planner/domain/entities/category.dart';
import '../../data/repositories/firebase_category_repository.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final FirebaseCategoryRepository _categoryRepo = FirebaseCategoryRepository();

  List<Category> _categories = []; // List of categories
  bool _isLoading = true; // Initial loading
  bool _isUpdating = false; // Inline loading for add/edit/delete

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// Load all categories from repository
  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final categories = await _categoryRepo.getCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  /// Add a new category
  Future<void> _addCategory() async {
    final controller = TextEditingController();
    int selectedColor = 0xFF6A5AE0; // Default purple

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Ajouter une catégorie',
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
                  labelText: 'Nom de la catégorie',
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

      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.addCategory(name, selectedColor);

      // Refresh the list after adding
      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  /// Edit category name and color
  Future<void> _editCategory(String id, String oldName, int oldColor) async {
    final controller = TextEditingController(text: oldName);
    int selectedColor = oldColor;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Modifier la catégorie',
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
                  labelText: 'Nom de la catégorie',
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

      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.updateCategory(id, newName, selectedColor);

      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  Widget _buildColorPicker({
    required int selectedColor,
    required ValueChanged<int> onColorSelected,
  }) {
    final colors = [
      0xFFE57373, // Red
      0xFFF06292, // Pink
      0xFFBA68C8, // Purple
      0xFF9575CD, // Deep Purple
      0xFF7986CB, // Indigo
      0xFF64B5F6, // Blue
      0xFF4FC3F7, // Light Blue
      0xFF4DD0E1, // Cyan
      0xFF4DB6AC, // Teal
      0xFF81C784, // Green
      0xFFAED581, // Light Green
      0xFFFFD54F, // Amber
      0xFFFFB74D, // Orange
      0xFFFF8A65, // Deep Orange
      0xFFA1887F, // Brown
      0xFF90A4AE, // Blue Grey
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected = selectedColor == color;
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.black, width: 2)
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }

  /// Delete category
  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Supprimer la catégorie',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Voulez-vous vraiment supprimer cette catégorie ?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey))
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text('Supprimer', style: GoogleFonts.poppins(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isUpdating = true); // Inline loader
      await _categoryRepo.deleteCategory(id);

      final updatedCategories = await _categoryRepo.getCategories();
      if (mounted) {
        setState(() {
          _categories = updatedCategories;
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Slightly off-white background
      appBar: AppBar(
        title: Text(
          'Mes Catégories',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600, 
            color: Colors.black87
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Column(
        children: [
          // Inline loader for add/edit/delete actions
          if (_isUpdating)
            const LinearProgressIndicator(minHeight: 3, color: Color(0xFF6A5AE0), backgroundColor: Color(0xFFEFEFFC)),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator()) // Full screen on initial load
                : _categories.isEmpty
                  ? Center(child: Text('Aucune catégorie', style: GoogleFonts.poppins(color: Colors.grey)))
                  : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final name = cat.name;
                          final id = cat.id;
                          final baseColor = Color(cat.color);

                          final hsl = HSLColor.fromColor(baseColor);
                          final startLightness = hsl.lightness;
                          final textLightness = startLightness > 0.4 ? 0.4 : startLightness;
                          final textColor = hsl.withLightness(textLightness).toColor();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: baseColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              title: Text(
                                name,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_rounded, color: textColor.withOpacity(0.7)),
                                    onPressed: () => _editCategory(id, name, cat.color),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, color: textColor.withOpacity(0.7)),
                                    onPressed: () => _deleteCategory(id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCategory,
        backgroundColor: const Color(0xFF6A5AE0),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}