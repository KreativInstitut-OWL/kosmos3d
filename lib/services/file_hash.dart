import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// SHA-256 (hex) of a file, computed in a background isolate so hashing
/// multi-GB videos never blocks the UI thread.
Future<String> sha256OfFile(String path) => Isolate.run(() async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
});
