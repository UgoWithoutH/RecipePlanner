import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kReleaseMode;

import '../../domain/entities/app_user.dart';

/// Handles Google Sign-In, Firebase Authentication, and Firestore access
/// verification. This is the single source of truth for auth in the app.
class GoogleAuthService {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  GoogleAuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream of Firebase authentication state changes.
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Returns the currently signed-in Firebase user, or null.
  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts the Google Sign-In OAuth flow via Firebase Auth, then verifies
  /// that the user's UID exists in the `users` Firestore collection.
  ///
  /// On Web release: triggers a full-page redirect (avoids COOP issues on GitHub Pages).
  ///   The result is handled by [checkRedirectResult] on the next page load.
  /// On Web debug: uses signInWithPopup (redirect doesn't work with Flutter debug server).
  /// On mobile: uses [signInWithProvider].
  ///
  /// Returns an [AppUser] on success (mobile and web debug).
  /// On web release: never returns — the page redirects before the future resolves.
  /// Throws [SignInCancelledException] if the user dismisses the picker.
  /// Throws [AccessDeniedException] if the UID is not in Firestore.
  Future<AppUser> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    // On web (all browsers, all modes): use signInWithPopup.
    // signInWithRedirect is unreliable on GitHub Pages (sub-path deployments
    // cause getRedirectResult() to always return null). Safari/iOS ITP also
    // drops the redirect state. Session persistence is handled via Firebase
    // Auth's localStorage — verifyCurrentUser() restores it on page reload.
    UserCredential userCredential;
    try {
      userCredential = kIsWeb
          ? await _firebaseAuth.signInWithPopup(provider)
          : await _firebaseAuth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'canceled' ||
          e.code == 'user-cancelled') {
        throw const SignInCancelledException();
      }
      rethrow;
    }

    final User? firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw FirebaseAuthException(
          code: 'null-user', message: 'Firebase returned a null user.');
    }

    return _verifyUserAccess(firebaseUser);
  }

  /// Handles the redirect result after [signInWithGoogle] on web.
  /// Must be called AFTER Firebase Auth has initialized (i.e. after waiting
  /// for the first authStateChanges event).
  ///
  /// Returns [AppUser] if a redirect result is available, null otherwise.
  Future<AppUser?> checkRedirectResult() async {
    debugPrint('[Auth] checkRedirectResult: attente initialisation Firebase Auth...');
    // Wait for Firebase to finish reading its persisted state before calling
    // getRedirectResult — otherwise it always returns user=null.
    await _firebaseAuth
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 6), onTimeout: () => null);

    debugPrint('[Auth] checkRedirectResult: appel getRedirectResult...');
    try {
      final result = await _firebaseAuth.getRedirectResult();
      debugPrint('[Auth] checkRedirectResult: user=${result.user?.uid ?? "null"}, credential=${result.credential != null}');
      if (result.user == null) return null;
      return _verifyUserAccess(result.user!);
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] checkRedirectResult: FirebaseAuthException → code=${e.code}, msg=${e.message}');
      return null;
    } catch (e) {
      debugPrint('[Auth] checkRedirectResult: exception → $e');
      return null;
    }
  }

  /// Checks whether the currently authenticated Firebase user (if any) has a
  /// valid `users` document in Firestore. Called at app start to restore
  /// session — does NOT re-check `allowed_emails` (already done at first login).
  ///
  /// Looks up by UID first, then falls back to email (handles seeded users
  /// whose document ID differs from the Firebase Auth UID).
  ///
  /// Returns [AppUser] if valid, null if no session or document absent.
  /// Throws [AccessDeniedException] if the session is found but not authorised.
  Future<AppUser?> verifyCurrentUser() async {
    // currentUser is populated synchronously when Firebase has already
    // restored its state (browser refresh, mobile token cache, redirect result).
    // On a cold Flutter web start, authStateChanges() may emit null first, then
    // the restored user. We wait for the first non-null emission with a timeout.
    final user = _firebaseAuth.currentUser ??
        await _firebaseAuth
            .authStateChanges()
            .where((u) => u != null)
            .first
            .timeout(const Duration(seconds: 6), onTimeout: () => null);

    if (user == null) {
      debugPrint('[Auth] verifyCurrentUser: aucun utilisateur Firebase en session.');
      return null;
    }

    debugPrint('[Auth] verifyCurrentUser: utilisateur Firebase trouvé — uid=${user.uid}, email=${user.email}');

    // Try by UID first
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      debugPrint('[Auth] verifyCurrentUser: document users/${user.uid} trouvé → accès accordé.');
      return AppUser.fromFirestore(doc.id, doc.data()!);
    }

    debugPrint('[Auth] verifyCurrentUser: document users/${user.uid} INTROUVABLE, tentative de recherche par email...');

    // Fallback: look up by email (e.g. user document was seeded with a different ID)
    final email = user.email;
    if (email != null) {
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        final seededDoc = emailQuery.docs.first;
        debugPrint('[Auth] verifyCurrentUser: document trouvé par email ($email) → id=${seededDoc.id} → accès accordé.');

        // Si le doc seedé a un ID différent du Firebase UID :
        // 1. Les règles Firestore (isAuthorised vérifie users/{auth.uid}) bloqueront
        //    toutes les autres collections → on crée un doc miroir à users/{uid}.
        // 2. Le groupe a members:[seededId] mais getCurrentGroupId cherche par UID
        //    → on ajoute le Firebase UID au groupe pour que la recherche fonctionne.
        if (seededDoc.id != user.uid) {
          debugPrint('[Auth] verifyCurrentUser: doc ID (${seededDoc.id}) ≠ Firebase UID (${user.uid}) → migration en cours...');

          // 1. Doc miroir pour isAuthorised()
          await _firestore
              .collection('users')
              .doc(user.uid)
              .set(seededDoc.data()!, SetOptions(merge: true));
          debugPrint('[Auth] verifyCurrentUser: users/${user.uid} créé.');

          // 2. Ajout du Firebase UID dans le groupe qui contient le seeded doc ID
          final groupSnap = await _firestore
              .collection('groups')
              .where('members', arrayContains: seededDoc.id)
              .limit(1)
              .get();
          if (groupSnap.docs.isNotEmpty) {
            final groupRef = groupSnap.docs.first.reference;
            await groupRef.update({
              'members': FieldValue.arrayUnion([user.uid]),
            });
            debugPrint('[Auth] verifyCurrentUser: Firebase UID ajouté au groupe ${groupSnap.docs.first.id}.');
          } else {
            debugPrint('[Auth] verifyCurrentUser: aucun groupe trouvé contenant ${seededDoc.id}.');
          }
        }

        return AppUser.fromFirestore(seededDoc.id, seededDoc.data()!);
      }
      debugPrint('[Auth] verifyCurrentUser: aucun document users avec email=$email → ACCESS REFUSÉ.');
    } else {
      debugPrint('[Auth] verifyCurrentUser: email Firebase null → ACCESS REFUSÉ.');
    }

    await signOut();
    throw const AccessDeniedException();
  }

  /// Signs out from Firebase.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// 1. Checks that the user's email exists in the `users` collection.
  /// 2. Creates (or updates) the `users/{uid}` document.
  /// 3. Returns an [AppUser] for the session.
  ///
  /// On absence from `users`, signs out and throws [AccessDeniedException].
  Future<AppUser> _verifyUserAccess(User firebaseUser) async {
    final email = firebaseUser.email;
    debugPrint('[Auth] _verifyUserAccess: uid=${firebaseUser.uid}, email=$email');

    if (email == null) {
      debugPrint('[Auth] _verifyUserAccess: email Firebase null → ACCESS REFUSÉ.');
      await signOut();
      throw const AccessDeniedException();
    }

    // Step 1 – Check users/{uid} directly (fast path for returning users).
    debugPrint('[Auth] _verifyUserAccess: vérification directe users/${firebaseUser.uid}');
    final uidDoc = await _firestore.collection('users').doc(firebaseUser.uid).get();

    late DocumentReference userRef;
    if (uidDoc.exists) {
      debugPrint('[Auth] _verifyUserAccess: users/${firebaseUser.uid} trouvé → mise à jour.');
      userRef = uidDoc.reference;
      await userRef.set({
        'email': email,
        'name': firebaseUser.displayName ?? '',
      }, SetOptions(merge: true));
    } else {
      // No doc at users/{uid}: check by email (pending invitations or seeded users).
      debugPrint('[Auth] _verifyUserAccess: recherche document users existant par email=$email');
      final existingQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existingQuery.docs.isEmpty) {
        debugPrint('[Auth] _verifyUserAccess: email=$email ABSENT de users → ACCESS REFUSÉ.');
        await signOut();
        throw const AccessDeniedException();
      }

      final existingDoc = existingQuery.docs.first;
      debugPrint('[Auth] _verifyUserAccess: document users trouvé par email (id=${existingDoc.id}).');

      if (existingDoc.id == firebaseUser.uid) {
        // Same ID — just update.
        userRef = existingDoc.reference;
        await userRef.set({
          'email': email,
          'name': firebaseUser.displayName ?? '',
        }, SetOptions(merge: true));
      } else {
        // Pending invitation or seeded doc with different ID:
        // create/migrate to users/{uid}.
        debugPrint('[Auth] _verifyUserAccess: doc ID (${existingDoc.id}) ≠ Firebase UID (${firebaseUser.uid}) → migration.');
        userRef = _firestore.collection('users').doc(firebaseUser.uid);
        final existingData = existingDoc.data() as Map<String, dynamic>;
        final groupId = existingData['groupId'] as String?;
        await userRef.set({
          'email': email,
          'name': firebaseUser.displayName ?? existingData['name'] ?? '',
          'role': existingData['role'] ?? 'user',
          if (groupId != null) 'groupId': groupId,
        }, SetOptions(merge: true));
        debugPrint('[Auth] _verifyUserAccess: users/${firebaseUser.uid} créé.');

        // Delete the old pending/seeded doc.
        await existingDoc.reference.delete();
        debugPrint('[Auth] _verifyUserAccess: ancien doc ${existingDoc.id} supprimé.');

        // Add Firebase UID to the group.
        if (groupId != null) {
          await _firestore.collection('groups').doc(groupId).update({
            'members': FieldValue.arrayUnion([firebaseUser.uid]),
          });
          debugPrint('[Auth] _verifyUserAccess: Firebase UID ajouté au groupe $groupId.');
        } else {
          // Also check if old doc was in a group by members array.
          final groupSnap = await _firestore
              .collection('groups')
              .where('members', arrayContains: existingDoc.id)
              .limit(1)
              .get();
          if (groupSnap.docs.isNotEmpty) {
            await groupSnap.docs.first.reference.update({
              'members': FieldValue.arrayUnion([firebaseUser.uid]),
            });
            debugPrint('[Auth] _verifyUserAccess: Firebase UID ajouté au groupe ${groupSnap.docs.first.id}.');
          } else {
            debugPrint('[Auth] _verifyUserAccess: aucun groupe trouvé → utilisateur non assigné.');
          }
        }
      }
    }

    // Step 2 – return AppUser
    final doc = await userRef.get();
    final appUser = AppUser.fromFirestore(doc.id, doc.data()! as Map<String, dynamic>);
    debugPrint('[Auth] _verifyUserAccess: AppUser créé → uid=${appUser.uid}, email=${appUser.email}, role=${appUser.role}');
    return appUser;
  }
}

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

/// The user is authenticated with Google/Firebase but their UID is absent from
/// the Firestore `users` collection.
class AccessDeniedException implements Exception {
  const AccessDeniedException();

  @override
  String toString() =>
      'AccessDeniedException: This account is not authorised.';
}

/// The user dismissed the Google account picker without completing sign-in.
class SignInCancelledException implements Exception {
  const SignInCancelledException();

  @override
  String toString() => 'SignInCancelledException: Sign-in was cancelled.';
}
