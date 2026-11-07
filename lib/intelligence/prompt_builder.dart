import '../models/meeting.dart';
import '../models/meeting_mark.dart';
import '../utils/format.dart';

/// Faz 2: toplantı metninden özet / karar / görev çıkarmak için dil modeline
/// verilecek komutları hazırlar. Motor (cihaz içi veya sunucu) ne olursa olsun
/// aynı şablon kullanılır; çıktı [InsightsParser] ile okunur.
///
/// Recco'dan alınan fikirler:
///  - Toplantı türüne göre odak (tür → [MeetingType.focus]),
///  - Kayıt sırasında işaretlenen anlar modele "burası önemli" ipucu olarak verilir,
///  - Kararlar ve görevler kişiye ve ana bağlanır (kim, ne zaman söyledi).
class PromptBuilder {
  const PromptBuilder();

  static const systemPrompt = '''
Sen bir toplantı tutanağı asistanısın. Sana yüz yüze bir toplantının konuşmacı etiketli
metni verilecek. Metin otomatik konuşma tanımayla çıkarıldı; yazım hataları ve yanlış
konuşmacı etiketleri olabilir.

Kurallar:
- Yalnızca metinde gerçekten söylenenleri yaz. Tahmin etme, eklemede bulunma.
- Bir şeyin karar olması için açıkça kabul edilmiş olması gerekir ("tamam, öyle yapalım",
  "onaylıyoruz", "şu tarihte başlıyoruz"). Önerileri karar sayma.
- Görev: belirli bir kişiye verilen ya da birinin üstlendiği iş. Sorumlu söylenmediyse boş bırak.
- Tarihleri söylendiği gibi yaz ("cuma", "ay sonu"); takvim tarihine çevirme.
- Kişi adlarını katılımcı listesindeki yazılışla kullan.
- Zaman damgasını ilgili sözün başındaki [dk:sn] değerinden al.
- Türkçe yaz. Sadece istenen JSON'u döndür, başka hiçbir şey yazma.''';

  /// Beklenen JSON şeması (modele örnek olarak verilir).
  static const outputSchema = '''
{
  "ozet": "3-5 cümlelik genel özet",
  "ana_basliklar": ["..."],
  "kararlar": [{"karar": "...", "kisi": "Ad Soyad veya boş", "zaman": "dk:sn"}],
  "gorevler": [{"gorev": "...", "sorumlu": "Ad Soyad veya boş", "tarih": "söylendiği gibi veya boş", "zaman": "dk:sn"}],
  "acik_konular": ["karara bağlanmayan konular"]
}''';

  /// Tek seferde gönderilecek kullanıcı mesajı.
  String buildUserPrompt(Meeting m, {String? transcriptOverride}) {
    final b = StringBuffer()
      ..writeln('TOPLANTI: ${m.title}')
      ..writeln('TÜR: ${m.type.label}')
      ..writeln('ODAK: ${m.type.focus}')
      ..writeln('KATILIMCILAR: ${m.participants.map((p) => p.fullName).join(', ')}')
      ..writeln();

    final marks = [...m.marks]..sort((a, c) => a.at.compareTo(c.at));
    if (marks.isNotEmpty) {
      b.writeln('TOPLANTI SIRASINDA ELLE İŞARETLENEN ANLAR (bu anlara özellikle dikkat et):');
      for (final k in marks) {
        final note = k.note.trim().isEmpty ? '' : ' — ${k.note.trim()}';
        b.writeln('[${formatDuration(k.at)}] ${k.kind.label}$note');
      }
      b.writeln();
    }

    b
      ..writeln('METİN:')
      ..writeln(transcriptOverride ?? transcriptText(m))
      ..writeln()
      ..writeln('Yukarıdaki toplantıyı şu JSON biçiminde çıkar:')
      ..writeln(outputSchema);
    return b.toString();
  }

  /// Modelin okuyacağı metin: "[02:15] Ahmet Yılmaz: ..."
  String transcriptText(Meeting m) {
    final b = StringBuffer();
    for (final s in m.segments) {
      final who = m.participantById(s.speakerId)?.fullName ?? 'Bilinmeyen';
      b.writeln('[${formatDuration(s.start)}] $who: ${s.text}');
    }
    return b.toString().trimRight();
  }

  /// Uzun toplantılar için metni, satır bölmeden [maxChars] sınırında parçalara ayırır.
  /// Küçük (cihaz içi) modellerin bağlam penceresi dar olduğunda önce her parça
  /// ayrı özetlenir, sonra parça özetleri birleştirilir.
  List<String> transcriptChunks(Meeting m, {int maxChars = 6000}) {
    final lines = transcriptText(m).split('\n');
    final chunks = <String>[];
    final current = StringBuffer();
    for (final line in lines) {
      if (current.isNotEmpty && current.length + line.length + 1 > maxChars) {
        chunks.add(current.toString().trimRight());
        current.clear();
      }
      current.writeln(line);
    }
    if (current.toString().trim().isNotEmpty) chunks.add(current.toString().trimRight());
    return chunks;
  }

  /// Dikte edilen kararlarla konuşmadan çıkan kararları eşleştirme komutu
  /// (kullanıcının istediği "arka plan karşılaştırması").
  String buildComparisonPrompt({
    required List<String> dictated,
    required List<String> extracted,
    List<MeetingMark> decisionMarks = const [],
  }) {
    final b = StringBuffer()
      ..writeln('İki karar listesi var. Aynı kararı anlatan maddeleri eşleştir.')
      ..writeln()
      ..writeln('A) Toplantı sonunda dikte edilen kararlar:');
    for (var i = 0; i < dictated.length; i++) {
      b.writeln('A${i + 1}. ${dictated[i]}');
    }
    b
      ..writeln()
      ..writeln('B) Konuşmadan çıkarılan kararlar:');
    for (var i = 0; i < extracted.length; i++) {
      b.writeln('B${i + 1}. ${extracted[i]}');
    }
    if (decisionMarks.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Toplantıda "Karar" diye işaretlenen anlar: '
            '${decisionMarks.map((k) => formatDuration(k.at)).join(', ')}');
    }
    b
      ..writeln()
      ..writeln('Sadece şu JSON\'u döndür:')
      ..writeln('{"eslesen": [["A1","B2"]], "sadece_dikte": ["A3"], '
          '"sadece_konusma": ["B1"], "celisen": [["A2","B3","kısa açıklama"]]}');
    return b.toString();
  }
}
