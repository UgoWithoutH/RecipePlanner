import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/firebase_stats_repository.dart';
import '../../data/repositories/group_repository.dart';

const _primary = Color(0xFF6A5AE0);
const _primaryLight = Color(0xFFEEECFB);

class AdminPage extends StatefulWidget {
  final bool isAdmin;
  const AdminPage({super.key, this.isAdmin = false});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchAllUsers() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    return snap.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'email': data['email'] ?? '',
        'role': data['role'] ?? 'user',
      };
    }).toList();
  }

  Future<void> _showGroupDialog({DocumentSnapshot? group}) async {
    // Fetch users and groups in parallel — they are independent
    final results = await Future.wait([
      _fetchAllUsers(),
      FirebaseFirestore.instance.collection('groups').get(),
    ]);
    List<Map<String, dynamic>> allUsers = results[0] as List<Map<String, dynamic>>;
    allUsers.sort((a, b) =>
        a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));

    final allGroupsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final currentGroupId = group?.id;
    final Map<String, String> userToGroup = {};
    for (final g in allGroupsSnap.docs) {
      final gData = g.data() as Map<String, dynamic>;
      final members = gData['members'];
      List<String> ids = [];
      if (members is List) {
        ids = members.whereType<String>().toList();
      } else if (members is String) {
        ids = [members];
      }
      for (final uid in ids) {
        userToGroup[uid] = g.id;
      }
    }

    final groupData = group?.data() as Map<String, dynamic>?;
    final nameController =
        TextEditingController(text: groupData?['name'] ?? '');
    String? nameError;
    Set<String> selectedUserIds;
    if (groupData != null) {
      final rawMembers = groupData['members'];
      if (rawMembers is List) {
        selectedUserIds = Set<String>.from(rawMembers.whereType<String>());
      } else if (rawMembers is String) {
        selectedUserIds = {rawMembers};
      } else {
        selectedUserIds = {};
      }
    } else {
      selectedUserIds = {};
    }

    // Catalogue: which groups' recipes are visible to this group
    // Other groups (excluding the current one)
    final otherGroups = allGroupsSnap.docs.where((g) => g.id != currentGroupId).toList();
    Set<String> selectedVisibleGroupIds;
    if (groupData != null) {
      final rawVisible = groupData['visibleGroupIds'];
      if (rawVisible is List) {
        selectedVisibleGroupIds = Set<String>.from(rawVisible.whereType<String>());
      } else {
        selectedVisibleGroupIds = {};
      }
    } else {
      // New group: default to seeing all other groups' recipes
      selectedVisibleGroupIds = otherGroups.map((g) => g.id).toSet();
    }

    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredUsers = allUsers;
    void updateSearch(String value) {
      final q = value.toLowerCase();
      filteredUsers = allUsers.where((user) {
        return user['name'].toString().toLowerCase().contains(q) ||
            user['email'].toString().toLowerCase().contains(q);
      }).toList();
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.group,
                            color: _primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          group == null ? 'Créer un groupe' : 'Éditer le groupe',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Group name field
                  Text(
                    'Nom du groupe',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ex : Famille Dupont',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: Colors.black26),
                      errorText: nameError,
                      filled: true,
                      fillColor: const Color(0xFFF7F6FF),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _primary, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: Colors.red.shade400, width: 1.5),
                      ),
                    ),
                    onChanged: (_) {
                      if (nameError != null) {
                        setStateDialog(() => nameError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Search field
                  TextField(
                    controller: searchController,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un utilisateur…',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.black38),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.black38),
                      filled: true,
                      fillColor: const Color(0xFFF3F3F3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) {
                      updateSearch(value);
                      setStateDialog(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Membres du groupe',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Members list
                  SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: filteredUsers.map((user) {
                          final userId = user['id'] as String;
                          final alreadyInGroup =
                              userToGroup.containsKey(userId) &&
                                  userToGroup[userId] != currentGroupId;
                          final isSelected = selectedUserIds.contains(userId);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _primaryLight
                                  : (alreadyInGroup
                                      ? Colors.grey.shade100
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? _primary.withOpacity(0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            child: CheckboxListTile(
                              dense: true,
                              activeColor: _primary,
                              checkColor: Colors.white,
                              value: isSelected,
                              title: Text(
                                user['name'].toString().isNotEmpty
                                    ? user['name']
                                    : user['email'],
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: alreadyInGroup
                                      ? Colors.black38
                                      : Colors.black87,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    user['email'],
                                    style: GoogleFonts.poppins(
                                        fontSize: 11, color: Colors.black38),
                                  ),
                                  if (alreadyInGroup) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Déjà dans un groupe',
                                        style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: Colors.orange.shade700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              onChanged: alreadyInGroup
                                  ? null
                                  : (val) {
                                      if (val == true) {
                                        selectedUserIds.add(userId);
                                      } else {
                                        selectedUserIds.remove(userId);
                                      }
                                      setStateDialog(() {});
                                    },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Catalogue section
                  if (otherGroups.isNotEmpty) ...[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: _primary, size: 16),
                      ),
                      title: Text(
                        'Catalogue visible',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      subtitle: Text(
                        '${selectedVisibleGroupIds.length} groupe(s) partag\u00e9(s)',
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.black38),
                      ),
                      children: otherGroups.map((g) {
                        final gData = g.data();
                        final gName = (gData['name'] as String? ?? '').isNotEmpty
                            ? gData['name'] as String
                            : 'Groupe sans nom';
                        final isChecked = selectedVisibleGroupIds.contains(g.id);
                        return CheckboxListTile(
                          dense: true,
                          activeColor: _primary,
                          checkColor: Colors.white,
                          value: isChecked,
                          title: Text(
                            gName,
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          onChanged: (val) {
                            if (val == true) {
                              selectedVisibleGroupIds.add(g.id);
                            } else {
                              selectedVisibleGroupIds.remove(g.id);
                            }
                            setStateDialog(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.black12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            'Annuler',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              setStateDialog(() => nameError =
                                  'Le nom est obligatoire');
                              return;
                            }
                            final data = {
                              'members': selectedUserIds.toList(),
                              'name': name,
                              'visibleGroupIds': selectedVisibleGroupIds.toList(),
                            };
                            if (group == null) {
                              final newDoc = await FirebaseFirestore.instance
                                  .collection('groups')
                                  .add(data);
                              // Add new group to visibleGroupIds of all existing groups
                              final batch = FirebaseFirestore.instance.batch();
                              for (final existingGroup in allGroupsSnap.docs) {
                                batch.update(existingGroup.reference, {
                                  'visibleGroupIds': FieldValue.arrayUnion([newDoc.id]),
                                });
                              }
                              await batch.commit();
                            } else {
                              await group.reference.update(data);
                            }
                            Navigator.pop(ctx, true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            group == null ? 'Créer' : 'Enregistrer',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
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
    searchController.dispose();
    nameController.dispose();
    if (result == true) setState(() {});
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.isAdmin ? 'Administration' : 'Mon groupe',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: widget.isAdmin
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.group_outlined, size: 18), text: 'Groupes'),
                  Tab(icon: Icon(Icons.manage_accounts_outlined, size: 18), text: 'Utilisateurs'),
                ],
              )
            : null,
      ),
      body: widget.isAdmin
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildAdminBody(),
                _buildUsersBody(),
              ],
            )
          : FutureBuilder<String?>(
              future: GroupRepository.instance.getCurrentGroupId(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _primary));
                }
                final groupId = snap.data;
                if (groupId == null) {
                  return Center(
                    child: Text(
                      'Vous n\'êtes dans aucun groupe.',
                      style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45),
                    ),
                  );
                }
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('groups').doc(groupId).get(),
                  builder: (context, groupSnap) {
                    if (groupSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: _primary));
                    }
                    final groupDoc = groupSnap.data;
                    if (groupDoc == null || !groupDoc.exists) {
                      return Center(
                        child: Text(
                          'Groupe introuvable.',
                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45),
                        ),
                      );
                    }
                    return _buildUserGroupView(groupDoc);
                  },
                );
              },
            ),
      floatingActionButton: widget.isAdmin
          ? _tabController.index == 1
              ? FloatingActionButton.extended(
                  onPressed: _showAddEmailDialog,
                  backgroundColor: _primary,
                  elevation: 3,
                  icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                  label: Text(
                    'Inviter',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                )
              : FloatingActionButton.extended(
                  onPressed: () async {
                    await _showGroupDialog();
                  },
                  backgroundColor: _primary,
                  elevation: 3,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: Text(
                    'Nouveau groupe',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                )
          : null,
    );
  }

  // -------------------------------------------------------------------------
  // Admin body: all groups list
  // -------------------------------------------------------------------------
  Widget _buildAdminBody() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('groups').get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        final groups = snapshot.data?.docs ?? [];
        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(color: _primaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.group_outlined, color: _primary, size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  'Aucun groupe pour l\'instant',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Créez votre premier groupe\nen appuyant sur +',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.black45),
                ),
              ],
            ),
          );
        }
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchAllUsers(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _primary));
            }
            final allUsers = userSnapshot.data ?? [];
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                return _buildGroupCard(
                  groups[index],
                  allUsers,
                  canEdit: true,
                  canDelete: true,
                  canResetStats: true,
                  canClearHistory: true,
                );
              },
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // User body: own group only, edit allowed, no delete/create
  // -------------------------------------------------------------------------
  Widget _buildUserGroupView(DocumentSnapshot groupDoc) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchAllUsers(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        final allUsers = userSnapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            _buildGroupCard(
              groupDoc,
              allUsers,
              canEdit: false,
              canDelete: false,
              canEditCatalogueOnly: true,
              canResetStats: true,
              canClearHistory: true,
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Catalogue-only dialog (for non-admin users)
  // -------------------------------------------------------------------------
  Future<void> _showCatalogueOnlyDialog(DocumentSnapshot group) async {
    final allGroupsSnap = await FirebaseFirestore.instance.collection('groups').get();
    final currentGroupId = group.id;
    final groupData = group.data() as Map<String, dynamic>;

    final otherGroups = allGroupsSnap.docs.where((g) => g.id != currentGroupId).toList();
    if (otherGroups.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aucun autre groupe disponible.', style: GoogleFonts.poppins()),
            backgroundColor: _primary,
          ),
        );
      }
      return;
    }

    final rawVisible = groupData['visibleGroupIds'];
    Set<String> selectedVisibleGroupIds;
    if (rawVisible is List) {
      selectedVisibleGroupIds = Set<String>.from(rawVisible.whereType<String>());
    } else {
      selectedVisibleGroupIds = {};
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.menu_book_rounded, color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Catalogues visibles',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choisissez les groupes dont vous voulez voir les recettes dans le catalogue.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 20),
                ...otherGroups.map((g) {
                  final gData = g.data();
                  final gName = (gData['name'] as String? ?? '').isNotEmpty
                      ? gData['name'] as String
                      : 'Groupe sans nom';
                  final isChecked = selectedVisibleGroupIds.contains(g.id);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isChecked ? _primaryLight : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isChecked ? _primary.withOpacity(0.3) : Colors.black12,
                      ),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      activeColor: _primary,
                      checkColor: Colors.white,
                      value: isChecked,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(gName,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isChecked ? _primary : Colors.black87)),
                      onChanged: (val) {
                        if (val == true) {
                          selectedVisibleGroupIds.add(g.id);
                        } else {
                          selectedVisibleGroupIds.remove(g.id);
                        }
                        setStateDialog(() {});
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black12),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Annuler',
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await group.reference.update({'visibleGroupIds': selectedVisibleGroupIds.toList()});
                          Navigator.pop(ctx, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Enregistrer',
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Users body: registered users + pending invitations
  // -------------------------------------------------------------------------
  Widget _buildUsersBody() {
    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').get(),
        FirebaseFirestore.instance.collection('groups').get(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        final groupsSnap = snapshot.data?[1];

        final groupMap = <String, String>{};
        if (groupsSnap != null) {
          for (final g in groupsSnap.docs) {
            final gData = g.data() as Map<String, dynamic>;
            groupMap[g.id] = (gData['name'] as String? ?? '').isNotEmpty
                ? gData['name'] as String
                : 'Groupe sans nom';
          }
        }

        final allDocs = snapshot.data?[0].docs ?? [];
        final usersList = allDocs.map((u) {
          final data = u.data() as Map<String, dynamic>;
          return {'id': u.id, 'name': data['name'] ?? '', 'email': data['email'] ?? '', 'role': data['role'] ?? 'user', 'groupId': data['groupId']};
        }).toList()
          ..sort((a, b) {
            final aName = a['name'].toString();
            final bName = b['name'].toString();
            if (aName.isEmpty && bName.isNotEmpty) return 1;
            if (aName.isNotEmpty && bName.isEmpty) return -1;
            return aName.toLowerCase().compareTo(bName.toLowerCase());
          });

        if (usersList.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(color: _primaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.people_outline, color: _primary, size: 48),
                ),
                const SizedBox(height: 20),
                Text('Aucun utilisateur',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                const SizedBox(height: 6),
                Text('Ajoutez des utilisateurs en appuyant sur +',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.black45)),
              ],
            ),
          );
        }

        final registeredUsers = usersList.where((u) => u['name'].toString().isNotEmpty).toList();
        final authorizedUsers = usersList.where((u) => u['name'].toString().isEmpty).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            if (registeredUsers.isNotEmpty) ...[  
              _SectionHeader(title: 'Inscrits', count: registeredUsers.length),
              const SizedBox(height: 8),
              ...registeredUsers.map((user) => _buildUserRoleCard(user)),
              const SizedBox(height: 16),
            ],
            if (authorizedUsers.isNotEmpty) ...[  
              _SectionHeader(title: 'Autorisés (non connectés)', count: authorizedUsers.length),
              const SizedBox(height: 8),
              ...authorizedUsers.map((user) {
                final groupId = user['groupId'] as String?;
                return _buildEmailCard(
                  null,
                  user['email'] as String,
                  groupId != null ? groupMap[groupId] : null,
                  userId: user['id'] as String,
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildUserRoleCard(Map<String, dynamic> user) {
    final isRoleAdmin = user['role'] == 'admin';
    final name = user['name'].toString().isNotEmpty ? user['name'] as String : user['email'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isRoleAdmin ? _primaryLight : const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isRoleAdmin ? Icons.shield_outlined : Icons.person_outline,
                color: isRoleAdmin ? _primary : Colors.black45,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                  Text(user['email'] as String,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.black38)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showChangeRoleDialog(user),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isRoleAdmin ? _primaryLight : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRoleAdmin ? _primary.withOpacity(0.4) : Colors.black12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isRoleAdmin ? 'Admin' : 'Utilisateur',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isRoleAdmin ? _primary : Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more, size: 14, color: isRoleAdmin ? _primary : Colors.black45),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _IconActionButton(
              icon: Icons.delete_outline,
              color: Colors.red.shade400,
              backgroundColor: Colors.red.shade50,
              onTap: () => _confirmDeleteUser(user),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final name = user['name'].toString().isNotEmpty ? user['name'] as String : user['email'] as String;
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
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.person_remove_outlined, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Supprimer cet utilisateur ?',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: GoogleFonts.poppins(fontSize: 13, color: _primary, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'L\'utilisateur sera retiré de son groupe et ne pourra plus accéder à l\'application.',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Supprimer',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
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

    final userId = user['id'] as String;

    // Remove user from their group
    final groupSnap = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: userId)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in groupSnap.docs) {
      batch.update(doc.reference, {
        'members': FieldValue.arrayRemove([userId]),
      });
    }
    batch.delete(FirebaseFirestore.instance.collection('users').doc(userId));
    await batch.commit();

    if (mounted) setState(() {});
  }

  Future<void> _showChangeRoleDialog(Map<String, dynamic> user) async {
    final currentRole = user['role'] as String? ?? 'user';
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Changer le rôle',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                user['name'].toString().isNotEmpty ? user['name'] as String : user['email'] as String,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black45),
              ),
              const SizedBox(height: 20),
              _RoleOption(
                label: 'Administrateur',
                description: 'Accès complet : groupes, stats, utilisateurs',
                icon: Icons.shield_outlined,
                color: _primary,
                backgroundColor: _primaryLight,
                isSelected: currentRole == 'admin',
                onTap: () => Navigator.pop(ctx, 'admin'),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                label: 'Utilisateur',
                description: 'Accès à son groupe uniquement',
                icon: Icons.person_outline,
                color: Colors.black54,
                backgroundColor: const Color(0xFFF3F3F3),
                isSelected: currentRole == 'user',
                onTap: () => Navigator.pop(ctx, 'user'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (newRole == null || newRole == currentRole) return;
    await FirebaseFirestore.instance.collection('users').doc(user['id'] as String).update({'role': newRole});
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // (dead code – removed)
  // ignore: unused_element
  Widget _buildEmailsBody_unused() {
    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending').get(),
        FirebaseFirestore.instance.collection('groups').get(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _primary));
        }
        final docs = snapshot.data?[0].docs ?? [];
        final groupsSnap = snapshot.data?[1];
        final groupMap = <String, String>{};
        if (groupsSnap != null) {
          for (final g in groupsSnap.docs) {
            final gData = g.data() as Map<String, dynamic>;
            groupMap[g.id] = (gData['name'] as String? ?? '').isNotEmpty
                ? gData['name'] as String
                : 'Groupe sans nom';
          }
        }
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(color: _primaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.email_outlined, color: _primary, size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  'Aucun email autorisé',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ajoutez un email en appuyant sur +',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.black45),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final email = data['email'] as String? ?? '';
            final groupId = data['groupId'] as String?;
            final groupName = groupId != null ? groupMap[groupId] : null;
            return _buildEmailCard(doc, email, groupName, userId: doc.id);
          },
        );
      },
    );
  }

  Widget _buildEmailCard(DocumentSnapshot? doc, String email, String? groupName, {String? userId}) {
    final id = userId ?? doc?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.email_outlined, color: _primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                  ),
                  if (groupName != null) ...[  
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.group_outlined, size: 12, color: Colors.black38),
                        const SizedBox(width: 4),
                        Text(
                          groupName,
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.black45),
                        ),
                      ],
                    ),
                  ] else ...[  
                    const SizedBox(height: 2),
                    Text(
                      'Aucun groupe assigné',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ],
              ),
            ),
            _IconActionButton(
              icon: Icons.delete_outline,
              color: Colors.red.shade400,
              backgroundColor: Colors.red.shade50,
              onTap: () => _confirmDeleteEmail(id, email),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEmail(String? userId, String email) async {
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
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Supprimer cet email ?',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                email,
                style: GoogleFonts.poppins(fontSize: 13, color: _primary, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Cette action est irréversible.',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black45),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Annuler', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Supprimer',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm == true && userId != null) {
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAddEmailDialog() async {
    final emailController = TextEditingController();
    String? emailError;
    String? selectedGroupId;
    final groupsSnap = await FirebaseFirestore.instance.collection('groups').get();
    final groups = groupsSnap.docs;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.email_outlined, color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ajouter un email',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cet email pourra se connecter et sera assigné au groupe choisi.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 20),
                Text('Adresse email',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 6),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'exemple@email.com',
                    hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.black26),
                    errorText: emailError,
                    prefixIcon: const Icon(Icons.alternate_email, size: 18, color: Colors.black38),
                    filled: true,
                    fillColor: const Color(0xFFF7F6FF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _primary, width: 1.5)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5)),
                  ),
                  onChanged: (_) {
                    if (emailError != null) setStateDialog(() => emailError = null);
                  },
                ),
                const SizedBox(height: 16),
                Text('Groupe assigné (optionnel)',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: selectedGroupId,
                      isExpanded: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      borderRadius: BorderRadius.circular(14),
                      style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                      hint: Text('Aucun groupe', style: GoogleFonts.poppins(fontSize: 14, color: Colors.black38)),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Aucun groupe',
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45)),
                        ),
                        ...groups.map((g) {
                          final gData = g.data() as Map<String, dynamic>;
                          final gName = (gData['name'] as String? ?? '').isNotEmpty
                              ? gData['name'] as String
                              : 'Groupe sans nom';
                          return DropdownMenuItem<String?>(
                            value: g.id,
                            child: Text(gName, style: GoogleFonts.poppins(fontSize: 14)),
                          );
                        }),
                      ],
                      onChanged: (val) => setStateDialog(() => selectedGroupId = val),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black12),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Annuler',
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final email = emailController.text.trim().toLowerCase();
                          if (email.isEmpty || !email.contains('@')) {
                            setStateDialog(() => emailError = 'Email invalide');
                            return;
                          }
                          final existing = await FirebaseFirestore.instance
                              .collection('users')
                              .where('email', isEqualTo: email)
                              .limit(1)
                              .get();
                          if (existing.docs.isNotEmpty) {
                            setStateDialog(() => emailError = 'Cet email existe déjà');
                            return;
                          }
                          final data = <String, dynamic>{
                            'email': email,
                            'name': '',
                            'role': 'user',
                            if (selectedGroupId != null) 'groupId': selectedGroupId,
                          };
                          await FirebaseFirestore.instance.collection('users').add(data);
                          Navigator.pop(ctx, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Ajouter',
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    emailController.dispose();
    if (result == true && mounted) setState(() {});
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

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black38,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: _primary),
          ),
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? backgroundColor : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.black12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isSelected ? color : Colors.black38, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? color : Colors.black54,
                      )),
                  Text(description,
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.black38)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
