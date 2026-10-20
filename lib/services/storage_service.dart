import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/meeting.dart';
import '../utils/format.dart';
import 'settings_service.dart';

/// Toplantıların cihazda saklanması.
///
/// Kayıtlar her zaman önce uygulamanın kendi klasörüne yazılır (her platformda
/// yazma izni garanti). Toplantı tamamlanınca, ayarlarda bir klasör seçildiyse
/// oraya kopyalanır. Kopyalama başarısız olursa kayıt kaybolmaz.
///
///   <Belgeler>/FutureMeetingNotes/toplantilar/2026-10-19_22-29_Haftalik_Toplanti/
///       toplanti.wav      (toplantı ses kaydı)
///       kararlar.wav      (karar dikte kaydı)
///       toplanti.json     (katılımcılar, metin, kararlar)
///   <Belgeler>/FutureMeetingNotes/ses_profilleri/<katilimci-id>.wav
class StorageService {
  StorageService(this.settings);

  final SettingsService settings;

  Future<Directory> _base() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'FutureMeetingNotes'));
  }

  Future<Directory> meetingsDir() async {
    final d = Directory(p.join((await _base()).path, 'toplantilar'));
    await d.create(recursive: true);
    return d;
  }

  /// Ses örnekleri ayrı tutulur (KVKK: biyometrik veri, ileride ayrı saklama/silme kuralı).
  Future<Directory> voiceProfilesDir() async {
    final d = Directory(p.join((await _base()).path, 'ses_profilleri'));
    await d.create(recursive: true);
    return d;
  }

  Future<String> createMeetingFolder(Meeting m) async {
    final root = await meetingsDir();
    final name =
        '${fileStamp(m.startedAt ?? DateTime.now())}_${sanitizeFileName(m.title)}';
    var dir = Directory(p.join(root.path, name));
    var i = 2;
    while (await dir.exists()) {
      dir = Directory(p.join(root.path, '${name}_$i'));
      i++;
    }
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> saveMeeting(Meeting m) async {
    final folder = m.folderPath;
    if (folder == null) return;
    final file = File(p.join(folder, 'toplanti.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(m.toJson()),
      flush: true,
    );
  }

  /// Okunabilir metin dökümü: "[02:15] Ahmet Yılmaz: ..."
  /// Varsayılan dosya: toplanti_metni.txt. Model karşılaştırması için farklı ad verilebilir.
  Future<void> writeTranscriptText(Meeting m, {String fileName = 'toplanti_metni.txt'}) async {
    final folder = m.folderPath;
    if (folder == null) return;
    final b = StringBuffer()
      ..writeln(m.title)
      ..writeln('${formatDateTime(m.startedAt ?? m.createdAt)} · ${formatDuration(m.duration)}')
      ..writeln('Katılımcılar: ${m.participants.map((p) => p.fullName).join(', ')}')
      ..writeln();
    for (final s in m.segments) {
      final who = m.participantById(s.speakerId)?.fullName ?? 'Bilinmeyen';
      b.writeln('[${formatDuration(s.start)}] $who: ${s.text}');
    }
    if (m.decisions.isNotEmpty) {
      b
        ..writeln()
        ..writeln('DİKTE EDİLEN KARARLAR');
      for (var i = 0; i < m.decisions.length; i++) {
        b.writeln('${i + 1}. ${m.decisions[i].text}');
      }
    }
    await File(p.join(folder, fileName)).writeAsString(b.toString(), flush: true);
  }

  Future<List<Meeting>> listMeetings() async {
    final root = await meetingsDir();
    final result = <Meeting>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'toplanti.json'));
      if (!await file.exists()) continue;
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        result.add(Meeting.fromJson(json));
      } catch (_) {
        // Bozuk dosya: listede gösterme, silme.
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Ayarlarda klasör seçildiyse toplantı klasörünü oraya kopyalar.
  /// Klasör seçilmemişse null döner; hata olursa istisna fırlatır.
  Future<String?> exportMeeting(Meeting m) async {
    final target = settings.exportDir;
    final folder = m.folderPath;
    if (target == null || folder == null) return null;

    final dest = Directory(p.join(target, p.basename(folder)));
    await dest.create(recursive: true);
    await for (final entity in Directory(folder).list()) {
      if (entity is File) {
        await entity.copy(p.join(dest.path, p.basename(entity.path)));
      }
    }
    return dest.path;
  }
}
