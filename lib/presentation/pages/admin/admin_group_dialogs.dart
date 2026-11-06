// ignore_for_file: invalid_use_of_protected_member
part of 'admin_page.dart';

extension _AdminGroupDialogs on _AdminPageState {
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
}
