// ignore_for_file: invalid_use_of_protected_member
part of 'recipes_page.dart';

extension _RecipesCatalog on _RecipesPageState {
  Future<void> _fetchCatalogRecipes() async {
    setState(() => _catalogLoading = true);
    final groupId = await GroupRepository.instance.getCurrentGroupId();
    if (groupId == null) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    final visibleGroupIds = List<String>.from(
      (groupDoc.data() as Map<String, dynamic>)['visibleGroupIds'] ?? [],
    );
    if (visibleGroupIds.isEmpty) {
      if (mounted) {
        setState(() {
          _catalogRecipes = [];
          _catalogGroups = [];
          _selectedCatalogGroupIds.clear();
          _catalogLoading = false;
        });
      }
      return;
    }
    // Fetch group names and recipes in parallel
    final groupNameFutures = visibleGroupIds.map(
      (gid) => FirebaseFirestore.instance.collection('groups').doc(gid).get(),
    );
    final recipesFuture = FirebaseFirestore.instance
        .collection('recipes')
        .where('groupId', whereIn: visibleGroupIds)
        .get();
    final results = await Future.wait([Future.wait(groupNameFutures), recipesFuture]);
    if (!mounted) return;
    final groupSnaps = (results[0] as List).cast<DocumentSnapshot>();
    final groupNames = <String, String>{};
    for (final snap in groupSnaps) {
      if (snap.exists) {
        groupNames[snap.id] = (snap.data() as Map<String, dynamic>)['name'] as String? ?? snap.id;
      }
    }
    final availableGroups = groupNames.entries
        .map((e) => <String, String>{'id': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    final recipesSnap = results[1] as QuerySnapshot;
    final recipes = recipesSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      data['_id'] = doc.id;
      data['_groupName'] = groupNames[data['groupId'] as String? ?? ''] ?? '';
      return data;
    }).toList()
      ..sort((a, b) => (a['title'] as String? ?? '').compareTo(b['title'] as String? ?? ''));
    setState(() {
      _catalogRecipes = recipes;
      _catalogGroups = availableGroups;
      _selectedCatalogGroupIds.removeWhere(
        (id) => !availableGroups.any((g) => g['id'] == id),
      );
      _catalogLoading = false;
    });
  }

  List<Map<String, dynamic>> _filteredCatalogRecipes() {
    final filtered = _catalogRecipes.where((recipe) {
      final title = recipe['title'] as String? ?? '';
      final recipeGroupId = recipe['groupId'] as String? ?? '';
      final matchesTitle = _titleFilter.isEmpty ||
          title.toLowerCase().contains(_titleFilter.toLowerCase());
      final matchesGroup = _selectedCatalogGroupIds.isEmpty ||
          _selectedCatalogGroupIds.contains(recipeGroupId);
      final isImported = _groupRecipeTitles.contains(title.toLowerCase().trim());
      final matchesImportFilter = _catalogImportFilter == 'all' ||
          (_catalogImportFilter == 'imported' && isImported) ||
          (_catalogImportFilter == 'notImported' && !isImported);
      return matchesTitle && matchesGroup && matchesImportFilter;
    }).toList();

    if (_catalogSortMode == 'rating') {
      filtered.sort((a, b) {
        final aRating = (a['rating'] as num?)?.toDouble() ?? 0.0;
        final bRating = (b['rating'] as num?)?.toDouble() ?? 0.0;
        final diff = bRating.compareTo(aRating);
        if (diff != 0) return diff;
        final aTitle = a['title'] as String? ?? '';
        final bTitle = b['title'] as String? ?? '';
        return aTitle.compareTo(bTitle);
      });
    }

    return filtered;
  }

  Future<void> _openCatalogRecipeDetail(Map<String, dynamic> data) async {
    final recipeId = data['_id'] as String? ?? '';
    final groupName = data['_groupName'] as String? ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipeId: recipeId,
          isCatalogRecipe: true,
          sourceGroupName: groupName,
        ),
      ),
    );
    _refreshRecipes();
    _fetchCatalogRecipes();
  }

  Widget _buildCatalogListView() {
    if (_catalogLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    final filtered = _filteredCatalogRecipes();
    if (filtered.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                _catalogRecipes.isEmpty
                    ? 'Aucun groupe partagé avec vous.'
                    : 'Aucune recette disponible',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemCount: filtered.length,
        itemBuilder: (_, index) {
          final recipe = filtered[index];
          final prepTime = (recipe['preparationTime'] as num?)?.toInt() ?? 0;
          final cookTime = (recipe['cookingTime'] as num?)?.toInt() ?? 0;
          final servings = (recipe['servings'] as num?)?.toInt() ?? 1;
          final title = recipe['title'] as String? ?? '';
          final groupName = recipe['_groupName'] as String? ?? '';
          final rating = (recipe['rating'] as num?)?.toDouble() ?? 0.0;
          final isImported = _groupRecipeTitles.contains(title.toLowerCase().trim());
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openCatalogRecipeDetail(recipe),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                // Source group badge
                                if (groupName.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5C6BC0).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.group_rounded, size: 12, color: Color(0xFF5C6BC0)),
                                        const SizedBox(width: 4),
                                        Text(
                                          groupName,
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF5C6BC0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isImported)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Dans le groupe',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              recipe['description'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _buildStatItem(
                                  Icons.access_time_rounded,
                                  '${prepTime + cookTime} min',
                                  const Color(0xFF5C6BC0),
                                ),
                                const SizedBox(width: 24),
                                _buildStatItem(
                                  Icons.pie_chart_rounded,
                                  '$servings portions',
                                  const Color(0xFFFF8A65),
                                ),
                                if (rating > 0) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA726).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA726)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1)}/5',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFFFA726),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 18,
                        color: Colors.black26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportFilterChip(String value, String label) {
    final selected = _catalogImportFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _catalogImportFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6A5AE0)
              : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF6A5AE0),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(
      IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6A5AE0)
              : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF6A5AE0)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(IconData icon, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6A5AE0) : const Color(0xFF6A5AE0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF6A5AE0)),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF6A5AE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
