import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

    if (user == null) return null;

    // Try by UID first
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return AppUser.fromFirestore(doc.id, doc.data()!);
    }

    // Fallback: look up by email (e.g. user document was seeded with a different ID)
    final email = user.email;
    if (email != null) {
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        return AppUser.fromFirestore(
            emailQuery.docs.first.id, emailQuery.docs.first.data());
      }
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
    if (email == null) {
      await signOut();
      throw const AccessDeniedException();
    }

    // Step 1 – whitelist check
    final allowedQuery = await _firestore
        .collection('allowed_emails')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (allowedQuery.docs.isEmpty) {
      await signOut();
      throw const AccessDeniedException();
    }

    // Step 2 – find existing user document by email (handles seeded users
    // whose document ID differs from the Firebase Auth UID), or create at
    // users/{uid} for new users.
    final existingQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    late DocumentReference userRef;
    if (existingQuery.docs.isNotEmpty) {
      // Pre-existing user (e.g. seeded doc) – update name, keep document ID
      userRef = existingQuery.docs.first.reference;
    } else {
      // New user – create at users/{uid}
      userRef = _firestore.collection('users').doc(firebaseUser.uid);
    }
    await userRef.set({
      'email': email,
      'name': firebaseUser.displayName ?? '',
    }, SetOptions(merge: true));

    // Step 3 – return AppUser
    final doc = await userRef.get();
    return AppUser.fromFirestore(doc.id, doc.data()! as Map<String, dynamic>);
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
