import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny JSON file cache for offline reads. Controllers hydrate from here at
/// startup (so the last-known data shows with no connection) and write back
/// after every successful fetch. One file per key under the app documents dir
/// — NOT secure storage, which is for small secrets, not list payloads.
///
/// Keys should be scoped per user (e.g. 'transactions_5') so switching
/// accounts never shows another user's cached data.
class LocalCache {
  LocalCache._internal();
  static final LocalCache instance = LocalCache._internal();

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pulsespend_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String key) {
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  /// Stores any json-encodable [value] under [key]. Failures are swallowed —
  /// caching is best-effort and must never break a successful fetch.
  Future<void> write(String key, Object value) async {
    try {
      final file = _fileFor(await _cacheDir(), key);
      await file.writeAsString(jsonEncode(value));
    } catch (_) {}
  }

  /// Returns the decoded json for [key], or null when absent/corrupt.
  Future<dynamic> read(String key) async {
    try {
      final file = _fileFor(await _cacheDir(), key);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Convenience for list payloads: returns a list of maps, or null.
  Future<List<Map<String, dynamic>>?> readList(String key) async {
    final decoded = await read(key);
    if (decoded is! List) return null;
    return decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// Wipes the whole cache (e.g. on logout/account deletion).
  Future<void> clear() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
