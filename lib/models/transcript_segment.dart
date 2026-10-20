/// Toplantı sırasında konuşulan tek bir parça (cümle/söz).
class TranscriptSegment {
  TranscriptSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    this.speakerId,
    this.speakerConfidence,
    this.manuallyLabeled = false,
  });

  final String id;
  final Duration start;
  final Duration end;
  String text;

  /// Eşleşen katılımcının id'si; null ise "Bilinmeyen Konuşmacı".
  String? speakerId;

  /// 0-1 arası benzerlik puanı (Faz 1c'de dolacak).
  double? speakerConfidence;

  /// Kullanıcı etiketi elle düzelttiyse true.
  bool manuallyLabeled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'text': text,
        'speakerId': speakerId,
        'speakerConfidence': speakerConfidence,
        'manuallyLabeled': manuallyLabeled,
      };

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) => TranscriptSegment(
        id: j['id'] as String,
        start: Duration(milliseconds: j['startMs'] as int? ?? 0),
        end: Duration(milliseconds: j['endMs'] as int? ?? 0),
        text: j['text'] as String? ?? '',
        speakerId: j['speakerId'] as String?,
        speakerConfidence: (j['speakerConfidence'] as num?)?.toDouble(),
        manuallyLabeled: j['manuallyLabeled'] as bool? ?? false,
      );
}
