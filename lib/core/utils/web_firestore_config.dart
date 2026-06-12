// Conditional export: web implementation on browsers, no-op stub elsewhere.
export 'web_firestore_config_stub.dart'
    if (dart.library.html) 'web_firestore_config_web.dart';
