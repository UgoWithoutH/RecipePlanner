part of 'ingredients_page.dart';

// =====================================================
// Bottom sheet : recettes pour un ingrédient
// =====================================================
class _RecipesForIngredientSheet extends StatelessWidget {
  final String ingredientName;
  final List<Recipe> recipes;
  final Map<String, int> recipeCounts;
  final double initialChildSize;
  final double maxChildSize;

  const _RecipesForIngredientSheet({
    required this.ingredientName,
    required this.recipes,
    required this.recipeCounts,
    required this.initialChildSize,
    required this.maxChildSize,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        DraggableScrollableSheet(
          initialChildSize: initialChildSize,
          minChildSize: 0.3,
          maxChildSize: maxChildSize,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recettes avec "$ingredientName"',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.black45),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                // Contenu scrollable : deux sections
                Expanded(
                  child: recipes.isEmpty
                      ? Center(
                          child: Text(
                            'Aucune recette utilise cet ingrédient.',
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          children: [
                            // ── Section recettes du groupe ──
                            _SectionHeader(
                              icon: Icons.group_rounded,
                              label: 'Recettes du groupe (${recipes.length})',
                            ),
                            const SizedBox(height: 8),
                            if (recipes.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Aucune recette du groupe.',
                                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                                ),
                              )
                            else
                              ...recipes.map((recipe) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _RecipeItem(
                                  title: recipe.title,
                                  usageCount: recipeCounts[recipe.id],
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailPage(
                                        recipeId: recipe.id,
                                        initialRecipe: recipe,
                                      ),
                                    ),
                                  ),
                                ),
                              )),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6A5AE0)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6A5AE0),
          ),
        ),
      ],
    );
  }
}

class _RecipeItem extends StatelessWidget {
  final String title;
  final int? usageCount;
  final VoidCallback? onTap;
  const _RecipeItem({required this.title, this.usageCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: onTap != null ? const Color(0xFFF5F4FF) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  onTap != null ? Icons.restaurant_menu_rounded : Icons.book_rounded,
                  size: 18,
                  color: onTap != null ? const Color(0xFF6A5AE0) : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF2D2D2D),
                    ),
                  ),
                ),
                if ((usageCount ?? 0) > 0) ...
                  [
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF57C00).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bar_chart_rounded, size: 12, color: Color(0xFFF57C00)),
                          const SizedBox(width: 3),
                          Text(
                            '$usageCount×',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFF57C00),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
