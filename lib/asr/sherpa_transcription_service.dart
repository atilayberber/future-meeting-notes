import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/participant.dart';
import '../models/transcript_segment.dart';
import '../services/transcription_service.dart';
import 'asr_worker.dart';
import 'model_manager.dart';
import 'text_cleaner.dart';

const int _sampleRate = 16000;

Duration _samplesToDuration(int samples) =>
    Duration(microseconds: samples * 1000000 ~/ _sampleRate);

/// sherpa-onnx + Whisper ile cihaz üzerinde konuşma tanıma.
class SherpaTranscriptionService implements TranscriptionService {
  SherpaTranscriptionService({required this.models});

  final ModelManager models;
  final _uuid = const Uuid();

  final _segments = StreamController<TranscriptSegment>.broadcast();
  final _lag = ValueNotifier<double>(0);
  final _problem = ValueNotifier<String?>(null);

  Isolate? _isolate;
  ReceivePort? _inbox;
  SendPort? _send;
  Completer<void>? _ready;
  String? _loadedModelId;

  // Canlı oturum
  String _session = '';
  int _sentSamples = 0;
  StreamSubscription<Float32List>? _audioSub;
  Completer<void>? _audioDone;
  Completer<void>? _flushed;
  bool _liveActive = false;

  // Klip / dosya işleri
  int _nextId = 1;
  final Map<int, Completer<String>> _clips = {};
  final Map<int, _FileJob> _files = {};

  @override
  Stream<TranscriptSegment> get segments => _segments.stream;

  @override
  ValueListenable<double> get lagSeconds => _lag;

  @override
  ValueListenable<String?> get problem => _problem;

  @override
  String get modelId => models.activeModel.id;

  // ------------------------------------------------------------ Yükleme

  Future<bool>? _warming;

  /// Aynı anda gelen çağrılar tek bir yüklemeyi paylaşır (iki isolate açılmasın).
  @override
  Future<bool> warmUp() =>
      _warming ??= _warmUp().whenComplete(() => _warming = null);

  Future<bool> _warmUp() async {
    final model = models.activeModel;
    if (!await models.isInstalled(model)) {
      _problem.value = 'Konuşma tanıma modeli indirilmemiş. '
          'Ayarlar → Konuşma tanıma modeli bölümünden indirin. Ses kaydı yine de alınır.';
      return false;
    }
    if (_ready != null && _loadedModelId == model.id) {
      try {
        await _ready!.future;
        return true;
      } catch (_) {
        return false;
      }
    }

    await _shutdown();
    _problem.value = null;
    _loadedModelId = model.id;
    final ready = Completer<void>();
    _ready = ready;
    final paths = await models.pathsFor(model);
    final inbox = ReceivePort();
    _inbox = inbox;
    inbox.listen((dynamic msg) {
      if (msg == null) {
        _onWorkerDied();
      } else if (msg is SendPort) {
        _send = msg;
        msg.send({
          'type': 'init',
          'encoder': paths.encoder,
          'decoder': paths.decoder,
          'tokens': paths.tokens,
          'vad': paths.vad,
          'language': 'tr',
          'numThreads': _threads(),
        });
      } else {
        _onMessage(msg as Map<dynamic, dynamic>);
      }
    });
    _isolate = await Isolate.spawn(
      asrWorkerMain,
      inbox.sendPort,
      onExit: inbox.sendPort, // beklenmedik kapanışta null gelir
    );

    try {
      await ready.future;
      return true;
    } catch (e) {
      _problem.value = 'Model yüklenemedi: $e';
      await _shutdown(); // bir sonraki denemede yeniden başlatılır
      return false;
    }
  }

  int _threads() {
    final cores = Platform.numberOfProcessors;
    return math.max(1, math.min(4, cores - 2));
  }

  Future<void> _shutdown() async {
    _send?.send({'type': 'dispose'});
    _send = null;
    _inbox?.close();
    _inbox = null;
    _isolate = null;
    _ready = null;
    _loadedModelId = null;
  }

  /// Çalışan isolate beklenmedik şekilde kapandı (çoğunlukla yetersiz bellek).
  /// Bekleyen her işi serbest bırak ki arayüz takılı kalmasın.
  void _onWorkerDied() {
    const message = 'Konuşma tanıma motoru kapandı. Bellek yetersiz olabilir; '
        'Ayarlar\'dan daha küçük bir model seçin.';
    _problem.value = message;
    if (!(_ready?.isCompleted ?? true)) _ready!.completeError(message);
    if (!(_flushed?.isCompleted ?? true)) _flushed!.complete();
    for (final c in _clips.values) {
      c.complete('');
    }
    _clips.clear();
    for (final job in _files.values) {
      job.completer.completeError(message);
    }
    _files.clear();
    _liveActive = false;
    _lag.value = 0;
    _send = null;
    _inbox?.close();
    _inbox = null;
    _isolate = null;
    _ready = null;
    _loadedModelId = null;
  }

  // ------------------------------------------------------------ Mesajlar

  void _onMessage(Map<dynamic, dynamic> m) {
    switch (m['type'] as String) {
      case 'ready':
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      case 'error':
        final message = m['message'] as String;
        if (!(_ready?.isCompleted ?? true)) {
          _ready!.completeError(message);
        } else {
          _problem.value = 'Konuşma tanıma hatası: $message';
        }
      case 'segment':
        if (m['session'] != _session) return;
        final seg = _toSegment(m['start'] as int, m['length'] as int, m['text'] as String);
        if (seg != null) _segments.add(seg);
      case 'progress':
        if (m['session'] != _session) return;
        _lag.value = math.max(0, (_sentSamples - (m['samples'] as int)) / _sampleRate);
      case 'flushed':
        if (m['session'] != _session) return;
        _lag.value = 0;
        if (!(_flushed?.isCompleted ?? true)) _flushed!.complete();
      case 'clip':
        _clips.remove(m['id'] as int)?.complete(m['text'] as String);
      case 'fileSegment':
        final job = _files[m['id'] as int];
        final seg = _toSegment(m['start'] as int, m['length'] as int, m['text'] as String);
        if (job != null && seg != null) job.segments.add(seg);
      case 'fileProgress':
        final job = _files[m['id'] as int];
        final total = m['total'] as int;
        if (job != null && total > 0) job.onProgress?.call((m['done'] as int) / total);
      case 'fileDone':
        final job = _files.remove(m['id'] as int);
        job?.completer.complete(job.segments);
      case 'fileError':
        _files.remove(m['id'] as int)?.completer.completeError(m['message'] as String);
    }
  }

  TranscriptSegment? _toSegment(int start, int length, String raw) {
    final text = TextCleaner.clean(raw);
    if (text == null) return null;
    return TranscriptSegment(
      id: _uuid.v4(),
      start: _samplesToDuration(start),
      end: _samplesToDuration(start + length),
      text: text,
    );
  }

  // ------------------------------------------------------------ Canlı

  @override
  Future<void> startLive({
    required TranscriptionMode mode,
    required List<Participant> participants,
    required Stream<Float32List> audio,
  }) async {
    final previous = _audioSub;
    _session = _uuid.v4();
    _sentSamples = 0;
    _lag.value = 0;
    _liveActive = false;

    // Ses akışına hemen abone ol: model yüklenirken gelen ses tamponda bekler,
    // böylece toplantının ilk saniyeleri kaybolmaz.
    final pending = <Float32List>[];
    var ready = false;
    var failed = false;
    _audioDone = Completer<void>();
    _audioSub = audio.listen(
      (chunk) {
        if (failed) return;
        if (!ready) {
          pending.add(chunk);
        } else {
          _sendAudio(chunk);
        }
      },
      onDone: () {
        if (!(_audioDone?.isCompleted ?? true)) _audioDone!.complete();
      },
    );
    await previous?.cancel();

    if (!await warmUp()) {
      failed = true;
      pending.clear();
      return;
    }
    _send!.send({'type': 'start', 'session': _session});
    for (final chunk in pending) {
      _sendAudio(chunk);
    }
    pending.clear();
    ready = true;
    _liveActive = true;
  }

  void _sendAudio(Float32List chunk) {
    final send = _send;
    if (send == null) return;
    _sentSamples += chunk.length;
    send.send({
      'type': 'audio',
      'data': TransferableTypedData.fromList([chunk]),
    });
  }

  @override
  Future<void> stopLive() async {
    // Kayıt durunca ses akışının son parçalarının gelmesini bekle.
    await _audioDone?.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    await _audioSub?.cancel();
    _audioSub = null;

    final send = _send;
    if (send == null || !_liveActive) return;
    _liveActive = false;
    final flushed = Completer<void>();
    _flushed = flushed;
    send.send({'type': 'flush'});
    await flushed.future;
  }

  // ------------------------------------------------------------ Klip / Dosya

  @override
  Future<String> transcribeClip(Float32List samples) async {
    if (!await warmUp()) return '';
    final id = _nextId++;
    final c = Completer<String>();
    _clips[id] = c;
    _send!.send({
      'type': 'clip',
      'id': id,
      'data': TransferableTypedData.fromList([samples]),
    });
    final text = await c.future;
    return TextCleaner.clean(text) ?? '';
  }

  @override
  Future<List<TranscriptSegment>> transcribeFile(
    String wavPath, {
    void Function(double fraction)? onProgress,
  }) async {
    if (!await warmUp()) {
      throw StateError(_problem.value ?? 'Model hazır değil');
    }
    final id = _nextId++;
    final job = _FileJob(onProgress);
    _files[id] = job;
    _send!.send({'type': 'file', 'id': id, 'path': wavPath});
    return job.completer.future;
  }
}

class _FileJob {
  _FileJob(this.onProgress);
  final void Function(double fraction)? onProgress;
  final List<TranscriptSegment> segments = [];
  final Completer<List<TranscriptSegment>> completer = Completer();
}
