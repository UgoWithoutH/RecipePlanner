import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/unit.dart';
import '../../core/utils/qty_format.dart';
import '../../data/repositories/firebase_unit_repository.dart';

/// Gestion des unités du groupe et de leurs correspondances (ex : 1 kg = 1000 g).
class UnitsPage extends StatefulWidget {
  const UnitsPage({super.key});

  @override
  State<UnitsPage> createState() => _UnitsPageState();
}

class _UnitsPageState extends State<UnitsPage>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF6A5AE0);

  final FirebaseUnitRepository _repo = FirebaseUnitRepository();
  late final TabController _tabController;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _repo.load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _isUpdating = true);
    try {
      await action();
    } catch (_) {
      _snack('Une erreur est survenue');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Unités ────────────────────────────────────────────────────────────────

  Future<void> _editUnit([Unit? unit]) async {
    final controller = TextEditingController(text: unit?.label ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(unit == null ? 'Nouvelle unité' : 'Modifier l\'unité',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.poppins(),
          decoration: InputDecoration(
            labelText: 'Nom (ex: cl, gousse, botte)',
            labelStyle: GoogleFonts.poppins(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(unit == null ? 'Ajouter' : 'Enregistrer',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _accent)),
          ),
        ],
      ),
    );
    final label = controller.text.trim();
    controller.dispose();
    if (confirmed != true || label.isEmpty) return;

    await _run(() async {
      final ok = unit == null
          ? await _repo.addUnit(label)
          : await _repo.updateUnit(unit.name, label);
      if (!ok) _snack('Une unité "$label" existe déjà');
    });
  }

  Future<void> _deleteUnit(Unit unit) async {
    final linked = UnitRegistry.conversions
        .where((c) => c.fromCode == unit.name || c.toCode == unit.name)
        .length;
    final confirmed = await _confirm(
      title: 'Supprimer "${unit.label}" ?',
      message: 'Les recettes, courses et frigo qui utilisent cette unité '
          'seront affichés en "pièce".'
          '${linked > 0 ? '\n$linked correspondance(s) liée(s) seront aussi supprimées.' : ''}',
    );
    if (confirmed != true) return;
    await _run(() => _repo.deleteUnit(unit.name));
  }

  // ── Correspondances ───────────────────────────────────────────────────────

  Future<void> _editConversion([UnitConversion? existing]) async {
    final units = Unit.values;
    if (units.length < 2) {
      _snack('Créez au moins deux unités');
      return;
    }
    Unit from = (existing != null ? Unit.byName(existing.fromCode) : null) ?? units.first;
    Unit to = (existing != null ? Unit.byName(existing.toCode) : null) ??
        units.firstWhere((u) => u != from);
    bool auto = existing?.autoConvert ?? false;
    final factorController = TextEditingController(
        text: existing != null ? fmtQty(existing.factor) : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
              existing == null ? 'Nouvelle correspondance' : 'Modifier la correspondance',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1 unité…', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                _unitDropdown(from, units, (u) => setStateDialog(() => from = u)),
                const SizedBox(height: 16),
                Text('…est égale à', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: factorController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(),
                      decoration: InputDecoration(
                        hintText: '1000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _unitDropdown(to, units, (u) => setStateDialog(() => to = u)),
                  ),
                ]),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: _accent,
                  value: auto,
                  onChanged: (v) => setStateDialog(() => auto = v),
                  title: Text('Conversion automatique',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Affiche la quantité en "${from.label}" dès qu\'elle atteint 1 ${from.label}.',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enregistrer',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _accent)),
            ),
          ],
        ),
      ),
    );
    final factor = double.tryParse(factorController.text.trim().replaceAll(',', '.'));
    factorController.dispose();
    if (confirmed != true) return;

    if (from == to || factor == null || factor <= 0) {
      _snack('Choisissez deux unités différentes et une valeur positive');
      return;
    }
    await _run(() async {
      final ok = await _repo.saveConversion(
        replaceId: existing?.id,
        fromCode: from.name,
        toCode: to.name,
        factor: factor,
        autoConvert: auto,
      );
      if (!ok) _snack('Une correspondance existe déjà entre ces deux unités');
    });
  }

  Future<void> _deleteConversion(UnitConversion c) async {
    final confirmed = await _confirm(
      title: 'Supprimer cette correspondance ?',
      message: '${_describe(c)}\nCes unités ne seront plus convertibles entre elles.',
    );
    if (confirmed != true) return;
    await _run(() => _repo.deleteConversion(c.id));
  }

  String _describe(UnitConversion c) =>
      '1 ${Unit.labelOf(c.fromCode)} = ${fmtQty(c.factor)} ${Unit.labelOf(c.toCode)}';

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _unitDropdown(Unit value, List<Unit> units, ValueChanged<Unit> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Unit>(
          value: value,
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

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Supprimer',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red[400])),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _card({
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: leading,
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _actionButton(Icons.edit_rounded, _accent, onEdit),
          const SizedBox(width: 8),
          _actionButton(Icons.delete_outline_rounded, Colors.red[400]!, onDelete),
        ]),
      ),
    );
  }

  Widget _circleIcon(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: _accent.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(icon, color: _accent, size: 20),
      );

  Widget _unitsTab() {
    final units = Unit.values;
    if (units.isEmpty) {
      return Center(child: Text('Aucune unité', style: GoogleFonts.poppins(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      itemCount: units.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final unit = units[i];
        return _card(
          leading: _circleIcon(Icons.straighten_rounded),
          title: unit.label,
          onEdit: () => _editUnit(unit),
          onDelete: () => _deleteUnit(unit),
        );
      },
    );
  }

  Widget _conversionsTab() {
    final conversions = [...UnitRegistry.conversions]
      ..sort((a, b) => _describe(a).compareTo(_describe(b)));
    if (conversions.isEmpty) {
      return Center(
          child: Text('Aucune correspondance', style: GoogleFonts.poppins(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      itemCount: conversions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c = conversions[i];
        return _card(
          leading: _circleIcon(Icons.swap_horiz_rounded),
          title: _describe(c),
          subtitle: c.autoConvert ? 'Conversion automatique' : null,
          onEdit: () => _editConversion(c),
          onDelete: () => _deleteConversion(c),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final onUnitsTab = _tabController.index == 0;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Unités',
            style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _accent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _accent,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Unités'), Tab(text: 'Correspondances')],
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [_unitsTab(), _conversionsTab()],
                ),
          if (_isUpdating)
            Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator())),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: FloatingActionButton.extended(
          onPressed: () => onUnitsTab ? _editUnit() : _editConversion(),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text(onUnitsTab ? 'Nouvelle unité' : 'Nouvelle correspondance',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
