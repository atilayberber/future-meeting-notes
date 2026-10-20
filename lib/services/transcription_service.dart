import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/participant.dart';
import '../models/transcript_segment.dart';

enum TranscriptionMode {
  /// Toplantı: her parça konuşmacıyla etiketlenir.
  meeting,

  /// Karar dikte: kişi etiketi yok, her söz bir madde.
  decisions,
}

/// Konuşmayı yazıya döken servis (cihaz üzerinde).
abstract class TranscriptionService {
  /// Canlı oturumda üretilen parçalar.
  Stream<TranscriptSegment> get segments;

  /// Metnin canlı sesin kaç saniye gerisinde olduğu.
  ValueListenable<double> get lagSeconds;

  /// Kullanıcıya gösterilecek sorun (ör. model indirilmemiş). null = sorun yok.
  ValueListenable<String?> get problem;

  /// Modeli önceden belleğe yükler (toplantı başlarken beklememek için).
  Future<bool> warmUp();

  Future<void> startLive({
    required TranscriptionMode mode,
    required List<Participant> participants,
    required Stream<Float32List> audio,
  });

  /// Ses akışı bitince kalan tüm konuşmayı işler; hepsi yazıya dökülünce tamamlanır.
  Future<void> stopLive();

  /// Kısa bir klibi (ad, soyad, e-posta) yazıya döker.
  Future<String> transcribeClip(Float32List samples);

  /// Kaydedilmiş bir WAV dosyasını baştan yazıya döker.
  Future<List<TranscriptSegment>> transcribeFile(
    String wavPath, {
    void Function(double fraction)? onProgress,
  });

  /// Şu an kullanılan modelin kısa adı (dosya adlarında kullanılır).
  String get modelId;
}
