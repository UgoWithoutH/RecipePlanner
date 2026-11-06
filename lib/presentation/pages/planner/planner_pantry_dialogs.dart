// ignore_for_file: invalid_use_of_protected_member
part of 'planner_page.dart';

extension _PlannerPantryDialogs on _PlannerPageState {
  void _showPantrySnapshotDialog() {
    if (_pantrySnapshot.isEmpty) return;

    // Grouper par catégorie, urgents d'abord
    final urgent = _pantrySnapshot.where((i) => i.isUrgent).toList();
    final normal = _pantrySnapshot.where((i) => !i.isUrgent).toList();

    Map<String, List<PantrySnapshotItem>> _group(List<PantrySnapshotItem> items) {
      final m = <String, List<PantrySnapshotItem>>{};
      for (final i in items) {
        final k = i.typeName.isNotEmpty ? i.typeName : 'Autre';
        m.putIfAbsent(k, () => []).add(i);
      }
      for (final k in m.keys) {
        m[k]!.sort((a, b) => a.name.compareTo(b.name));
      }
      return m;
    }

    List<String> _sortedKeys(Map<String, List<PantrySnapshotItem>> g) =>
        g.keys.toList()
          ..sort((a, b) {
            if (a == 'Autre') return 1;
            if (b == 'Autre') return -1;
            return a.compareTo(b);
          });

    final urgentGroups = _group(urgent);
    final normalGroups = _group(normal);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Frigo / Placard de ce plan',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_pantrySnapshot.length} article${_pantrySnapshot.length > 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Snapshot figé au moment de la génération du plan',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400]),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (urgent.isNotEmpty) ...[
                    _buildSnapshotSuperLabel('🔥 Urgents', Colors.orange.shade700),
                    for (final key in _sortedKeys(urgentGroups)) ...[
                      _buildSnapshotCategoryLabel(key),
                      ...urgentGroups[key]!.map(_buildSnapshotItemRow),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (normal.isNotEmpty) ...[
                    if (urgent.isNotEmpty)
                      _buildSnapshotSuperLabel('Normaux', const Color(0xFF6A5AE0)),
                    for (final key in _sortedKeys(normalGroups)) ...[
                      _buildSnapshotCategoryLabel(key),
                      ...normalGroups[key]!.map(_buildSnapshotItemRow),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche le contenu ACTUEL du pantry (utilisé depuis la modale nouveau plan).
  void _showCurrentPantryDialog() {
    // Fallback : si _rawPantryItems n'est pas encore peuplé, utiliser _pantryIngredients
    final items = _rawPantryItems.isNotEmpty
        ? _rawPantryItems
        : _pantryIngredients.map((ri) => PantryItem(
              id: ri.ingredient.id,
              name: ri.ingredient.name,
              ingredientId: ri.ingredient.id,
              quantity: ri.quantity,
              unit: ri.unit,
              isUrgent: _urgentPantryNames.contains(ri.ingredient.name),
              updatedAt: DateTime.now(),
            )).toList();
    if (items.isEmpty) return;

    Map<String, List<PantryItem>> _groupPantry(List<PantryItem> list) {
      final m = <String, List<PantryItem>>{};
      for (final i in list) {
        final k = i.typeName.isNotEmpty ? i.typeName : 'Autre';
        m.putIfAbsent(k, () => []).add(i);
      }
      for (final k in m.keys) m[k]!.sort((a, b) => a.name.compareTo(b.name));
      return m;
    }
    List<String> _sortedKeysPantry(Map<String, List<PantryItem>> g) =>
        g.keys.toList()
          ..sort((a, b) {
            if (a == 'Autre') return 1;
            if (b == 'Autre') return -1;
            return a.compareTo(b);
          });

    final urgent = items.where((i) => i.isUrgent).toList();
    final normal = items.where((i) => !i.isUrgent).toList();
    final urgentGroups = _groupPantry(urgent);
    final normalGroups = _groupPantry(normal);

    Widget buildRow(PantryItem item) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          if (item.isUrgent)
            const Text('🔥', style: TextStyle(fontSize: 13))
          else
            Icon(Icons.circle, size: 6, color: Colors.grey[300]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '${fmtQty(item.quantity)} ${item.unit.label}',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.kitchen_rounded, color: Color(0xFF6A5AE0), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Frigo / Placard',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A5AE0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length} article${items.length > 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A5AE0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'État actuel du frigo/placard',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400]),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (urgent.isNotEmpty) ...[
                    _buildSnapshotSuperLabel('🔥 Urgents', Colors.orange.shade700),
                    for (final key in _sortedKeysPantry(urgentGroups)) ...[
                      _buildSnapshotCategoryLabel(key),
                      ...urgentGroups[key]!.map(buildRow),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (normal.isNotEmpty) ...[
                    if (urgent.isNotEmpty)
                      _buildSnapshotSuperLabel('Normaux', const Color(0xFF6A5AE0)),
                    for (final key in _sortedKeysPantry(normalGroups)) ...[
                      _buildSnapshotCategoryLabel(key),
                      ...normalGroups[key]!.map(buildRow),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotSuperLabel(String label, Color color) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    ),
  );

  static const _categoryPalette = [
    Color(0xFF6A5AE0), // violet
    Color(0xFF4CAF50), // vert
    Color(0xFFFF9800), // orange
    Color(0xFF2196F3), // bleu
    Color(0xFFE91E63), // rose
    Color(0xFF009688), // teal
    Color(0xFFFF5722), // orange foncé
    Color(0xFF9C27B0), // violet foncé
    Color(0xFF795548), // marron
    Color(0xFF607D8B), // bleu-gris
  ];

  Color _categoryColor(String name) {
    if (name.isEmpty || name == 'Autre') return Colors.grey.shade500;
    final idx = name.codeUnits.fold(0, (sum, c) => sum + c) % _categoryPalette.length;
    return _categoryPalette[idx];
  }

  Widget _buildSnapshotCategoryLabel(String label, {Color? color}) {
    final c = color ?? _categoryColor(label);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3, height: 13,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }

  Widget _buildSnapshotItemRow(PantrySnapshotItem item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Row(
      children: [
        if (item.isUrgent)
          const Text('🔥', style: TextStyle(fontSize: 13))
        else
          Icon(Icons.circle, size: 6, color: Colors.grey[300]),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.name,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          '${fmtQty(item.quantity)} ${item.unit.label}',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    ),
  );

  /// Affiche un dialog de confirmation pour modifier le frigo/placard.
  /// Retourne true si l'utilisateur accepte, false/null sinon.
  Future<bool?> _showPantryModificationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required Color color,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: Text('Non', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: Text(confirmLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
