import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/repositories/firebase_stats_repository.dart';
import '../../../data/repositories/group_repository.dart';

part 'admin_group_dialogs.dart';
part 'admin_group_actions.dart';
part 'admin_users.dart';
part 'admin_emails.dart';

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
