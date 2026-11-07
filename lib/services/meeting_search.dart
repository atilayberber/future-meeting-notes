import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import '../utils/turkish.dart';

/// Arama için metni sadeleştirir: Türkçe küçük harf, aksansız, tek boşluk.
/// "Bütçe", "BÜTÇE" ve "butce" aynı şekilde eşleşir.
String normalizeForSearch(String s) =>
    toAscii(trLower(s)).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Bir konuşma parçasında bulunan eşleşme.
class SearchHit {
  SearchHit({required this.meeting, required this.segment});

  final Meeting meeting;
  final TranscriptSegment segment;

  String get speakerName =>
      meeting.participantById(segment.speakerId)?.fullName ?? 'Bilinmeyen';
}

/// Tek bir parçanın sorguya uyup uymadığı. Sorgudaki her kelime geçmeli
/// (sıra önemli değil): "bütçe ahmet" → hem "bütçe" hem "ahmet" geçen parçalar.
/// Konuşmacının adı da aranır: "Ahmet" yazınca Ahmet'in söyledikleri bulunur.
bool segmentMatches(Meeting m, TranscriptSegment s, String query) {
  final words = normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return false;
  final speaker = m.participantById(s.speakerId)?.fullName ?? '';
  final haystack = normalizeForSearch('${s.text} $speaker');
  return words.every(haystack.contains);
}

/// Bir toplantı içinde arama; [speakerId] verilirse yalnızca o kişinin sözleri.
/// [speakerId] olarak boş metin ('') "Bilinmeyen Konuşmacı" demektir.
List<TranscriptSegment> searchMeeting(
  Meeting m,
  String query, {
  String? speakerId,
}) {
  final q = query.trim();
  return m.segments.where((s) {
    if (speakerId != null) {
      final sid = s.speakerId ?? '';
      if (sid != speakerId) return false;
    }
    return q.isEmpty || segmentMatches(m, s, q);
  }).toList();
}

/// Tüm toplantılarda arama ("kim ne dedi"). En yeni toplantı önce.
List<SearchHit> searchMeetings(List<Meeting> meetings, String query, {int limit = 200}) {
  final hits = <SearchHit>[];
  if (query.trim().isEmpty) return hits;
  for (final m in meetings) {
    for (final s in m.segments) {
      if (segmentMatches(m, s, query)) {
        hits.add(SearchHit(meeting: m, segment: s));
        if (hits.length >= limit) return hits;
      }
    }
  }
  return hits;
}

/// Eşleşen kelimelerin metindeki yerleri (vurgulamak için). Aksansız karşılaştırır
/// ama orijinal metindeki konumları döndürür.
List<(int, int)> matchRanges(String text, String query) {
  final words = normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  // toAscii ve trLower karakter sayısını değiştirmez (tek harf → tek harf),
  // böylece konumlar orijinal metinle aynı kalır.
  final folded = toAscii(trLower(text));
  if (folded.length != text.length) return const [];
  final ranges = <(int, int)>[];
  for (final w in words) {
    var i = folded.indexOf(w);
    while (i >= 0) {
      ranges.add((i, i + w.length));
      i = folded.indexOf(w, i + w.length);
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  // Çakışanları birleştir.
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}
