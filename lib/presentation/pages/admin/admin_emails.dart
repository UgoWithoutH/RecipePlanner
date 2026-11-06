// ignore_for_file: invalid_use_of_protected_member
part of 'admin_page.dart';

extension _AdminEmails on _AdminPageState {
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
}
