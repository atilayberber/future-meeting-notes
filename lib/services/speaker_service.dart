import '../models/participant.dart';
import '../models/transcript_segment.dart';

/// Konuşmacı tanıma servisi.
///
/// FAZ 1c: sherpa-onnx ile cihaz üzerinde gerçek uygulama yazılacak:
///  - [enroll]: katılımcının ses örneğinden ses izi (embedding) çıkarır.
///  - [identifyLive]: canlı parça için ön etiket verir.
///  - [assignSpeakers]: toplantı bitince tüm kaydı kümeler, her kümeyi en
///    yakın katılımcıya eşleştirir ve kesin etiketleri döndürür. Benzerlik
///    eşiğin altındaysa speakerId = null ("Bilinmeyen Konuşmacı").
abstract class SpeakerIdentificationService {
  Future<void> enroll(Participant participant);

  Future<String?> identifyLive({
    required TranscriptSegment segment,
    required List<Participant> participants,
  });

  Future<List<TranscriptSegment>> assignSpeakers({
    required String audioPath,
    required List<TranscriptSegment> segments,
    required List<Participant> participants,
  });
}

/// Faz 1c'ye kadar yer tutucu: kimseyi tahmin etmez, etiketler elle atanır.
class PlaceholderSpeakerService implements SpeakerIdentificationService {
  @override
  Future<void> enroll(Participant participant) async {}

  @override
  Future<String?> identifyLive({
    required TranscriptSegment segment,
    required List<Participant> participants,
  }) async =>
      null;

  @override
  Future<List<TranscriptSegment>> assignSpeakers({
    required String audioPath,
    required List<TranscriptSegment> segments,
    required List<Participant> participants,
  }) async =>
      segments;
}
