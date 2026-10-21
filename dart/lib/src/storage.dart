import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'types.dart';

/// Keeps the session in memory only. It is lost when the process stops, so
/// the device must be confirmed again at every start.
class MemoryStorage implements SessionStorage {
  /// Creates an empty storage, or one holding [initial].
  MemoryStorage([StoredSession? initial]) : _session = initial?.copy();

  StoredSession? _session;

  @override
  Future<StoredSession?> load() async => _session?.copy();

  @override
  Future<void> save(StoredSession session) async => _session = session.copy();

  @override
  Future<void> clear() async => _session = null;
}

/// Saves the session to a JSON file, compatible with the TypeScript and
/// Python SDKs.
///
/// Suited to scripts, servers and desktop apps. In a mobile app, prefer the
/// platform secure storage (see the README): the file is not encrypted.
class FileStorage implements SessionStorage {
  /// Creates a storage backed by the file at [path].
  FileStorage(this.path);

  /// Path of the session file.
  final String path;

  @override
  Future<StoredSession?> load() async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return StoredSession.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      throw BaridiMobError('Corrupted session file: $path', cause: error);
    }
  }

  @override
  Future<void> save(StoredSession session) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(session.toJson())}\n',
      flush: true,
    );
    await temporary.rename(path);
  }

  @override
  Future<void> clear() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
