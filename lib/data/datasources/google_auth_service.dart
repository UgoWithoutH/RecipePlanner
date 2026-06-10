import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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
  /// Uses [signInWithPopup] on Web, [signInWithProvider] on mobile.
  ///
  /// Returns an [AppUser] on success.
  /// Throws [SignInCancelledException] if the user dismisses the picker.
  /// Throws [AccessDeniedException] if the UID is not in Firestore.
  Future<AppUser> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    UserCredential userCredential;
    try {
      if (kIsWeb) {
        // Web: popup flow – no google_sign_in, no People API
        userCredential = await _firebaseAuth.signInWithPopup(provider);
      } else {
        // Android / iOS: provider flow
        userCredential = await _firebaseAuth.signInWithProvider(provider);
      }
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

    // Firestore access check (binary: present = ok, absent = denied)
    return _verifyUserAccess(firebaseUser);
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
    // restored its state (browser refresh, mobile token cache).
    // On a cold Flutter web start, authStateChanges() emits null immediately
    // before reading localStorage, so we skip that first emission and wait
    // for the real state (2nd event). Timeout = safety net if no session.
    final user = _firebaseAuth.currentUser ??
        await _firebaseAuth
            .authStateChanges()
            .skip(1)
            .first
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

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

  /// 1. Checks that the user's email is in the `allowed_emails` whitelist.
  /// 2. Creates (or updates) the `users/{uid}` document.
  /// 3. Returns an [AppUser] for the session.
  ///
  /// On absence from the whitelist, signs out and throws [AccessDeniedException].
  Future<AppUser> _verifyUserAccess(User firebaseUser) async {
    final email = firebaseUser.email;
    debugPrint('[Auth] _verifyUserAccess: uid=${firebaseUser.uid}, email=$email');

    if (email == null) {
      debugPrint('[Auth] _verifyUserAccess: email Firebase null → ACCESS REFUSÉ.');
      await signOut();
      throw const AccessDeniedException();
    }

    // Step 1 – whitelist check
    debugPrint('[Auth] _verifyUserAccess: vérification dans allowed_emails pour email=$email');
    final allowedQuery = await _firestore
        .collection('allowed_emails')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (allowedQuery.docs.isEmpty) {
      debugPrint('[Auth] _verifyUserAccess: email=$email ABSENT de allowed_emails → ACCESS REFUSÉ.');
      await signOut();
      throw const AccessDeniedException();
    }
    debugPrint('[Auth] _verifyUserAccess: email=$email trouvé dans allowed_emails (doc id=${allowedQuery.docs.first.id}).');

    // Step 2 – find existing user document by email (handles seeded users
    // whose document ID differs from the Firebase Auth UID), or create at
    // users/{uid} for new users.
    debugPrint('[Auth] _verifyUserAccess: recherche document users existant par email=$email');
    final existingQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    late DocumentReference userRef;
    if (existingQuery.docs.isNotEmpty) {
      // Pre-existing user (e.g. seeded doc) – update name, keep document ID
      final seededDoc = existingQuery.docs.first;
      userRef = seededDoc.reference;
      debugPrint('[Auth] _verifyUserAccess: document users existant trouvé (id=${seededDoc.id}), mise à jour des champs email/name.');
      // On ne modifie pas le rôle existant
      await userRef.set({
        'email': email,
        'name': firebaseUser.displayName ?? '',
      }, SetOptions(merge: true));

      // Si le doc seedé a un ID différent du Firebase UID :
      // 1. Créer users/{uid} pour que isAuthorised() passe.
      // 2. Ajouter le Firebase UID dans le groupe pour que getCurrentGroupId() fonctionne.
      if (seededDoc.id != firebaseUser.uid) {
        debugPrint('[Auth] _verifyUserAccess: doc ID (${seededDoc.id}) ≠ Firebase UID (${firebaseUser.uid}) → migration en cours...');

        // 1. Doc miroir
        await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .set({'email': email, 'name': firebaseUser.displayName ?? ''}, SetOptions(merge: true));
        debugPrint('[Auth] _verifyUserAccess: users/${firebaseUser.uid} créé.');

        // 2. Ajout du Firebase UID dans le groupe qui contient le seeded doc ID
        final groupSnap = await _firestore
            .collection('groups')
            .where('members', arrayContains: seededDoc.id)
            .limit(1)
            .get();
        if (groupSnap.docs.isNotEmpty) {
          await groupSnap.docs.first.reference.update({
            'members': FieldValue.arrayUnion([firebaseUser.uid]),
          });
          debugPrint('[Auth] _verifyUserAccess: Firebase UID ajouté au groupe ${groupSnap.docs.first.id}.');
        } else {
          debugPrint('[Auth] _verifyUserAccess: aucun groupe trouvé contenant ${seededDoc.id}.');
        }
      }
    } else {
      // New user – create at users/{uid} avec role 'user' par défaut
      debugPrint('[Auth] _verifyUserAccess: aucun document users existant pour email=$email → création à users/${firebaseUser.uid}');
      userRef = _firestore.collection('users').doc(firebaseUser.uid);
      await userRef.set({
        'email': email,
        'name': firebaseUser.displayName ?? '',
        'role': 'user',
      }, SetOptions(merge: true));
    }

    // Step 3 – return AppUser
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
