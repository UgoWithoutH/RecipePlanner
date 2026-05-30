import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Resolves and caches the Firestore group document ID for the current user.
/// A group document lives in the `groups` collection and has a `members` field
/// that is an array of Firebase Auth UIDs.
class GroupRepository {
  static final GroupRepository instance = GroupRepository._();
  GroupRepository._();

  /// In-memory cache: uid -> groupId. Cleared on sign-out via [clearCache].
  final Map<String, String> _groupIdCache = {};

  /// Clears the cached groupId (call on sign-out or group membership change).
  void clearCache() => _groupIdCache.clear();

  /// Returns the group document ID for the currently authenticated user,
  /// or null if no matching group is found.
  /// Result is cached in-memory for the session duration.
  Future<String?> getCurrentGroupId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    if (_groupIdCache.containsKey(uid)) return _groupIdCache[uid];

    final snap = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final groupId = snap.docs.first.id;
    _groupIdCache[uid] = groupId;
    return groupId;
  }

  /// Returns the list of member UIDs for the current user's group.
  Future<List<String>> getGroupMemberIds() async {
    final groupId = await getCurrentGroupId();
    if (groupId == null) return [];

    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();

    if (!doc.exists) return [];
    return List<String>.from(doc.get('members') ?? []);
  }
}
