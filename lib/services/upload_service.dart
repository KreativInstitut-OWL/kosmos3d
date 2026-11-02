import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'system_settings_service.dart';

typedef ServerConfigLoader = Future<Map<String, String>> Function();

/// Streamed, cancellable uploads. KOSMOS PUT retries are content-address verified.
class UploadService extends ChangeNotifier {
  UploadService({
    ServerConfigLoader? configLoader,
    Future<Directory> Function()? documents,
  }) : _configLoader = configLoader,
       _documents = documents ?? getApplicationDocumentsDirectory;
  final ServerConfigLoader? _configLoader;
  final Future<Directory> Function() _documents;
  bool _isUploading = false, _cancelled = false;
  double _progress = 0;
  String _statusMessage = '';
  String? _lastError;
  http.Client? _client;
  bool get isUploading => _isUploading;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;

  Future<Map<String, String>> _config() async {
    if (_configLoader != null) return _configLoader();
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString('server_url') ?? '',
      'username': prefs.getString('server_username') ?? '',
      'password': prefs.getString('server_password') ?? '',
      'api_key': prefs.getString('server_api_key') ?? '',
      'transport': prefs.getString('server_transport') ?? 'multipart',
    };
  }

  Uri _base(Map<String, String> config) {
    final uri = Uri.tryParse(config['url'] ?? '');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter a valid HTTP(S) server address without query parameters.',
      );
    }
    return uri;
  }

  Uri _endpoint(Uri base, List<String> segments) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...segments,
    ],
  );

  Future<bool> isServerConfigured() async {
    try {
      _base(await _config());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testConnection() async {
    // A joined camera Wi-Fi routes all app traffic to the camera, which has
    // no internet. Hand traffic back to the normal phone network first.
    try {
      await SystemSettingsService.releaseCameraWifi();
    } catch (_) {}
    final client = http.Client();
    try {
      final config = await _config();
      final base = _base(config);
      final uri = config['transport'] == 'kosmos'
          ? _endpoint(base, ['health'])
          : base;
      final response = await client
          .get(uri, headers: _headers(config))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Server returned HTTP ${response.statusCode}');
      }
      if (config['transport'] == 'kosmos' &&
          jsonDecode(response.body)['service'] != 'kosmos-transfer') {
        throw const FormatException(
          'This address is not a KOSMOS transfer server.',
        );
      }
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
      return false;
    } finally {
      client.close();
    }
  }

  void cancel() {
    if (!_isUploading) return;
    _cancelled = true;
    _client?.close();
    _statusMessage = 'Cancelling…';
    notifyListeners();
  }

  Future<bool> uploadFile(File file, {String? projectName}) =>
      uploadFiles([file], projectName: projectName);

  Future<bool> uploadProject(String projectId, String projectName) =>
      _run(() async {
        final root = Directory(
          '${(await _documents()).path}/kosmos3d_projects/$projectId',
        );
        if (!await root.exists()) {
          throw const FileSystemException('Project folder not found');
        }
        final entries = <_UploadEntry>[];
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && !entity.path.endsWith('.part')) {
            final relative = entity.path
                .substring(root.path.length + 1)
                .replaceAll('\\', '/');
            entries.add(_UploadEntry(entity, relative));
          }
        }
        entries.sort((a, b) => a.relative.compareTo(b.relative));
        return entries;
      }, '$projectName--$projectId');

  Future<bool> uploadFiles(List<File> files, {String? projectName}) => _run(
    () async => files
        .where((f) => !f.path.endsWith('.part'))
        .map((f) => _UploadEntry(f, f.uri.pathSegments.last))
        .toList(),
    projectName ?? 'Imports',
  );

  Future<bool> _run(
    Future<List<_UploadEntry>> Function() collect,
    String project,
  ) async {
    if (_isUploading) return false;
    _isUploading = true;
    _cancelled = false;
    _lastError = null;
    _progress = 0;
    _statusMessage = 'Preparing files…';
    notifyListeners();
    // A joined camera Wi-Fi routes all app traffic to the camera, which has
    // no internet. Hand traffic back to the normal phone network first.
    try {
      await SystemSettingsService.releaseCameraWifi();
    } catch (_) {}
    try {
      final config = await _config();
      final base = _base(config);
      final entries = await collect();
      if (entries.isEmpty) {
        throw const FileSystemException('No files to upload');
      }
      var total = 0;
      for (final entry in entries) {
        total += await entry.file.length();
      }
      var completedBytes = 0;
      var completedFiles = 0;
      for (final entry in entries) {
        _checkCancelled();
        _statusMessage = 'Checking ${entry.relative}';
        notifyListeners();
        final length = await entry.file.length();
        final digest = (await sha256.bind(entry.file.openRead()).first)
            .toString();
        _checkCancelled();
        final usePut = config['transport'] == 'kosmos';
        final uri = usePut
            ? _endpoint(base, ['files', project, ...entry.relative.split('/')])
            : _endpoint(base, ['upload']);
        var acknowledged = false;
        for (var attempt = 0; attempt < (usePut ? 3 : 1); attempt++) {
          _checkCancelled();
          final client = http.Client();
          _client = client;
          try {
            if (usePut) {
              final existing = await client
                  .head(uri, headers: _headers(config))
                  .timeout(const Duration(seconds: 15));
              if (existing.statusCode == 200 &&
                  existing.headers['x-content-sha256'] == digest &&
                  existing.headers['content-length'] == '$length') {
                acknowledged = true;
                break;
              }
              if (existing.statusCode == 401 || existing.statusCode == 403) {
                throw HttpException(
                  'Server authentication failed (HTTP ${existing.statusCode})',
                );
              }
            }
            _statusMessage =
                'Sending ${completedFiles + 1}/${entries.length} · ${entry.relative}';
            notifyListeners();
            void sent(int bytes) {
              _checkCancelled();
              _progress = total == 0
                  ? 0
                  : ((completedBytes + bytes.clamp(0, length)) / total).clamp(
                      0,
                      0.999,
                    );
              notifyListeners();
            }

            final http.BaseRequest request;
            if (usePut) {
              request = _FilePut(uri, entry.file, length, sent);
              request.headers.addAll({
                'Content-Type': 'application/octet-stream',
                'X-Content-SHA256': digest,
              });
            } else {
              final multipart = _ProgressMultipart(uri, sent);
              multipart.fields.addAll({
                'project': project,
                'relative_path': entry.relative,
                'sha256': digest,
              });
              multipart.files.add(
                await http.MultipartFile.fromPath('file', entry.file.path),
              );
              request = multipart;
            }
            request.followRedirects = false;
            request.headers.addAll(_headers(config));
            final response = await client
                .send(request)
                .timeout(const Duration(minutes: 30));
            final body = await response.stream.bytesToString().timeout(
              const Duration(seconds: 30),
            );
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException(
                'HTTP ${response.statusCode} while sending ${entry.relative}',
              );
            }
            if (usePut) {
              final receipt = jsonDecode(body) as Map<String, dynamic>;
              if (receipt['sha256'] != digest || receipt['bytes'] != length) {
                throw const FormatException(
                  'Server checksum receipt did not match the local file',
                );
              }
            }
            acknowledged = true;
            break;
          } catch (e) {
            if (_cancelled ||
                !usePut ||
                attempt == 2 ||
                e.toString().contains('authentication') ||
                e.toString().contains('HTTP 4')) {
              rethrow;
            }
            _statusMessage =
                'Connection interrupted. Retrying ${entry.relative}…';
            notifyListeners();
            await Future<void>.delayed(Duration(seconds: attempt + 1));
          } finally {
            client.close();
            if (identical(_client, client)) _client = null;
          }
        }
        if (!acknowledged) throw StateError('File was not acknowledged');
        completedBytes += length;
        completedFiles++;
        _progress = total == 0
            ? completedFiles / entries.length
            : completedBytes / total;
        notifyListeners();
      }
      _statusMessage = 'Transferred $completedFiles files';
      _progress = 1;
      return true;
    } catch (e) {
      _lastError = _cancelled ? 'Transfer cancelled. Retry to continue.' : '$e';
      _statusMessage = _cancelled ? 'Cancelled' : 'Transfer needs attention';
      return false;
    } finally {
      _client?.close();
      _client = null;
      _isUploading = false;
      notifyListeners();
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw StateError('Cancelled');
  }

  Future<bool> uploadTrajectory(
    String projectId,
    String projectName,
    String data,
    String format,
  ) async {
    final root = await _documents();
    final file = File(
      '${root.path}/kosmos3d_projects/$projectId/trajectory.$format',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(data);
    return uploadFile(file, projectName: '$projectName--$projectId');
  }

  Map<String, String> _headers(Map<String, String> config) {
    if ((config['api_key'] ?? '').isNotEmpty) {
      return {'Authorization': 'Bearer ${config['api_key']}'};
    }
    if ((config['username'] ?? '').isNotEmpty) {
      return {
        'Authorization':
            'Basic ${base64Encode(utf8.encode("${config['username']}:${config['password']}"))}',
      };
    }
    return {};
  }
}

class _UploadEntry {
  const _UploadEntry(this.file, this.relative);
  final File file;
  final String relative;
}

class _FilePut extends http.BaseRequest {
  _FilePut(Uri uri, this.file, int length, this.onBytes) : super('PUT', uri) {
    contentLength = length;
  }
  final File file;
  final void Function(int) onBytes;
  @override
  http.ByteStream finalize() {
    super.finalize();
    var count = 0;
    return http.ByteStream(
      file.openRead().map((bytes) {
        count += bytes.length;
        onBytes(count);
        return bytes;
      }),
    );
  }
}

class _ProgressMultipart extends http.MultipartRequest {
  _ProgressMultipart(Uri uri, this.onBytes) : super('POST', uri);
  final void Function(int) onBytes;
  @override
  http.ByteStream finalize() {
    var count = 0;
    return http.ByteStream(
      super.finalize().map((bytes) {
        count += bytes.length;
        onBytes(count);
        return bytes;
      }),
    );
  }
}
