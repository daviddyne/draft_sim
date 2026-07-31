import 'dart:js_interop';

@JS('navigator.storage.persist')
external JSPromise<JSBoolean> _persist();

// Asks the browser not to evict what we stored. Browsers grant this most often
// to apps added to the home screen, and ignore it otherwise, so it can only help.
Future<void> requestPersistentStorage() async {
  try {
    await _persist().toDart;
  } catch (_) {
    // Not supported here, downloads still work until the browser clears them
  }
}