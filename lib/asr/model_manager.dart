import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/settings_service.dart';
import 'model_catalog.dart';

class ModelPaths {
  const ModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
}

class DownloadState {
  DownloadState({this.received = 0, this.total = 0, this.file = ''});
  int received;
  int total;
  String file;
  double? get fraction => total > 0 ? received / total : null;
}

/// Model dosyalarını indirir, saklar ve siler.
class ModelManager extends ChangeNotifier {
  ModelManager(this.settings);

  final SettingsService settings;

  final Map<String, bool> _installed = {};
  final Map<String, DownloadState> _downloads = {};
  final Set<String> _cancelRequested = {};
  String? lastError;

  AsrModel get activeModel => asrModelById(settings.asrModelId);

  bool isInstalledCached(AsrModel m) => _installed[m.id] ?? false;
  DownloadState? downloadOf(AsrModel m) => _downloads[m.id];
  bool isDownloading(AsrModel m) => _downloads.containsKey(m.id);

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory(p.join(support.path, 'models'));
    await d.create(recursive: true);
    return d;
  }

  Future<Directory> _dirFor(AsrModel m) async {
    final d = Directory(p.join((await _root()).path, m.id));
    await d.create(recursive: true);
    return d;
  }

  Future<String> _vadPath() async => p.join((await _root()).path, kVadFile);

  Future<void> refresh() async {
    for (final m in kAsrModels) {
      _installed[m.id] = await isInstalled(m);
    }
    notifyListeners();
  }

  Future<bool> isInstalled(AsrModel m) async {
    final dir = await _dirFor(m);
    for (final f in m.files.keys) {
      if (!await File(p.join(dir.path, f)).exists()) return false;
    }
    return File(await _vadPath()).exists();
  }

  Future<ModelPaths> pathsFor(AsrModel m) async {
    final dir = await _dirFor(m);
    return ModelPaths(
      encoder: p.join(dir.path, m.encoderFile),
      decoder: p.join(dir.path, m.decoderFile),
      tokens: p.join(dir.path, m.tokensFile),
      vad: await _vadPath(),
    );
  }

  Future<void> download(AsrModel m) async {
    if (isDownloading(m)) return;
    lastError = null;
    final state = DownloadState();
    _downloads[m.id] = state;
    _cancelRequested.remove(m.id);
    notifyListeners();

    final dir = await _dirFor(m);
    final jobs = <String, String>{}; // hedef yol → adres
    m.files.forEach((name, url) => jobs[p.join(dir.path, name)] = url);
    final vad = await _vadPath();
    if (!await File(vad).exists()) jobs[vad] = kVadUrl;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      // Toplam boyutu öğren (ilerleme çubuğu için).
      for (final url in jobs.values) {
        try {
          final req = await client.headUrl(Uri.parse(url));
          final res = await req.close();
          await res.drain<void>();
          if (res.contentLength > 0) state.total += res.contentLength;
        } catch (_) {
          // Boyut alınamazsa ilerleme yüzdesiz gösterilir.
        }
      }
      notifyListeners();

      for (final entry in jobs.entries) {
        final target = File(entry.key);
        if (await target.exists()) continue;
        state.file = p.basename(entry.key);
        await _downloadFile(client, entry.value, target, state, m.id);
      }
      _installed[m.id] = await isInstalled(m);
    } catch (e) {
      lastError = _cancelRequested.contains(m.id) ? null : 'İndirme başarısız: $e';
    } finally {
      client.close(force: true);
      _downloads.remove(m.id);
      _cancelRequested.remove(m.id);
      notifyListeners();
    }
  }

  Future<void> _downloadFile(
    HttpClient client,
    String url,
    File target,
    DownloadState state,
    String modelId,
  ) async {
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }

    final sink = part.openWrite();
    var lastNotify = DateTime.now();
    try {
      await for (final chunk in res) {
        if (_cancelRequested.contains(modelId)) throw const _Cancelled();
        sink.add(chunk);
        state.received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 250) {
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      await part.rename(target.path);
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  void cancel(AsrModel m) {
    _cancelRequested.add(m.id);
  }

  Future<void> delete(AsrModel m) async {
    final dir = await _dirFor(m);
    if (await dir.exists()) await dir.delete(recursive: true);
    _installed[m.id] = false;
    notifyListeners();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'İptal edildi';
}
