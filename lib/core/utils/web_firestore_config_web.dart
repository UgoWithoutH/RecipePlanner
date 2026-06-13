// Web-only implementation.
// Uses the Firebase JS SDK globals (firebase_core / firebase_firestore)
// that are loaded as classic <script> bundles by firebase_core_web.
// Calling initializeFirestore with experimentalForceLongPolling forces XHR
// transport, which works correctly on Safari/iOS where WebChannel (gRPC) hangs.

import 'dart:js_interop';

// ── Firebase JS SDK interop ───────────────────────────────────────────────────

/// firebase_core.getApp() → returns the default FirebaseApp JS object.
@JS('firebase_core.getApp')
external JSObject _getApp([JSString? name]);

/// firebase_firestore.initializeFirestore(app, settings) → FirestoreJsImpl
@JS('firebase_firestore.initializeFirestore')
external JSObject _initFirestore(JSObject app, _FirestoreSettings settings);

/// firebase_firestore.memoryLocalCache() → MemoryLocalCache
/// (disables IndexedDB persistence – prevents Safari's storage-quota blocks)
@JS('firebase_firestore.memoryLocalCache')
external JSObject _memoryLocalCache([JSObject? settings]);

/// A plain JS object matching the FirestoreSettings interface.
extension type _FirestoreSettings._(JSObject _) implements JSObject {
  external factory _FirestoreSettings({
    JSBoolean experimentalForceLongPolling,
    JSObject cache,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

/// Must be called once, after [Firebase.initializeApp()] but before any
/// Firestore access.  Pre-initialises Firestore with long-polling transport
/// and memory cache so the Dart plugin's lazy [_delegate] getter will call
/// [getFirestore()] (returning this instance) rather than
/// [initializeFirestore()] (which would throw "already initialised").
Future<void> configureFirestoreForWeb() async {
  try {
    final app = _getApp();
    final settings = _FirestoreSettings(
      experimentalForceLongPolling: true.toJS,
      cache: _memoryLocalCache(),
    );
    _initFirestore(app, settings);
  } catch (_) {
    // Already initialised (e.g. hot-restart) – safe to ignore.
  }
}
