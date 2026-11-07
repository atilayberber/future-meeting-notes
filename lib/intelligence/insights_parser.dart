import 'dart:convert';

import '../models/participant.dart';
import '../services/meeting_search.dart';
import 'meeting_insights.dart';

/// Dil modelinin döndürdüğü metni [MeetingInsights]'a çevirir.
///
/// Modeller (özellikle küçük cihaz içi modeller) JSON'u çoğu zaman tam istendiği
/// gibi vermez: ```json bloğu içinde, önünde açıklama cümlesiyle, sonda fazladan
/// virgülle… Bu sınıf bunları tolere eder; okunamazsa [FormatException] fırlatır.
class InsightsParser {
  const InsightsParser();

  MeetingInsights parse(
    String raw, {
    required List<Participant> participants,
    required String engine,
    DateTime? now,
  }) {
    final json = extractJsonObject(raw);
    String str(Object? v) => (v ?? '').toString().trim();
    List<dynamic> list(Object? v) => v is List ? v : const [];

    final decisions = <InsightDecision>[];
    for (final d in list(json['kararlar'])) {
      if (d is Map) {
        final text = str(d['karar']);
        if (text.isEmpty) continue;
        decisions.add(InsightDecision(
          text: text,
          ownerId: matchParticipant(str(d['kisi']), participants)?.id,
          at: parseStamp(str(d['zaman'])),
        ));
      } else if (str(d).isNotEmpty) {
        decisions.add(InsightDecision(text: str(d)));
      }
    }

    final tasks = <ActionItem>[];
    for (final t in list(json['gorevler'])) {
      if (t is! Map) continue;
      final task = str(t['gorev']);
      if (task.isEmpty) continue;
      final ownerRaw = str(t['sorumlu']);
      final owner = matchParticipant(ownerRaw, participants);
      final due = str(t['tarih']);
      tasks.add(ActionItem(
        task: task,
        ownerId: owner?.id,
        ownerName: owner == null && ownerRaw.isNotEmpty ? ownerRaw : null,
        due: due.isEmpty ? null : due,
        at: parseStamp(str(t['zaman'])),
      ));
    }

    List<String> strings(Object? v) =>
        list(v).map(str).where((s) => s.isNotEmpty).toList();

    return MeetingInsights(
      summary: str(json['ozet']),
      keyPoints: strings(json['ana_basliklar']),
      decisions: decisions,
      actionItems: tasks,
      openQuestions: strings(json['acik_konular']),
      generatedAt: now ?? DateTime.now(),
      engine: engine,
    );
  }

  /// Metindeki ilk geçerli JSON nesnesini bulur.
  static Map<String, dynamic> extractJsonObject(String raw) {
    var text = raw.trim();
    // ```json ... ``` bloğu
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Model çıktısında JSON bulunamadı');
    }
    var body = text.substring(start, end + 1);
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      // Sık görülen hata: kapanıştan önce fazladan virgül.
      body = body.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!);
      return jsonDecode(body) as Map<String, dynamic>;
    }
  }

  /// "12:05", "1:02:03" → Duration. Okunamazsa null.
  static Duration? parseStamp(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final n = parts.map(int.tryParse).toList();
    if (n.any((x) => x == null)) return null;
    return parts.length == 2
        ? Duration(minutes: n[0]!, seconds: n[1]!)
        : Duration(hours: n[0]!, minutes: n[1]!, seconds: n[2]!);
  }

  /// Modelin yazdığı adı katılımcıya bağlar: tam ad, sadece ad veya sadece soyad
  /// (Türkçe karakter ve büyük/küçük harf farkı gözetmeden). Belirsizse null.
  static Participant? matchParticipant(String name, List<Participant> participants) {
    final n = normalizeForSearch(name);
    if (n.isEmpty) return null;
    for (final p in participants) {
      if (normalizeForSearch(p.fullName) == n) return p;
    }
    final byPart = participants.where((p) {
      final first = normalizeForSearch(p.firstName);
      final last = normalizeForSearch(p.lastName);
      return (first.isNotEmpty && first == n) || (last.isNotEmpty && last == n);
    }).toList();
    return byPart.length == 1 ? byPart.first : null;
  }
}
