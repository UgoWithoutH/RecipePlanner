// ignore_for_file: invalid_use_of_protected_member
part of 'admin_page.dart';

extension _AdminGroupActions on _AdminPageState {
  Future<void> _resetGroupStats(DocumentSnapshot group) async {
    final groupData = group.data() as Map<String, dynamic>;
    final groupName = (groupData['name'] as String? ?? '').isNotEmpty
        ? groupData['name'] as String
        : 'ce groupe';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bar_chart_rounded,
                    color: Colors.orange.shade700, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Réinitialiser les statistiques ?',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Les compteurs d\'utilisation des recettes et des ingrédients de "$groupName" seront remis à zéro. Cette action est irréversible.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.black45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Annuler',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Réinitialiser',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;

    // Fetch recipes and ingredients in parallel for this group.
    final batch = FirebaseFirestore.instance.batch();
    final snapshots = await Future.wait([
      FirebaseFirestore.instance
          .collection('recipes')
          .where('groupId', isEqualTo: group.id)
          .get(),
      FirebaseFirestore.instance
          .collection('ingredients')
          .where('groupId', isEqualTo: group.id)
          .get(),
    ]);
    final recipesSnap = snapshots[0];
    final ingredientsSnap = snapshots[1];

    for (final doc in recipesSnap.docs) {
      batch.update(doc.reference, {'usageCount': 0});
    }
    for (final doc in ingredientsSnap.docs) {
      batch.update(doc.reference, {'usageCount': 0});
    }

    await batch.commit();
    FirebaseStatsRepository.instance.invalidateCache();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Statistiques réinitialisées pour "$groupName".',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  Future<void> _deleteGroupHistory(DocumentSnapshot group) async {
    final groupData = group.data() as Map<String, dynamic>;
    final groupName = (groupData['name'] as String? ?? '').isNotEmpty
        ? groupData['name'] as String
        : 'ce groupe';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.history_toggle_off_rounded,
                    color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Supprimer l\'historique ?',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tout l\'historique des repas passés de "$groupName" sera supprimé définitivement. Cette action est irréversible.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.black45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Annuler',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Supprimer',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    final historySnap = await FirebaseFirestore.instance
        .collection('mealPlanHistory')
        .where('groupId', isEqualTo: group.id)
        .get();

    if (historySnap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aucun historique à supprimer pour "$groupName".',
                style: GoogleFonts.poppins()),
            backgroundColor: _primary,
          ),
        );
      }
      return;
    }

    // Supprimer l'historique du groupe + remettre les compteurs à zéro
    // uniquement pour les recettes/ingrédients présents dans cet historique.
    final db = FirebaseFirestore.instance;
    final recipeIdsSeen = <String>{};
    for (final doc in historySnap.docs) {
      final data = doc.data();
      final mealsData = (data['meals'] as List<dynamic>?) ?? [];
      for (final m in mealsData) {
        final mealData = m as Map<String, dynamic>;
        if (mealData['isLeftoverMeal'] as bool? ?? false) continue;
        final recipeId = mealData['recipeId'] as String? ?? '';
        if (recipeId.isNotEmpty) recipeIdsSeen.add(recipeId);
      }
    }

    final ingredientIdsSeen = <String>{};
    for (final recipeId in recipeIdsSeen) {
      try {
        final recipeDoc = await db.collection('recipes').doc(recipeId).get();
        if (!recipeDoc.exists) continue;
        final ingredients =
            (recipeDoc.data()?['ingredients'] as List<dynamic>?) ?? [];
        for (final ing in ingredients) {
          final ingId =
              (ing as Map<String, dynamic>)['ingredientId'] as String? ?? '';
          if (ingId.isNotEmpty) ingredientIdsSeen.add(ingId);
        }
      } catch (_) {}
    }

    final batch = db.batch();
    for (final doc in historySnap.docs) {
      batch.delete(doc.reference);
    }
    for (final recipeId in recipeIdsSeen) {
      batch.update(db.collection('recipes').doc(recipeId), {'usageCount': 0});
    }
    for (final ingredientId in ingredientIdsSeen) {
      batch.update(
          db.collection('ingredients').doc(ingredientId), {'usageCount': 0});
    }
    await batch.commit();

    FirebaseStatsRepository.instance.invalidateCache();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Historique supprimé pour "$groupName".',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  Future<void> _confirmDeleteGroup(DocumentSnapshot group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline,
                    color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Supprimer ce groupe ?',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Cette action est irréversible.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.black45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Annuler',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Supprimer',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm == true) {
      await group.reference.delete();
      setState(() {});
    }
  }

  // -------------------------------------------------------------------------
  // Shared group card
  // -------------------------------------------------------------------------
  Widget _buildGroupCard(DocumentSnapshot group, List<Map<String, dynamic>> allUsers,
      {required bool canEdit, required bool canDelete, bool canEditCatalogueOnly = false, bool canResetStats = false, bool canClearHistory = false}) {
    final groupData = group.data() as Map<String, dynamic>;
    final rawMembers = groupData['members'];
    List<String> memberIds = [];
    if (rawMembers is List) {
      memberIds = rawMembers.whereType<String>().toList();
    } else if (rawMembers is String) {
      memberIds = [rawMembers];
    }
    final members = allUsers.where((u) => memberIds.contains(u['id'])).toList();
    final groupName = (groupData['name'] as String? ?? '').isNotEmpty
        ? groupData['name'] as String
        : 'Groupe sans nom';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.group, color: _primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    groupName,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                if (canEdit)
                  _IconActionButton(
                    icon: Icons.edit_outlined,
                    color: _primary,
                    backgroundColor: _primaryLight,
                    onTap: () => _showGroupDialog(group: group),
                  ),
                if (canResetStats) ...[
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.bar_chart_rounded,
                    color: Colors.orange.shade700,
                    backgroundColor: Colors.orange.shade50,
                    onTap: () => _resetGroupStats(group),
                  ),
                ],
                if (canClearHistory) ...[
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.history_toggle_off_rounded,
                    color: Colors.red.shade400,
                    backgroundColor: Colors.red.shade50,
                    onTap: () => _deleteGroupHistory(group),
                  ),
                ],
                if (canEditCatalogueOnly) ...[  
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.menu_book_rounded,
                    color: _primary,
                    backgroundColor: _primaryLight,
                    onTap: () => _showCatalogueOnlyDialog(group),
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.delete_outline,
                    color: Colors.red.shade400,
                    backgroundColor: Colors.red.shade50,
                    onTap: () => _confirmDeleteGroup(group),
                  ),
                ],
              ],
            ),
            if (members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: members.map((u) {
                  final name = u['name'].toString().isNotEmpty ? u['name'] as String : u['email'] as String;
                  final isRoleAdmin = u['role'] == 'admin';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isRoleAdmin ? _primaryLight : const Color(0xFFF3F3F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRoleAdmin ? Icons.shield_outlined : Icons.person_outline,
                          size: 12,
                          color: isRoleAdmin ? _primary : Colors.black45,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isRoleAdmin ? _primary : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text('Aucun membre', style: GoogleFonts.poppins(fontSize: 12, color: Colors.black38)),
            ],
          ],
        ),
      ),
    );
  }
}
