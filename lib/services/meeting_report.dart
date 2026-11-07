import '../models/meeting.dart';
import '../models/meeting_mark.dart';
import '../utils/format.dart';

/// Kişi başına konuşma süresi ve payı.
class SpeakerShare {
  SpeakerShare({required this.participantId, required this.name, required this.time, required this.turns});

  /// null = Bilinmeyen Konuşmacı.
  final String? participantId;
  final String name;
  final Duration time;
  final int turns;
}

/// Konuşma süresini kişilere göre toplar (en çok konuşan önce).
/// Payların toplamı = konuşulan toplam süre (sessizlikler hariç).
List<SpeakerShare> speakingShares(Meeting m) {
  final time = <String?, Duration>{};
  final turns = <String?, int>{};
  for (final s in m.segments) {
    final d = s.end - s.start;
    if (d.isNegative) continue;
    time[s.speakerId] = (time[s.speakerId] ?? Duration.zero) + d;
    turns[s.speakerId] = (turns[s.speakerId] ?? 0) + 1;
  }
  final result = [
    for (final e in time.entries)
      SpeakerShare(
        participantId: e.key,
        name: m.participantById(e.key)?.fullName ?? 'Bilinmeyen',
        time: e.value,
        turns: turns[e.key] ?? 0,
      ),
  ]..sort((a, b) => b.time.compareTo(a.time));
  return result;
}

/// Katılımcılara gönderilecek / paylaşılacak toplantı notu (Markdown).
///
/// İçerik: başlık bilgisi, (varsa) yapay zekâ özeti, dikte edilen kararlar,
/// kayıt sırasında işaretlenen anlar, görevler ve [includeTranscript] ise tam metin.
String meetingToMarkdown(Meeting m, {bool includeTranscript = true}) {
  final b = StringBuffer()
    ..writeln('# ${m.title}')
    ..writeln()
    ..writeln('- **Tarih:** ${formatDateTime(m.startedAt ?? m.createdAt)}')
    ..writeln('- **Süre:** ${formatDuration(m.duration)}')
    ..writeln('- **Tür:** ${m.type.label}')
    ..writeln('- **Katılımcılar:** ${m.participants.map((p) => p.fullName).join(', ')}')
    ..writeln();

  final ins = m.insights;
  if (ins != null && ins.summary.trim().isNotEmpty) {
    b
      ..writeln('## Özet')
      ..writeln()
      ..writeln(ins.summary.trim())
      ..writeln();
  }

  if (m.decisions.isNotEmpty) {
    b
      ..writeln('## Kararlar')
      ..writeln();
    for (var i = 0; i < m.decisions.length; i++) {
      b.writeln('${i + 1}. ${m.decisions[i].text}');
    }
    b.writeln();
  }

  if (ins != null && ins.actionItems.isNotEmpty) {
    b
      ..writeln('## Görevler')
      ..writeln();
    for (final a in ins.actionItems) {
      final owner = m.participantById(a.ownerId)?.fullName ?? a.ownerName;
      final parts = [
        a.task,
        if (owner != null && owner.isNotEmpty) '— $owner',
        if (a.due != null && a.due!.isNotEmpty) '(${a.due})',
      ];
      b.writeln('- [ ] ${parts.join(' ')}');
    }
    b.writeln();
  }

  if (m.marks.isNotEmpty) {
    b
      ..writeln('## Toplantıda işaretlenen anlar')
      ..writeln();
    for (final mark in [...m.marks]..sort((a, c) => a.at.compareTo(c.at))) {
      b.writeln('- ${markLine(m, mark)}');
    }
    b.writeln();
  }

  if (includeTranscript && m.segments.isNotEmpty) {
    b
      ..writeln('## Konuşma metni')
      ..writeln();
    for (final s in m.segments) {
      final who = m.participantById(s.speakerId)?.fullName ?? 'Bilinmeyen';
      b.writeln('**[${formatDuration(s.start)}] $who:** ${s.text}  ');
    }
  }
  return b.toString();
}

/// "[12:30] Karar — not — «o anda söylenen»" biçiminde tek satır.
String markLine(Meeting m, MeetingMark mark) {
  final said = m.segmentAt(mark.at);
  final parts = <String>['[${formatDuration(mark.at)}] ${mark.kind.label}'];
  if (mark.note.trim().isNotEmpty) parts.add(mark.note.trim());
  if (said != null) {
    final who = m.participantById(said.speakerId)?.fullName ?? 'Bilinmeyen';
    parts.add('$who: «${said.text}»');
  }
  return parts.join(' — ');
}

/// Toplantı sonrası takip e-postası (Recco'daki "follow-up email" karşılığı).
/// Yapay zekâ gerektirmez: dikte edilen kararlar ve işaretlenen anlardan kurulur;
/// Faz 2 özeti varsa o da eklenir.
class FollowUpEmail {
  FollowUpEmail({required this.to, required this.subject, required this.body});

  final List<String> to;
  final String subject;
  final String body;

  /// mailto: bağlantısı (alıcılar, konu ve gövde ile).
  Uri toMailtoUri() => Uri(
        scheme: 'mailto',
        path: to.join(','),
        // Uri.queryParameters boşlukları '+' yapar; e-posta istemcileri bunu
        // düz '+' gösterebildiği için %20 ile elle kodlanır.
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
}

FollowUpEmail buildFollowUpEmail(Meeting m) {
  final to = m.participants
      .map((p) => p.email.trim())
      .where((e) => e.contains('@'))
      .toSet()
      .toList();
  final date = formatDateTime(m.startedAt ?? m.createdAt);
  final b = StringBuffer()
    ..writeln('Merhaba,')
    ..writeln()
    ..writeln('$date tarihli "${m.title}" toplantısının notları aşağıdadır.')
    ..writeln();

  final ins = m.insights;
  if (ins != null && ins.summary.trim().isNotEmpty) {
    b
      ..writeln('ÖZET')
      ..writeln(ins.summary.trim())
      ..writeln();
  }

  if (m.decisions.isNotEmpty) {
    b.writeln('ALINAN KARARLAR');
    for (var i = 0; i < m.decisions.length; i++) {
      b.writeln('${i + 1}. ${m.decisions[i].text}');
    }
    b.writeln();
  }

  final tasks = ins?.actionItems ?? const [];
  if (tasks.isNotEmpty) {
    b.writeln('GÖREVLER');
    for (final a in tasks) {
      final owner = m.participantById(a.ownerId)?.fullName ?? a.ownerName ?? '';
      final due = (a.due ?? '').isEmpty ? '' : ' (${a.due})';
      b.writeln('- ${a.task}${owner.isEmpty ? '' : ' — $owner'}$due');
    }
    b.writeln();
  }

  final flagged = m.marks
      .where((k) => k.kind == MarkKind.task || k.kind == MarkKind.decision)
      .toList()
    ..sort((a, c) => a.at.compareTo(c.at));
  if (flagged.isNotEmpty) {
    b.writeln('TOPLANTIDA İŞARETLENENLER');
    for (final k in flagged) {
      b.writeln('- ${markLine(m, k)}');
    }
    b.writeln();
  }

  b
    ..writeln('Katılımcılar: ${m.participants.map((p) => p.fullName).join(', ')}')
    ..writeln()
    ..writeln('İyi çalışmalar.');

  return FollowUpEmail(
    to: to,
    subject: 'Toplantı notları: ${m.title} ($date)',
    body: b.toString(),
  );
}
