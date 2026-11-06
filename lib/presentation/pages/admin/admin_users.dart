// ignore_for_file: invalid_use_of_protected_member
part of 'admin_page.dart';

extension _AdminUsers on _AdminPageState {
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
}
