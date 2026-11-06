part of 'shopping_list_page.dart';

class _ShoppingListItemCard extends StatefulWidget {
  final ShoppingItem item;
  final VoidCallback onCheckTap;
  final VoidCallback onEditTap;
  final VoidCallback onDeleteTap;
  final PantrySnapshotItem? pantryMatch;
  final List<RecipeContribution> contributions;
  final String Function(double) formatQuantity;

  const _ShoppingListItemCard({
    required this.item,
    required this.onCheckTap,
    required this.onEditTap,
    required this.onDeleteTap,
    required this.pantryMatch,
    required this.contributions,
    required this.formatQuantity,
  });

  @override
  State<_ShoppingListItemCard> createState() => _ShoppingListItemCardState();
}

class _ShoppingListItemCardState extends State<_ShoppingListItemCard> {
  bool _expanded = false;

  String _formatBase(double base, String displayUnit) {
    final isVolume = displayUnit == 'l' || displayUnit == 'ml';
    final isMass = displayUnit == 'kg' || displayUnit == 'g';
    if (isVolume && base >= 1000) return '${fmtQty(base / 1000)} l';
    if (isVolume) return '${fmtQty(base)} ml';
    if (isMass && base >= 1000) return '${fmtQty(base / 1000)} kg';
    if (isMass) return '${fmtQty(base)} g';
    return '${fmtQty(base)} ${Unit.labelOf(displayUnit)}';
  }

  void _showContributionsSheet(BuildContext context) {
    final item = widget.item;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Row(
                children: [
                  const Icon(Icons.restaurant_menu_rounded,
                      size: 18, color: Color(0xFF6A5AE0)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Recettes du plan de repas',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            Divider(height: 1, color: Colors.grey.withOpacity(0.15)),
            ...widget.contributions.map((c) {
              final qty = c.quantity > 0 && c.unit.isNotEmpty
                  ? '${fmtQty(c.quantity)} ${Unit.labelOf(c.unit)}'
                  : '';
              final canNavigate = c.recipeId.isNotEmpty;
              return InkWell(
                onTap: canNavigate
                    ? () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeDetailPage(recipeId: c.recipeId),
                          ),
                        );
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5AE0).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.menu_book_rounded,
                            size: 18, color: Color(0xFF6A5AE0)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.recipeName,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF1A1A1A)),
                            ),
                            if (qty.isNotEmpty)
                              Text(
                                qty,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ),
                      if (canNavigate)
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.grey[400]),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDetail = !item.isChecked &&
        (item.totalRequiredBase > 0 || widget.pantryMatch != null);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: item.isChecked ? Colors.grey[50] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? const Color(0xFF6A5AE0).withOpacity(0.25)
              : item.isChecked
                  ? Colors.transparent
                  : Colors.grey.withOpacity(0.1),
          width: _expanded ? 1.5 : 1.0,
        ),
        boxShadow: item.isChecked || _expanded
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Zone de coche pleine hauteur — séparée du tap d'expansion
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onCheckTap,
                    child: Container(
                      width: 44,
                      decoration: BoxDecoration(
                        color: item.isChecked
                            ? const Color(0xFF4CAF50).withOpacity(0.08)
                            : Colors.grey[50],
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(15)),
                        border: Border(
                          right: BorderSide(
                            color: item.isChecked
                                ? const Color(0xFF4CAF50).withOpacity(0.25)
                                : Colors.grey.withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: item.isChecked
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey('checked'),
                                  size: 22,
                                  color: Color(0xFF4CAF50),
                                )
                              : Icon(
                                  Icons.check_rounded,
                                  key: const ValueKey('unchecked'),
                                  size: 22,
                                  color: Colors.grey[300],
                                ),
                        ),
                      ),
                    ),
                  ),
                  // Contenu + bouton d'expansion
                  Expanded(
                    child: InkWell(
                      onTap: hasDetail
                          ? () => setState(() => _expanded = !_expanded)
                          : null,
                      borderRadius: _expanded
                          ? const BorderRadius.only(
                              topRight: Radius.circular(15))
                          : const BorderRadius.only(
                              topRight: Radius.circular(15),
                              bottomRight: Radius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 12, bottom: 12, left: 10, right: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: item.isChecked
                                      ? Colors.grey[400]
                                      : const Color(0xFF1A1A1A),
                                  decoration: item.isChecked
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: Colors.grey[400],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (item.quantity > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: item.isChecked
                                      ? Colors.transparent
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${widget.formatQuantity(item.quantity)} ${Unit.labelOf(item.unit)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: item.isChecked
                                        ? Colors.grey[400]
                                        : const Color(0xFF6A5AE0),
                                  ),
                                ),
                              ),
                            if (!item.isChecked &&
                                widget.contributions.isNotEmpty) ...[  
                              const SizedBox(width: 2),
                              GestureDetector(
                                onTap: () =>
                                    _showContributionsSheet(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: Icon(Icons.info_outline_rounded,
                                      size: 20,
                                      color: const Color(0xFF6A5AE0)
                                          .withOpacity(0.55)),
                                ),
                              ),
                            ],
                            if (hasDetail) ...[  
                              const SizedBox(width: 2),
                              AnimatedRotation(
                                turns: _expanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(Icons.expand_more_rounded,
                                    size: 20, color: Colors.grey[400]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded ? _buildDetail() : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );

    return Slidable(
      key: ValueKey(item.name),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.36,
        children: [
          CustomSlidableAction(
            onPressed: (_) => widget.onEditTap(),
            backgroundColor: const Color(0xFF6A5AE0),
            foregroundColor: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.edit_outlined, size: 24, color: Colors.white),
            ),
          ),
          CustomSlidableAction(
            onPressed: (_) => widget.onDeleteTap(),
            backgroundColor: Colors.red[400]!,
            foregroundColor: Colors.white,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.delete_outline_rounded, size: 24, color: Colors.white),
            ),
          ),
        ],
      ),
      child: card,
    );
  }

  Widget _buildDetail() {
    final item = widget.item;
    final pantry = widget.pantryMatch;
    final hasTotal = item.totalRequiredBase > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.withOpacity(0.12)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FF),
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  children: [
                    if (hasTotal)
                      _qRow(
                          'Total requis',
                          _formatBase(item.totalRequiredBase, item.unit),
                          Colors.grey[700]!),
                    if (pantry != null) ...[
                      if (hasTotal) const SizedBox(height: 6),
                      _qRow(
                          'Placard / frigo',
                          '${fmtQty(pantry.quantity)} ${pantry.unit.label}',
                          const Color(0xFF26A69A)),
                    ],
                    if (hasTotal || pantry != null) ...[
                      const SizedBox(height: 6),
                      Divider(
                          height: 1,
                          color: Colors.grey.withOpacity(0.15)),
                      const SizedBox(height: 6),
                    ],
                    _qRow(
                        'À acheter',
                        item.quantity > 0
                            ? '${fmtQty(item.quantity)} ${Unit.labelOf(item.unit)}'
                            : '—',
                        const Color(0xFF6A5AE0),
                        bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qRow(String label, String value, Color color, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[600]))),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// En dehors de la classe _ShoppingListPageState, ajouter ce painter :

class _ArrowTypePainterRight extends CustomPainter {
  final Color color;
  _ArrowTypePainterRight(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
