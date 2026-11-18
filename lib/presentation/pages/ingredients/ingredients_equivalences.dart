// ignore_for_file: invalid_use_of_protected_member
part of 'ingredients_page.dart';

extension _IngredientEquivalencesUi on _IngredientsPageState {
  String _equivalenceLabel(IngredientEquivalence e) {
    final target = Unit.labelOf(e.targetCode);
    return '1 ${Unit.labelOf(e.unitCode)} = ${_fmtAmount(e.amount)} $target';
  }

  String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Section « Équivalences » (ex : 1 paquet = 200 g) d'un ingrédient.
  Widget _buildEquivalencesEditor(
    BuildContext context,
    List<IngredientEquivalence> equivalences,
    void Function(VoidCallback) setStateDialog,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Équivalences',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          'Permet au plan de repas et à la liste de courses de convertir '
          'une unité (ex : paquet) pour cet ingrédient.',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        ...equivalences.map(
          (e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_equivalenceLabel(e),
                      style: GoogleFonts.poppins(fontSize: 13)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey[500]),
                  onPressed: () => setStateDialog(() => equivalences.remove(e)),
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final added = await _showEquivalenceDialog(context);
            if (added == null) return;
            setStateDialog(() {
              equivalences.removeWhere((e) => e.unitCode == added.unitCode);
              equivalences.add(added);
            });
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('Ajouter une équivalence',
              style: GoogleFonts.poppins(fontSize: 13)),
        ),
      ],
    );
  }

  Future<IngredientEquivalence?> _showEquivalenceDialog(
      BuildContext context) async {
    final units = Unit.values;
    if (units.length < 2) return null;
    Unit unit = Unit.byName('piece') ?? units.first;
    Unit target = Unit.byName('g') ?? units.firstWhere((u) => u != unit);
    if (unit == target) target = units.firstWhere((u) => u != unit);
    final amountController = TextEditingController();

    return showDialog<IngredientEquivalence>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateEq) {
          final amount = double.tryParse(
              amountController.text.trim().replaceAll(',', '.'));
          final valid = amount != null && amount > 0 && unit != target;
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Nouvelle équivalence',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _unitDropdown('Unité', unit, units,
                    (u) => setStateEq(() => unit = u)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('1 ${unit.label} =',
                        style: GoogleFonts.poppins(fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setStateEq(() {}),
                        style: GoogleFonts.poppins(),
                        decoration: InputDecoration(
                          labelText: 'Quantité',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _unitDropdown('Dans l\'unité', target, units,
                    (u) => setStateEq(() => target = u)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Annuler',
                      style: GoogleFonts.poppins(color: Colors.grey))),
              TextButton(
                  onPressed: valid
                      ? () => Navigator.pop(
                          dialogContext,
                          IngredientEquivalence(
                              unitCode: unit.name,
                              amount: amount,
                              targetCode: target.name))
                      : null,
                  child: Text('Ajouter',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: valid
                              ? const Color(0xFF6A5AE0)
                              : Colors.grey))),
            ],
          );
        },
      ),
    );
  }

  Widget _unitDropdown(String label, Unit value, List<Unit> units,
      ValueChanged<Unit> onChanged) {
    return DropdownButtonFormField<Unit>(
      value: units.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      items: units
          .map((u) => DropdownMenuItem(
              value: u, child: Text(u.label, style: GoogleFonts.poppins())))
          .toList(),
      onChanged: (u) {
        if (u != null) onChanged(u);
      },
    );
  }
}
