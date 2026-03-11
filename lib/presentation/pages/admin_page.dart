import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

const _primary = Color(0xFF6A5AE0);
const _primaryLight = Color(0xFFEEECFB);

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
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
    List<Map<String, dynamic>> allUsers = await _fetchAllUsers();
    allUsers.sort((a, b) =>
        a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));

    final allGroupsSnap =
        await FirebaseFirestore.instance.collection('groups').get();
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
                            };
                            if (group == null) {
                              await FirebaseFirestore.instance
                                  .collection('groups')
                                  .add(data);
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
          );
        },
      ),
    );
    searchController.dispose();
    nameController.dispose();
    if (result == true) setState(() {});
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
          'Administration',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('groups').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _primary),
            );
          }
          final groups = snapshot.data?.docs ?? [];
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: _primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_outlined,
                        color: _primary, size: 48),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Aucun groupe pour l\'instant',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Créez votre premier groupe\nen appuyant sur +',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.black45),
                  ),
                ],
              ),
            );
          }
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchAllUsers(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _primary));
              }
              final allUsers = userSnapshot.data ?? [];
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final groupData = group.data() as Map<String, dynamic>;
                  final rawMembers = groupData['members'];
                  List<String> memberIds = [];
                  if (rawMembers is List) {
                    memberIds = rawMembers.whereType<String>().toList();
                  } else if (rawMembers is String) {
                    memberIds = [rawMembers];
                  }
                  final members = allUsers
                      .where((u) => memberIds.contains(u['id']))
                      .toList();
                  final groupName = (groupData['name'] as String? ?? '').isNotEmpty
                      ? groupData['name'] as String
                      : 'Groupe sans nom';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _primary.withOpacity(0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
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
                                decoration: BoxDecoration(
                                  color: _primaryLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.group,
                                    color: _primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ),
                              _IconActionButton(
                                icon: Icons.edit_outlined,
                                color: _primary,
                                backgroundColor: _primaryLight,
                                onTap: () => _showGroupDialog(group: group),
                              ),
                              const SizedBox(width: 8),
                              _IconActionButton(
                                icon: Icons.delete_outline,
                                color: Colors.red.shade400,
                                backgroundColor: Colors.red.shade50,
                                onTap: () => _confirmDeleteGroup(group),
                              ),
                            ],
                          ),
                          if (members.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Divider(
                                height: 1,
                                color: Colors.grey.shade100),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: members.map((u) {
                                final name = u['name'].toString().isNotEmpty
                                    ? u['name'] as String
                                    : u['email'] as String;
                                final isAdmin = u['role'] == 'admin';
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAdmin
                                        ? _primaryLight
                                        : const Color(0xFFF3F3F3),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isAdmin
                                            ? Icons.shield_outlined
                                            : Icons.person_outline,
                                        size: 12,
                                        color: isAdmin
                                            ? _primary
                                            : Colors.black45,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        name,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isAdmin
                                              ? _primary
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'Aucun membre',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.black38),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
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
