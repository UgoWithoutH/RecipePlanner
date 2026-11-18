// ignore_for_file: invalid_use_of_protected_member
part of 'ingredients_page.dart';

const _equivalenceAccent = Color(0xFF6A5AE0);

extension _IngredientEquivalencesUi on _IngredientsPageState {
  String _equivalenceLabel(IngredientEquivalence e) {
    final target = Unit.labelOf(e.targetCode);
    return '1 ${Unit.labelOf(e.unitCode)} = ${_fmtAmount(e.amount)} $target';
  }

  String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Section « Correspondances » (ex : 1 paquet = 200 g) d'un ingrédient.
  Widget _buildEquivalencesEditor(
    BuildContext context,
    List<IngredientEquivalence> equivalences,
    void Function(VoidCallback) setStateDialog,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Correspondances',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          'Permet de convertir une unité (ex : paquet) pour cet ingrédient '
          'dans le plan de repas et la liste de courses.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 10),
        ...equivalences.map(
          (e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: _equivalenceAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: _equivalenceAccent.withOpacity(0.18),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: _equivalenceAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_equivalenceLabel(e),
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                InkWell(
                  onTap: () => setStateDialog(() => equivalences.remove(e)),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.red[400]),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final added = await _showEquivalenceDialog(context);
              if (added == null) return;
              setStateDialog(() {
                equivalences.removeWhere((e) => e.unitCode == added.unitCode);
                equivalences.add(added);
              });
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Ajouter une correspondance',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _equivalenceAccent,
              side: BorderSide(color: _equivalenceAccent.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
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

    final result = await showDialog<IngredientEquivalence>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateEq) {
          final amount = double.tryParse(
              amountController.text.trim().replaceAll(',', '.'));
          final valid = amount != null && amount > 0 && unit != target;
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Nouvelle correspondance',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1 unité…',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  _unitDropdown(unit, units, (u) => setStateEq(() => unit = u)),
                  const SizedBox(height: 16),
                  Text('…est égale à',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setStateEq(() {}),
                          style: GoogleFonts.poppins(),
                          decoration: InputDecoration(
                            hintText: '200',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: _unitDropdown(
                            target, units, (u) => setStateEq(() => target = u)),
                      ),
                    ],
                  ),
                ],
              ),
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
                          color: valid ? _equivalenceAccent : Colors.grey))),
            ],
          );
        },
      ),
    );
    amountController.dispose();
    return result;
  }

  Widget _unitDropdown(
      Unit value, List<Unit> units, ValueChanged<Unit> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Unit>(
          value: units.contains(value) ? value : null,
          isExpanded: true,
          dropdownColor: Colors.white,
          items: units
              .map((u) => DropdownMenuItem<Unit>(
                    value: u,
                    child: Text(u.label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 14)),
                  ))
              .toList(),
          onChanged: (u) {
            if (u != null) onChanged(u);
          },
        ),
      ),
    );
  }
}
