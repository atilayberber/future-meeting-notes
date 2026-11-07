import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/transcript_segment.dart';

/// Toplantı kaydını çalar; konuşma metnindeki satıra dokununca o saniyeden başlatır
/// ve çalan satırı vurgulamak için [currentSegmentId]'yi günceller.
/// (Recco'daki ses çubuğu + metinle eşzamanlı dinleme.)
class MeetingPlayer extends ChangeNotifier {
  MeetingPlayer({required List<TranscriptSegment> Function() segments}) : _segments = segments;

  final List<TranscriptSegment> Function() _segments;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Şu an çalan konuşma parçası (vurgulama için; yalnızca parça değişince bildirir).
  final ValueNotifier<String?> currentSegmentId = ValueNotifier(null);

  bool _loaded = false;
  bool get loaded => _loaded;
  String? error;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool get playing => _player.playing;
  double get speed => _player.speed;

  Future<void> load(String? path) async {
    if (path == null || !File(path).existsSync()) {
      error = 'Ses kaydı bulunamadı.';
      notifyListeners();
      return;
    }
    try {
      duration = await _player.setFilePath(path) ?? Duration.zero;
      _loaded = true;
      _subs
        ..add(_player.positionStream.listen((p) {
          position = p;
          _updateCurrent(p);
          notifyListeners();
        }))
        ..add(_player.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            unawaited(_player.pause());
            unawaited(_player.seek(Duration.zero));
          }
          notifyListeners();
        }))
        ..add(_player.durationStream.listen((d) {
          if (d != null) {
            duration = d;
            notifyListeners();
          }
        }));
    } catch (e) {
      error = 'Ses kaydı açılamadı: $e';
    }
    notifyListeners();
  }

  void _updateCurrent(Duration p) {
    String? id;
    for (final s in _segments()) {
      if (s.start <= p && p < s.end + const Duration(milliseconds: 300)) {
        id = s.id;
        break;
      }
      if (s.start > p) break;
    }
    if (currentSegmentId.value != id) currentSegmentId.value = id;
  }

  /// [at] saniyesinden çalmaya başlar (biraz önceden, cümle başı kaçmasın).
  Future<void> playFrom(Duration at) async {
    if (!_loaded) return;
    final start = at - const Duration(milliseconds: 400);
    await _player.seek(start.isNegative ? Duration.zero : start);
    unawaited(_player.play());
    notifyListeners();
  }

  Future<void> toggle() async {
    if (!_loaded) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play());
    }
    notifyListeners();
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> skip(Duration by) {
    var to = position + by;
    if (to.isNegative) to = Duration.zero;
    if (duration > Duration.zero && to > duration) to = duration;
    return _player.seek(to);
  }

  /// 1x → 1.5x → 2x → 1x
  Future<void> cycleSpeed() async {
    final next = speed < 1.25 ? 1.5 : (speed < 1.75 ? 2.0 : 1.0);
    await _player.setSpeed(next);
    notifyListeners();
  }

  Future<void> pause() => _player.pause();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    currentSegmentId.dispose();
    _player.dispose();
    super.dispose();
  }
}
