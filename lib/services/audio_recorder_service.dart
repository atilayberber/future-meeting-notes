import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// Mikrofon kaydı: tek bir PCM akışından
///  - isteğe bağlı olarak WAV dosyası yazar (16 kHz, mono, 16-bit),
///  - konuşma tanımaya Float32 örnekler verir ([samples]),
///  - ekrandaki gösterge için ses seviyesi üretir ([levels]).
///
/// Otomatik kazanç / gürültü bastırma kapalı: ses izi ve konuşma tanıma için
/// ham ses daha tutarlı sonuç verir.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  static const int sampleRate = 16000;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  StreamController<Float32List>? _samples;
  final _levels = StreamController<double>.broadcast();

  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _done;
  IOSink? _sink;
  String? _wavPath;
  int _dataBytes = 0;
  int? _pendingByte;
  bool _active = false;

  /// Geçerli kaydın örnekleri. Her [start] yeni bir akış açar; [stop] onu kapatır,
  /// böylece dinleyenler kaydın bittiğini anlar.
  Stream<Float32List> get samples =>
      _samples?.stream ?? const Stream<Float32List>.empty();
  Stream<double> get levels => _levels.stream;
  bool get isActive => _active;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Kaydı başlatır. [wavPath] verilirse ses aynı anda dosyaya yazılır.
  Future<void> start({String? wavPath}) async {
    if (_active) await stop();
    _dataBytes = 0;
    _pendingByte = null;
    _wavPath = wavPath;
    if (wavPath != null) {
      _sink = File(wavPath).openWrite();
      _sink!.add(wavHeader(0));
    }
    _samples = StreamController<Float32List>.broadcast();
    final stream = await _recorder.startStream(_config);
    _done = Completer<void>();
    _active = true;
    _sub = stream.listen(
      _onChunk,
      onDone: () {
        if (!(_done?.isCompleted ?? true)) _done!.complete();
      },
    );
  }

  void _onChunk(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _sink?.add(bytes);
    _dataBytes += bytes.length;

    // Parçalar tek sayıda bayt ile gelebilir; artan baytı bir sonrakine ekle.
    var data = bytes;
    if (_pendingByte != null) {
      data = Uint8List(bytes.length + 1)
        ..[0] = _pendingByte!
        ..setRange(1, bytes.length + 1, bytes);
      _pendingByte = null;
    }
    final n = data.length ~/ 2;
    if (data.length.isOdd) _pendingByte = data[data.length - 1];
    if (n == 0) return;

    final view = ByteData.sublistView(data, 0, n * 2);
    final floats = Float32List(n);
    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final v = view.getInt16(i * 2, Endian.little) / 32768.0;
      floats[i] = v;
      sumSq += v * v;
    }
    _samples?.add(floats);

    final rms = math.sqrt(sumSq / n);
    final db = rms > 0 ? 20 * math.log(rms) / math.ln10 : -100.0;
    _levels.add(((db + 60) / 60).clamp(0.0, 1.0).toDouble());
  }

  /// Kaydı durdurur; WAV dosyası yazıldıysa yolunu döndürür.
  Future<String?> stop() async {
    if (!_active) return null;
    _active = false;
    await _recorder.stop();
    await _done?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    await _sub?.cancel();
    _sub = null;
    await _samples?.close();
    _samples = null;
    _levels.add(0);

    final path = _wavPath;
    final sink = _sink;
    _sink = null;
    _wavPath = null;
    if (sink != null && path != null) {
      await sink.flush();
      await sink.close();
      await _patchHeader(path, _dataBytes);
    }
    return path;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  static Future<void> _patchHeader(String path, int dataBytes) async {
    final raf = await File(path).open(mode: FileMode.append);
    try {
      await raf.setPosition(0);
      await raf.writeFrom(wavHeader(dataBytes));
    } finally {
      await raf.close();
    }
  }
}

/// 16 kHz, mono, 16-bit PCM WAV başlığı (44 bayt).
Uint8List wavHeader(int dataBytes) {
  const sampleRate = AudioRecorderService.sampleRate;
  final b = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // fmt bölümü boyutu
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // bayt/sn
  b.setUint16(32, 2, Endian.little); // blok hizalama
  b.setUint16(34, 16, Endian.little); // bit
  ascii(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}
