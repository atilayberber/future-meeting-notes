import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Ayrı bir isolate'te çalışan konuşma tanıma motoru (VAD + Whisper).
///
/// Ana isolate ile mesajlaşır; böylece model çalışırken arayüz donmaz. Gelen
/// ses parçaları sırayla işlenir: model yavaş kalsa bile hiçbir parça atlanmaz,
/// yalnızca metin canlı akışın gerisinde kalır.
///
/// Ana → çalışan:
///   {type: init, encoder, decoder, tokens, vad, language, numThreads}
///   {type: start, session}                yeni canlı oturum (VAD sıfırlanır)
///   {type: audio, data}                   Float32 örnekler (TransferableTypedData)
///   {type: flush}                         kalan konuşmayı işle
///   {type: clip, id, data}                kısa klip (≤ 30 sn) → tek metin
///   {type: file, id, path}                16 kHz mono 16-bit WAV dosyası
///   {type: dispose}
///
/// Çalışan → ana:
///   SendPort (ilk mesaj), {type: ready}, {type: error, message}
///   {type: segment, session, start, length, text}
///   {type: progress, session, samples}
///   {type: flushed, session}
///   {type: clip, id, text}
///   {type: fileSegment, id, start, length, text}
///   {type: fileProgress, id, done, total}
///   {type: fileDone, id} / {type: fileError, id, message}
void asrWorkerMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final engine = _Engine(out);

  inbox.listen((dynamic raw) {
    final msg = raw as Map<dynamic, dynamic>;
    try {
      switch (msg['type'] as String) {
        case 'init':
          engine.init(msg);
          out.send({'type': 'ready'});
        case 'start':
          engine.startSession(msg['session'] as String);
        case 'audio':
          engine.feedLive(_floats(msg['data']));
        case 'flush':
          engine.flushLive();
        case 'clip':
          out.send({
            'type': 'clip',
            'id': msg['id'],
            'text': engine.decode(_floats(msg['data'])),
          });
        case 'file':
          engine.transcribeFile(msg['id'] as int, msg['path'] as String);
        case 'dispose':
          engine.dispose();
          inbox.close();
          Isolate.exit();
      }
    } catch (e) {
      switch (msg['type']) {
        case 'clip':
          out.send({'type': 'clip', 'id': msg['id'], 'text': ''});
        case 'file':
          out.send({'type': 'fileError', 'id': msg['id'], 'message': '$e'});
        default:
          out.send({'type': 'error', 'message': '$e'});
      }
    }
  });
}

Float32List _floats(dynamic data) =>
    (data as TransferableTypedData).materialize().asFloat32List();

const int _sampleRate = 16000;

class _Engine {
  _Engine(this.out);

  final SendPort out;

  so.OfflineRecognizer? _recognizer;
  late so.VadModelConfig _vadConfig;

  // Canlı oturum
  _VadPipeline? _live;
  String _session = '';

  void init(Map<dynamic, dynamic> m) {
    so.initBindings();

    _vadConfig = so.VadModelConfig(
      sileroVad: so.SileroVadModelConfig(
        model: m['vad'] as String,
        threshold: 0.5,
        // Kısa duraklamalarda cümleyi bölmemek için.
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        // Whisper en fazla 30 sn işler; konuşmacı değişimini yakalamak için kısa tutulur.
        maxSpeechDuration: 15.0,
      ),
      sampleRate: _sampleRate,
      numThreads: 1,
      debug: false,
    );

    final model = so.OfflineModelConfig(
      whisper: so.OfflineWhisperModelConfig(
        encoder: m['encoder'] as String,
        decoder: m['decoder'] as String,
        language: m['language'] as String? ?? 'tr',
        task: 'transcribe',
      ),
      tokens: m['tokens'] as String,
      modelType: 'whisper',
      numThreads: m['numThreads'] as int? ?? 2,
      debug: false,
    );
    _recognizer?.free();
    _recognizer = so.OfflineRecognizer(so.OfflineRecognizerConfig(model: model));
  }

  String decode(Float32List samples) {
    final rec = _recognizer;
    if (rec == null || samples.isEmpty) return '';
    final stream = rec.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      rec.decode(stream);
      return rec.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  // ------------------------------------------------------------ Canlı

  void startSession(String session) {
    _live?.free();
    _session = session;
    _live = _VadPipeline(_vadConfig, (start, samples) {
      final text = decode(samples);
      if (text.isNotEmpty) {
        out.send({
          'type': 'segment',
          'session': _session,
          'start': start,
          'length': samples.length,
          'text': text,
        });
      }
    });
  }

  void feedLive(Float32List samples) {
    final live = _live;
    if (live == null) return;
    live.feed(samples);
    out.send({'type': 'progress', 'session': _session, 'samples': live.fed});
  }

  void flushLive() {
    _live?.flush();
    out.send({'type': 'flushed', 'session': _session});
  }

  // ------------------------------------------------------------ Dosya

  /// WAV dosyasını parça parça okur (2 saatlik kayıt belleğe sığmayabilir).
  void transcribeFile(int id, String path) {
    final file = File(path).openSync();
    final pipeline = _VadPipeline(_vadConfig, (start, samples) {
      final text = decode(samples);
      if (text.isNotEmpty) {
        out.send({
          'type': 'fileSegment',
          'id': id,
          'start': start,
          'length': samples.length,
          'text': text,
        });
      }
    });
    try {
      final dataStart = _findDataChunk(file);
      final total = file.lengthSync() - dataStart;
      file.setPositionSync(dataStart);
      const chunkBytes = _sampleRate * 2 * 10; // 10 sn
      var done = 0;
      while (true) {
        final bytes = file.readSync(chunkBytes);
        if (bytes.isEmpty) break;
        done += bytes.length;
        pipeline.feed(pcm16ToFloat32(bytes));
        out.send({'type': 'fileProgress', 'id': id, 'done': done, 'total': total});
      }
      pipeline.flush();
      out.send({'type': 'fileDone', 'id': id});
    } finally {
      pipeline.free();
      file.closeSync();
    }
  }

  void dispose() {
    _live?.free();
    _live = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

/// VAD ile konuşma parçalarını ayırır ve her parça için [onSegment] çağırır.
class _VadPipeline {
  _VadPipeline(this.config, this.onSegment)
      : _vad = so.VoiceActivityDetector(config: config, bufferSizeInSeconds: 60),
        _buffer = so.CircularBuffer(capacity: 60 * _sampleRate);

  final so.VadModelConfig config;
  final void Function(int startSample, Float32List samples) onSegment;
  final so.VoiceActivityDetector _vad;
  final so.CircularBuffer _buffer;

  /// VAD'e verilen toplam örnek sayısı.
  int fed = 0;

  void feed(Float32List samples) {
    _buffer.push(samples);
    final window = config.sileroVad.windowSize;
    while (_buffer.size >= window) {
      final w = _buffer.get(startIndex: _buffer.head, n: window);
      _buffer.pop(window);
      _vad.acceptWaveform(w);
      fed += window;
      _drain();
    }
  }

  void flush() {
    _vad.flush();
    _drain();
  }

  void _drain() {
    while (!_vad.isEmpty()) {
      final seg = _vad.front();
      _vad.pop();
      onSegment(seg.start, seg.samples);
    }
  }

  void free() {
    _vad.free();
    _buffer.free();
  }
}

/// 16-bit little-endian PCM → [-1, 1] float.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.sublistView(bytes, 0, n * 2);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// WAV başlığında "data" bölümünün başladığı konumu bulur.
int _findDataChunk(RandomAccessFile f) {
  f.setPositionSync(12); // "RIFF", boyut, "WAVE"
  final len = f.lengthSync();
  while (f.positionSync() + 8 <= len) {
    final header = f.readSync(8);
    final id = String.fromCharCodes(header.sublist(0, 4));
    final size = ByteData.sublistView(header).getUint32(4, Endian.little);
    if (id == 'data') return f.positionSync();
    f.setPositionSync(f.positionSync() + size + (size.isOdd ? 1 : 0));
  }
  return 44;
}
