import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'system_settings_service.dart';

/// Connection details for any S3-compatible object storage
/// (Backblaze B2, AWS S3, Wasabi, Cloudflare R2, MinIO, Hetzner, ...).
class StorageServerConfig {
  const StorageServerConfig({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretKey,
    this.prefix = 'kosmos3d',
  });

  final String endpoint, region, bucket, accessKeyId, secretKey, prefix;

  bool get isComplete =>
      endpoint.isNotEmpty &&
      bucket.isNotEmpty &&
      accessKeyId.isNotEmpty &&
      secretKey.isNotEmpty;

  /// Normalised base URI, e.g. https://s3.eu-central-003.backblazeb2.com
  Uri get baseUri {
    final raw = endpoint.trim();
    final uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
  }

  /// Region from the field, or derived from common provider host names.
  String get effectiveRegion {
    if (region.trim().isNotEmpty) return region.trim();
    final host = baseUri.host;
    final match = RegExp(
      r'^s3[.-]([a-z0-9-]+)\.(backblazeb2|wasabisys|amazonaws)\.com$',
    ).firstMatch(host);
    if (match != null) return match[1]!;
    if (host.endsWith('r2.cloudflarestorage.com')) return 'auto';
    return 'us-east-1';
  }
}

/// AWS Signature Version 4 for S3-compatible APIs.
class S3Signer {
  S3Signer(this.config);
  final StorageServerConfig config;

  static const emptyPayloadHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// RFC 3986 encoding as required by SigV4 (only A-Z a-z 0-9 - _ . ~ unreserved).
  static String encode(String value, {bool keepSlash = false}) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final c = String.fromCharCode(byte);
      final unreserved =
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          (byte >= 0x30 && byte <= 0x39) ||
          c == '-' ||
          c == '_' ||
          c == '.' ||
          c == '~';
      if (unreserved || (keepSlash && c == '/')) {
        out.write(c);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Returns the full URI and signed headers for one request (path-style addressing).
  ({Uri uri, Map<String, String> headers}) sign({
    required String method,
    required String key,
    Map<String, String> query = const {},
    String payloadHash = emptyPayloadHash,
    Map<String, String> extraHeaders = const {},
    DateTime? now,
  }) {
    final time = (now ?? DateTime.now()).toUtc();
    final date = '${time.year}${_two(time.month)}${_two(time.day)}';
    final amzDate =
        '${date}T${_two(time.hour)}${_two(time.minute)}${_two(time.second)}Z';
    final base = config.baseUri;
    final path = key.isEmpty
        ? '/${encode(config.bucket)}'
        : '/${encode(config.bucket)}/${encode(key, keepSlash: true)}';
    final sortedQuery = query.keys.toList()..sort();
    final canonicalQuery = sortedQuery
        .map((k) => '${encode(k)}=${encode(query[k]!)}')
        .join('&');
    final hostHeader = base.hasPort && base.port != 443 && base.port != 80
        ? '${base.host}:${base.port}'
        : base.host;
    final headers = <String, String>{
      'host': hostHeader,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      for (final e in extraHeaders.entries) e.key.toLowerCase(): e.value.trim(),
    };
    final names = headers.keys.toList()..sort();
    final canonicalHeaders = names.map((n) => '$n:${headers[n]}\n').join();
    final signedHeaders = names.join(';');
    final canonicalRequest = [
      method,
      path,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final region = config.effectiveRegion;
    final scope = '$date/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    List<int> hmac(List<int> k, String data) =>
        Hmac(sha256, k).convert(utf8.encode(data)).bytes;
    var signingKey = hmac(utf8.encode('AWS4${config.secretKey}'), date);
    signingKey = hmac(signingKey, region);
    signingKey = hmac(signingKey, 's3');
    signingKey = hmac(signingKey, 'aws4_request');
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();
    headers['authorization'] =
        'AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    headers.remove('host');
    final uri = Uri.parse(
      '${base.scheme}://$hostHeader$path${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}',
    );
    return (uri: uri, headers: headers);
  }
}

/// Uploads project folders to the user's own S3-compatible storage server.
/// Credentials are stored encrypted via flutter_secure_storage.
class CloudStorageService extends ChangeNotifier {
  static const _keyId = 's3_access_key_id';
  static const _keySecret = 's3_secret_key';
  static const _keyBucket = 's3_bucket';
  static const _keyEndpoint = 's3_endpoint';
  static const _keyRegion = 's3_region';
  static const _keyPrefix = 's3_prefix';
  // Storage keys used by v1 (Backblaze native API). Migrated once.
  static const _legacy = {
    'b2_key_id': _keyId,
    'b2_app_key': _keySecret,
    'b2_bucket_name': _keyBucket,
    'b2_endpoint': _keyEndpoint,
    'b2_region': _keyRegion,
  };

  /// Single PUT limit on S3-compatible services.
  static const maxSinglePutBytes = 5 * 1024 * 1024 * 1024;

  CloudStorageService({FlutterSecureStorage? storage, http.Client? client})
    : _secureStorage = storage ?? const FlutterSecureStorage(),
      _injectedClient = client {
    ready = _checkConfiguration();
  }

  final FlutterSecureStorage _secureStorage;
  final http.Client? _injectedClient;
  late final Future<void> ready;

  bool _isUploading = false;
  bool _cancel = false;
  double _progress = 0;
  String _statusMessage = '';
  String? _lastError;
  bool _isConfigured = false;

  bool get isUploading => _isUploading;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;
  bool get isConfigured => _isConfigured;

  void cancelUpload() => _cancel = true;

  Future<void> _checkConfiguration() async {
    try {
      for (final entry in _legacy.entries) {
        final old = await _secureStorage.read(key: entry.key);
        if (old != null &&
            (await _secureStorage.read(key: entry.value)) == null) {
          await _secureStorage.write(key: entry.value, value: old);
        }
        if (old != null) await _secureStorage.delete(key: entry.key);
      }
      _isConfigured = (await loadConfig()).isComplete;
    } catch (e) {
      debugPrint('Storage configuration unavailable: $e');
      _isConfigured = false;
    }
    notifyListeners();
  }

  Future<StorageServerConfig> loadConfig() async => StorageServerConfig(
    endpoint: await _secureStorage.read(key: _keyEndpoint) ?? '',
    region: await _secureStorage.read(key: _keyRegion) ?? '',
    bucket: await _secureStorage.read(key: _keyBucket) ?? '',
    accessKeyId: await _secureStorage.read(key: _keyId) ?? '',
    secretKey: await _secureStorage.read(key: _keySecret) ?? '',
    prefix: await _secureStorage.read(key: _keyPrefix) ?? 'kosmos3d',
  );

  Future<void> saveCredentials({
    required String keyId,
    required String applicationKey,
    required String bucketName,
    required String endpoint,
    String region = '',
    String prefix = 'kosmos3d',
  }) async {
    await _secureStorage.write(key: _keyId, value: keyId.trim());
    if (applicationKey.trim().isNotEmpty) {
      await _secureStorage.write(key: _keySecret, value: applicationKey.trim());
    }
    await _secureStorage.write(key: _keyBucket, value: bucketName.trim());
    await _secureStorage.write(key: _keyEndpoint, value: endpoint.trim());
    await _secureStorage.write(key: _keyRegion, value: region.trim());
    await _secureStorage.write(key: _keyPrefix, value: _cleanPrefix(prefix));
    _isConfigured = (await loadConfig()).isComplete;
    notifyListeners();
  }

  /// Display values; the secret is reported only as present/absent.
  Future<Map<String, String>> getDisplayCredentials() async {
    final c = await loadConfig();
    return {
      'keyId': c.accessKeyId,
      'bucketName': c.bucket,
      'endpoint': c.endpoint,
      'region': c.region,
      'prefix': c.prefix,
      'hasSecret': c.secretKey.isEmpty ? 'false' : 'true',
    };
  }

  Future<void> clearCredentials() async {
    for (final key in [
      _keyId,
      _keySecret,
      _keyBucket,
      _keyEndpoint,
      _keyRegion,
      _keyPrefix,
    ]) {
      await _secureStorage.delete(key: key);
    }
    _isConfigured = false;
    notifyListeners();
  }

  static String _cleanPrefix(String prefix) => prefix
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.' && s != '..')
      .join('/');

  static String safeSegment(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return cleaned.isEmpty ? 'project' : cleaned;
  }

  http.Client _client() => _injectedClient ?? http.Client();
  void _close(http.Client c) {
    if (_injectedClient == null) c.close();
  }

  // ─── S3 OPERATIONS ─────────────────────────────────────────

  /// Lists at most one object: proves endpoint, bucket, region and key work.
  Future<bool> testConnection() async {
    _lastError = null;
    final config = await loadConfig();
    if (!config.isComplete) {
      _lastError = 'Enter endpoint, bucket, access key ID and secret key.';
      notifyListeners();
      return false;
    }
    // A joined camera Wi-Fi routes all app traffic to the camera, which has
    // no internet. Hand traffic back to the normal phone network first.
    try {
      await SystemSettingsService.releaseCameraWifi();
    } catch (_) {}
    final client = _client();
    try {
      final signed = S3Signer(config).sign(
        method: 'GET',
        key: '',
        query: {'list-type': '2', 'max-keys': '1'},
      );
      final response = await client
          .get(signed.uri, headers: signed.headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) return true;
      _lastError = _describe(response.statusCode, response.body);
      return false;
    } catch (e) {
      _lastError = 'Cannot reach ${config.baseUri.host}: $e';
      return false;
    } finally {
      _close(client);
      notifyListeners();
    }
  }

  String _describe(int status, String body) {
    final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(body)?[1];
    final message = RegExp(r'<Message>([^<]+)</Message>').firstMatch(body)?[1];
    final hint = switch (code) {
      'NoSuchBucket' => 'Bucket not found. Check the bucket name.',
      'InvalidAccessKeyId' => 'Access key ID is unknown on this server.',
      'SignatureDoesNotMatch' => 'Secret key or region is wrong.',
      'AccessDenied' => 'Key has no permission for this bucket.',
      'AuthorizationHeaderMalformed' => 'Region does not match the endpoint.',
      _ => null,
    };
    return hint ??
        'Server answered $status${code == null ? '' : ' $code'}'
            '${message == null ? '' : ': $message'}';
  }

  Future<int?> _remoteSize(
    http.Client client,
    StorageServerConfig config,
    String key,
  ) async {
    final signed = S3Signer(config).sign(method: 'HEAD', key: key);
    final response = await client
        .head(signed.uri, headers: signed.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw HttpException('HEAD $key failed (${response.statusCode})');
    }
    return int.tryParse(response.headers['content-length'] ?? '');
  }

  static String contentTypeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gpr' || 'dng' => 'image/x-adobe-dng',
      'mp4' || 'lrv' => 'video/mp4',
      'json' => 'application/json',
      'jsonl' => 'application/x-ndjson',
      'csv' => 'text/csv',
      'ply' => 'application/octet-stream',
      _ => 'application/octet-stream',
    };
  }

  /// Streams one file (never loaded fully into memory) with a SHA-256 payload hash.
  Future<void> putFile(
    http.Client client,
    StorageServerConfig config,
    File file,
    String key, {
    void Function(int sent, int total)? onBytes,
  }) async {
    final length = await file.length();
    if (length > maxSinglePutBytes) {
      throw StateError('${file.path} is larger than 5 GB; split it first.');
    }
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final signed = S3Signer(config).sign(
      method: 'PUT',
      key: key,
      payloadHash: hash,
      extraHeaders: {'content-type': contentTypeFor(key)},
    );
    final request = _StreamingPut(signed.uri, file, length, onBytes)
      ..headers.addAll(signed.headers);
    final response = await http.Response.fromStream(
      await client.send(request),
    ).timeout(const Duration(minutes: 60));
    if (response.statusCode != 200) {
      throw HttpException(_describe(response.statusCode, response.body));
    }
  }

  /// Every file inside the project folder (captures, receipts, sensor logs,
  /// LiDAR, manifest), keeping the folder structure.
  Future<List<({File file, String relative})>> _projectFiles(
    String projectId,
  ) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/kosmos3d_projects/$projectId');
    if (!await dir.exists()) return [];
    final out = <({File file, String relative})>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || entity.path.endsWith('.part')) continue;
      final relative = entity.path
          .substring(dir.path.length + 1)
          .replaceAll('\\', '/');
      out.add((file: entity, relative: relative));
    }
    out.sort((a, b) => a.relative.compareTo(b.relative));
    return out;
  }

  /// Upload the whole project folder to `<prefix>/<name>_<id>/...`.
  Future<bool> uploadProject(String projectId, String projectName) async {
    final files = await _projectFiles(projectId);
    if (files.isEmpty) {
      _lastError = 'No files to upload.';
      _statusMessage = 'Empty project';
      notifyListeners();
      return false;
    }
    return _upload(files, '${safeSegment(projectName)}_$projectId');
  }

  /// Upload loose files (e.g. a gallery selection) to `<prefix>/<folder>/`.
  Future<bool> uploadFiles(List<File> files, {String? projectName}) async {
    if (files.isEmpty) return true;
    return _upload([
      for (final f in files) (file: f, relative: f.uri.pathSegments.last),
    ], safeSegment(projectName ?? 'imports'));
  }

  Future<bool> _upload(
    List<({File file, String relative})> files,
    String folder,
  ) async {
    if (_isUploading) return false;
    final config = await loadConfig();
    if (!config.isComplete) {
      _lastError = 'Configure a storage server in Settings first.';
      notifyListeners();
      return false;
    }
    _isUploading = true;
    _cancel = false;
    _progress = 0;
    _lastError = null;
    _statusMessage = 'Connecting to ${config.baseUri.host}…';
    notifyListeners();
    // A joined camera Wi-Fi routes all app traffic to the camera, which has
    // no internet. Hand traffic back to the normal phone network first.
    try {
      await SystemSettingsService.releaseCameraWifi();
    } catch (_) {}
    final client = _client();
    final totalBytes = files.fold<int>(
      0,
      (sum, f) => sum + f.file.lengthSync(),
    );
    var doneBytes = 0, uploaded = 0, skipped = 0;
    final base = [
      if (config.prefix.isNotEmpty) config.prefix,
      folder,
    ].join('/');
    try {
      for (var i = 0; i < files.length; i++) {
        if (_cancel) throw StateError('Upload cancelled');
        final entry = files[i];
        final key = '$base/${entry.relative}';
        final length = await entry.file.length();
        _statusMessage = '${i + 1}/${files.length}: ${entry.relative}';
        notifyListeners();
        if (await _remoteSize(client, config, key) == length) {
          skipped++;
        } else {
          for (var attempt = 0; ; attempt++) {
            try {
              await putFile(
                client,
                config,
                entry.file,
                key,
                onBytes: (sent, _) {
                  _progress = totalBytes == 0
                      ? 1
                      : (doneBytes + sent) / totalBytes;
                  notifyListeners();
                },
              );
              break;
            } catch (e) {
              if (attempt >= 2 || _cancel) rethrow;
              _statusMessage = 'Retry ${attempt + 1}/2: ${entry.relative}';
              notifyListeners();
              await Future<void>.delayed(Duration(seconds: 2 << attempt));
            }
          }
          uploaded++;
        }
        doneBytes += length;
        _progress = totalBytes == 0 ? 1 : doneBytes / totalBytes;
      }
      _progress = 1;
      _statusMessage =
          '$uploaded uploaded, $skipped already on server → ${config.bucket}/$base';
      return true;
    } catch (e) {
      _lastError = '$e';
      _statusMessage = 'Upload stopped after $uploaded files: $e';
      return false;
    } finally {
      _close(client);
      _isUploading = false;
      notifyListeners();
    }
  }
}

/// Streams a file body with byte progress.
class _StreamingPut extends http.BaseRequest {
  _StreamingPut(Uri uri, this.file, int length, this.onBytes)
    : super('PUT', uri) {
    contentLength = length;
  }
  final File file;
  final void Function(int sent, int total)? onBytes;

  @override
  http.ByteStream finalize() {
    super.finalize();
    var sent = 0;
    return http.ByteStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        onBytes?.call(sent, contentLength ?? 0);
        return chunk;
      }),
    );
  }
}
