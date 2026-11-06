// ignore_for_file: invalid_use_of_protected_member
part of 'recipes_page.dart';

extension _RecipesFilters on _RecipesPageState {
  int _catalogActiveFiltersCount() {
    int count = 0;
    if (_catalogImportFilter != 'all') count++;
    if (_catalogSortMode != 'alpha') count++;
    if (_selectedCatalogGroupIds.isNotEmpty) count++;
    return count;
  }

  int _groupActiveFiltersCount() {
    int count = 0;
    if (_sortMode != 'alpha') count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    return count;
  }

  Future<void> _openGroupFiltersSheet() async {
    String tempSort = _sortMode;
    final tempCategories = Set<String>.from(_selectedCategoryIds);
    final tempIngredients = Set<String>.from(_selectedIngredientIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: 12),
                    Text(
                      'Filtres recettes',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.sort_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Tri',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort_by_alpha_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('A-Z'),
                            ],
                          ),
                          selected: tempSort == 'alpha',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'alpha'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Mieux notées'),
                            ],
                          ),
                          selected: tempSort == 'rating',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'rating'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.local_dining_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Plus cuisinées'),
                            ],
                          ),
                          selected: tempSort == 'usage',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'usage'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.block_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Jamais cuisinées'),
                            ],
                          ),
                          selected: tempSort == 'unused',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'unused'),
                        ),
                      ],
                    ),
                    if (_allCategories.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.label_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Catégories',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Toutes', style: TextStyle(fontWeight: FontWeight.w600)),
                            selected: tempCategories.isEmpty,
                            backgroundColor: const Color(0xFF6A5AE0).withOpacity(0.15),
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(() => tempCategories.clear()),
                          ),
                          for (final category in _allCategories)
                            FilterChip(
                              label: Text(
                                category['name'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              selected: tempCategories.contains(category['id']),
                              backgroundColor: Color(category['color'] as int? ?? 0xFF6A5AE0).withOpacity(0.15),
                              selectedColor: Color(category['color'] as int? ?? 0xFF6A5AE0).withOpacity(0.35),
                              onSelected: (_) {
                                final id = category['id'] as String?;
                                if (id == null || id.isEmpty) return;
                                setStateSheet(() {
                                  if (tempCategories.contains(id)) {
                                    tempCategories.remove(id);
                                  } else {
                                    tempCategories.add(id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setStateSheet(() {
                                tempSort = 'alpha';
                                tempCategories.clear();
                              });
                            },
                            child: Text(
                              'Réinitialiser',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _sortMode = tempSort;
                                _selectedCategoryIds = tempCategories;
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              'Appliquer',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCatalogFiltersSheet() async {
    String tempImport = _catalogImportFilter;
    String tempSort = _catalogSortMode;
    final tempGroups = Set<String>.from(_selectedCatalogGroupIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: 12),
                    Text(
                      'Filtres catalogue',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.download_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Import',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in const [
                          {'value': 'all', 'label': 'Toutes', 'icon': Icons.all_inclusive_rounded},
                          {'value': 'notImported', 'label': 'Non importées', 'icon': Icons.download_rounded},
                          {'value': 'imported', 'label': 'Importées', 'icon': Icons.check_circle_rounded},
                        ])
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(entry['icon'] as IconData, size: 18),
                                const SizedBox(width: 6),
                                Text(entry['label'] as String),
                              ],
                            ),
                            selected: tempImport == entry['value'] as String,
                            selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                            onSelected: (_) => setStateSheet(
                              () => tempImport = entry['value'] as String,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.sort_rounded, size: 16, color: Color(0xFF6A5AE0)),
                        const SizedBox(width: 6),
                        Text(
                          'Tri',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort_by_alpha_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('A-Z'),
                            ],
                          ),
                          selected: tempSort == 'alpha',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'alpha'),
                        ),
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 18),
                              const SizedBox(width: 6),
                              const Text('Mieux notées'),
                            ],
                          ),
                          selected: tempSort == 'rating',
                          selectedColor: const Color(0xFF6A5AE0).withOpacity(0.35),
                          onSelected: (_) => setStateSheet(() => tempSort = 'rating'),
                        ),
                      ],
                    ),
                    if (_catalogGroups.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.group_rounded, size: 16, color: Color(0xFF6A5AE0)),
                          const SizedBox(width: 6),
                          Text(
                            'Groupes visibles',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Tous les groupes'),
                            selected: tempGroups.isEmpty,
                            onSelected: (_) => setStateSheet(() => tempGroups.clear()),
                          ),
                          for (final group in _catalogGroups)
                            FilterChip(
                              label: Text(group['name'] ?? ''),
                              selected: tempGroups.contains(group['id']),
                              onSelected: (_) {
                                final id = group['id'];
                                if (id == null) return;
                                setStateSheet(() {
                                  if (tempGroups.contains(id)) {
                                    tempGroups.remove(id);
                                  } else {
                                    tempGroups.add(id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setStateSheet(() {
                                tempImport = 'all';
                                tempSort = 'alpha';
                                tempGroups.clear();
                              });
                            },
                            child: Text(
                              'Réinitialiser',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _catalogImportFilter = tempImport;
                                _catalogSortMode = tempSort;
                                _selectedCatalogGroupIds = tempGroups;
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A5AE0),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              'Appliquer',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
