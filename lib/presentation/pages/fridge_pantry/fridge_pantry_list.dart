// ignore_for_file: invalid_use_of_protected_member
part of 'fridge_pantry_page.dart';

extension _FridgePantryList on _FridgePantryPageState {
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
}
