import 'decision_item.dart';
import 'participant.dart';
import 'transcript_segment.dart';

/// Toplantı akışının adımları.
enum MeetingPhase {
  /// Katılımcılar kaydediliyor ("Toplantı Öncesi Hazırlık").
  preparation,

  /// "Hazırlığı Bitir" basıldı, "Toplantıyı Başlat" bekleniyor.
  ready,

  /// Toplantı kaydı sürüyor.
  recording,

  /// Toplantı bitti; "Toplantı Kararlarını Yaz" bekleniyor.
  ended,

  /// Kararlar dikte ediliyor.
  dictatingDecisions,

  /// Tamamlandı ve kaydedildi.
  completed,
}

class Meeting {
  Meeting({
    required this.id,
    required this.title,
    required this.createdAt,
    List<Participant>? participants,
    List<TranscriptSegment>? segments,
    List<DecisionItem>? decisions,
    this.phase = MeetingPhase.preparation,
    this.startedAt,
    this.endedAt,
    this.audioPath,
    this.decisionsAudioPath,
    this.folderPath,
    this.exportPath,
  })  : participants = participants ?? [],
        segments = segments ?? [],
        decisions = decisions ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? endedAt;
  MeetingPhase phase;

  final List<Participant> participants;
  final List<TranscriptSegment> segments;
  final List<DecisionItem> decisions;

  /// Toplantının ses kaydı (16 kHz mono WAV).
  String? audioPath;

  /// Karar dikte bölümünün ayrı ses kaydı.
  String? decisionsAudioPath;

  /// Uygulama içindeki toplantı klasörü.
  String? folderPath;

  /// Ayarlarda seçilen klasöre kopyalandıysa oradaki yol.
  String? exportPath;

  Duration get duration => (startedAt != null && endedAt != null)
      ? endedAt!.difference(startedAt!)
      : Duration.zero;

  Participant? participantById(String? id) {
    if (id == null) return null;
    for (final p in participants) {
      if (p.id == id) return p;
    }
    return null;
  }

  int participantIndex(String? id) =>
      id == null ? -1 : participants.indexWhere((p) => p.id == id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'phase': phase.name,
        'audioPath': audioPath,
        'decisionsAudioPath': decisionsAudioPath,
        'folderPath': folderPath,
        'exportPath': exportPath,
        'participants': participants.map((p) => p.toJson()).toList(),
        'segments': segments.map((s) => s.toJson()).toList(),
        'decisions': decisions.map((d) => d.toJson()).toList(),
      };

  factory Meeting.fromJson(Map<String, dynamic> j) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.tryParse(v as String);
    List<Map<String, dynamic>> list(Object? v) =>
        (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

    return Meeting(
      id: j['id'] as String,
      title: j['title'] as String? ?? 'Toplantı',
      createdAt: dt(j['createdAt']) ?? DateTime.now(),
      startedAt: dt(j['startedAt']),
      endedAt: dt(j['endedAt']),
      phase: MeetingPhase.values.asNameMap()[j['phase']] ?? MeetingPhase.completed,
      audioPath: j['audioPath'] as String?,
      decisionsAudioPath: j['decisionsAudioPath'] as String?,
      folderPath: j['folderPath'] as String?,
      exportPath: j['exportPath'] as String?,
      participants: list(j['participants']).map(Participant.fromJson).toList(),
      segments: list(j['segments']).map(TranscriptSegment.fromJson).toList(),
      decisions: list(j['decisions']).map(DecisionItem.fromJson).toList(),
    );
  }
}
