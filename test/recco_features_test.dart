import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_meeting_notes/intelligence/insights_parser.dart';
import 'package:future_meeting_notes/intelligence/insights_service.dart';
import 'package:future_meeting_notes/intelligence/meeting_insights.dart';
import 'package:future_meeting_notes/intelligence/prompt_builder.dart';
import 'package:future_meeting_notes/models/decision_item.dart';
import 'package:future_meeting_notes/models/meeting.dart';
import 'package:future_meeting_notes/models/meeting_mark.dart';
import 'package:future_meeting_notes/models/meeting_type.dart';
import 'package:future_meeting_notes/models/participant.dart';
import 'package:future_meeting_notes/models/transcript_segment.dart';
import 'package:future_meeting_notes/services/meeting_report.dart';
import 'package:future_meeting_notes/services/meeting_search.dart';

Duration s(int sec) => Duration(seconds: sec);

Meeting sample() {
  final ahmet = Participant(id: 'a', firstName: 'Ahmet', lastName: 'Yılmaz', email: 'ahmet@bicen.com.tr');
  final ayse = Participant(id: 'b', firstName: 'Ayşe', lastName: 'Kaya', email: 'ayse@bicen.com.tr');
  final m = Meeting(
    id: 'm1',
    title: 'Haftalık Satın Alma',
    createdAt: DateTime(2026, 11, 6, 10, 0),
    startedAt: DateTime(2026, 11, 6, 10, 0),
    endedAt: DateTime(2026, 11, 6, 10, 30),
    participants: [ahmet, ayse],
    type: MeetingType.client,
    segments: [
      TranscriptSegment(id: 's1', start: s(0), end: s(10), text: 'Bütçeyi bu ay onaylıyoruz.', speakerId: 'a'),
      TranscriptSegment(id: 's2', start: s(12), end: s(17), text: 'Tamam, kampanya fiyatlarını cuma göndereceğim.', speakerId: 'b'),
      TranscriptSegment(id: 's3', start: s(20), end: s(22), text: 'Peki.', speakerId: null),
    ],
    decisions: [DecisionItem(id: 'd1', text: 'Bütçe bu ay onaylandı', at: s(3))],
    marks: [
      MeetingMark(id: 'k1', at: s(14), kind: MarkKind.task, note: 'Fiyat listesi'),
      MeetingMark(id: 'k2', at: s(5), kind: MarkKind.decision),
    ],
  );
  return m;
}

void main() {
  group('Arama', () {
    test('Türkçe karakter ve büyük/küçük harf farkı gözetmez', () {
      final m = sample();
      expect(searchMeeting(m, 'butce').map((x) => x.id), ['s1']);
      expect(searchMeeting(m, 'BÜTÇE').map((x) => x.id), ['s1']);
      expect(searchMeeting(m, 'kampanya cuma').map((x) => x.id), ['s2']);
    });

    test('Konuşmacı adıyla ve konuşmacı filtresiyle arar', () {
      final m = sample();
      expect(searchMeeting(m, 'ayse fiyat').map((x) => x.id), ['s2']);
      expect(searchMeeting(m, '', speakerId: 'a').map((x) => x.id), ['s1']);
      expect(searchMeeting(m, '', speakerId: '').map((x) => x.id), ['s3']);
    });

    test('Tüm toplantılarda arama', () {
      final hits = searchMeetings([sample(), sample()], 'fiyat');
      expect(hits.length, 2);
      expect(hits.first.speakerName, 'Ayşe Kaya');
    });

    test('Vurgulanacak aralıklar orijinal metindeki konumlardır', () {
      const text = 'Bütçeyi bütçe ile';
      expect(matchRanges(text, 'butce'), [(0, 5), (8, 13)]);
      expect(matchRanges(text, ''), isEmpty);
    });
  });

  group('Rapor', () {
    test('Kişi başı konuşma süresi', () {
      final shares = speakingShares(sample());
      expect(shares.first.name, 'Ahmet Yılmaz');
      expect(shares.first.time, s(10));
      expect(shares.map((x) => x.name), contains('Bilinmeyen'));
    });

    test('İşaret, o anda söylenen cümleyle eşleşir', () {
      final m = sample();
      final line = markLine(m, m.marks.first);
      expect(line, contains('Görev'));
      expect(line, contains('Fiyat listesi'));
      expect(line, contains('Ayşe Kaya'));
    });

    test('Takip e-postası alıcıları, kararları ve işaretleri içerir', () {
      final mail = buildFollowUpEmail(sample());
      expect(mail.to, ['ahmet@bicen.com.tr', 'ayse@bicen.com.tr']);
      expect(mail.subject, contains('Haftalık Satın Alma'));
      expect(mail.body, contains('1. Bütçe bu ay onaylandı'));
      expect(mail.body, contains('TOPLANTIDA İŞARETLENENLER'));
      final uri = mail.toMailtoUri().toString();
      expect(uri, startsWith('mailto:ahmet@bicen.com.tr,ayse@bicen.com.tr?subject='));
      expect(uri, isNot(contains('+')));
    });

    test('Markdown notu', () {
      final md = meetingToMarkdown(sample());
      expect(md, startsWith('# Haftalık Satın Alma'));
      expect(md, contains('Tedarikçi / müşteri görüşmesi'));
      expect(md, contains('## Konuşma metni'));
      expect(meetingToMarkdown(sample(), includeTranscript: false), isNot(contains('## Konuşma metni')));
    });
  });

  group('Kayıt biçimi', () {
    test('Tür, işaretler ve özet JSON gidiş-dönüşünde korunur', () {
      final m = sample()
        ..insights = MeetingInsights(
          summary: 'Özet',
          generatedAt: DateTime(2026, 11, 6),
          engine: 'test',
          actionItems: [ActionItem(task: 'Fiyat gönder', ownerId: 'b', due: 'cuma')],
        );
      final back = Meeting.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
      expect(back.type, MeetingType.client);
      expect(back.marks.length, 2);
      expect(back.marks.first.kind, MarkKind.task);
      expect(back.insights!.actionItems.single.due, 'cuma');
    });

    test('Eski kayıtlar (tür/işaret alanı yok) açılır', () {
      final old = sample().toJson()
        ..remove('type')
        ..remove('marks');
      final back = Meeting.fromJson(old);
      expect(back.type, MeetingType.general);
      expect(back.marks, isEmpty);
      expect(back.insights, isNull);
    });
  });

  group('Faz 2 zemini', () {
    test('Komut türü, odağı, işaretleri ve metni içerir', () {
      final prompt = const PromptBuilder().buildUserPrompt(sample());
      expect(prompt, contains(MeetingType.client.focus));
      expect(prompt, contains('[00:14] Görev — Fiyat listesi'));
      expect(prompt, contains('[00:12] Ayşe Kaya: Tamam'));
    });

    test('Uzun metin satır bölünmeden parçalanır', () {
      final chunks = const PromptBuilder().transcriptChunks(sample(), maxChars: 60);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        for (final line in c.split('\n')) {
          expect(line, startsWith('['));
        }
      }
    });

    test('Kod bloğu ve fazladan virgül içeren model çıktısı okunur', () {
      const raw = '''Elbette, işte sonuç:
```json
{
  "ozet": "Bütçe onaylandı.",
  "ana_basliklar": ["Bütçe", "Kampanya"],
  "kararlar": [{"karar": "Bütçe onaylandı", "kisi": "Ahmet", "zaman": "00:00"},],
  "gorevler": [
    {"gorev": "Kampanya fiyatlarını gönder", "sorumlu": "ayşe kaya", "tarih": "cuma", "zaman": "0:12"},
    {"gorev": "Sözleşmeyi incele", "sorumlu": "Hukuk", "tarih": ""}
  ],
  "acik_konular": []
}
```''';
      final ins = const InsightsParser().parse(raw, participants: sample().participants, engine: 'test');
      expect(ins.summary, 'Bütçe onaylandı.');
      expect(ins.decisions.single.ownerId, 'a');
      expect(ins.actionItems.first.ownerId, 'b');
      expect(ins.actionItems.first.at, s(12));
      expect(ins.actionItems.first.due, 'cuma');
      expect(ins.actionItems.last.ownerId, isNull);
      expect(ins.actionItems.last.ownerName, 'Hukuk');
      expect(ins.actionItems.last.due, isNull);
    });

    test('JSON yoksa anlaşılır hata', () {
      expect(
        () => const InsightsParser().parse('üzgünüm', participants: const [], engine: 'x'),
        throwsFormatException,
      );
    });

    test('Belirsiz ad eşleştirilmez', () {
      final ps = [
        Participant(id: '1', firstName: 'Ali', lastName: 'Demir', email: ''),
        Participant(id: '2', firstName: 'Ali', lastName: 'Kurt', email: ''),
      ];
      expect(InsightsParser.matchParticipant('Ali', ps), isNull);
      expect(InsightsParser.matchParticipant('kurt', ps)?.id, '2');
    });

    test('Parça sonuçları tekrarsız birleştirilir', () {
      MeetingInsights part(String sum, String task) => MeetingInsights(
            summary: sum,
            generatedAt: DateTime(2026),
            engine: 'x',
            actionItems: [ActionItem(task: task)],
            keyPoints: ['Bütçe'],
          );
      final merged = InsightsService.merge([part('A', 'Gönder'), part('B', 'gönder ')], 'x');
      expect(merged.summary, 'A\n\nB');
      expect(merged.actionItems.length, 1);
      expect(merged.keyPoints, ['Bütçe']);
    });
  });
}
