import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/decision_item.dart';
import '../models/meeting.dart';
import '../models/participant.dart';
import '../models/transcript_segment.dart';
import '../services/audio_recorder_service.dart';
import '../services/speaker_service.dart';
import '../services/storage_service.dart';
import '../services/transcription_service.dart';
import '../utils/format.dart';

/// Aktif toplantının durum makinesi:
/// preparation -> ready -> recording -> ended -> (dictatingDecisions) -> completed
class MeetingController extends ChangeNotifier {
  MeetingController({
    required this.storage,
    required this.recorder,
    required this.transcription,
    required this.speakers,
  });

  final StorageService storage;
  final AudioRecorderService recorder;
  final TranscriptionService transcription;
  final SpeakerIdentificationService speakers;

  final _uuid = const Uuid();
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<TranscriptSegment>? _segmentSub;
  StreamSubscription<double>? _levelSub;

  Meeting? _meeting;
  Meeting? get meeting => _meeting;

  double _level = 0;
  double get level => _level;

  /// Uzun süren bir işlem varsa kullanıcıya gösterilecek açıklama.
  String? _busyMessage;
  String? get busyMessage => _busyMessage;
  bool get busy => _busyMessage != null;

  String? lastError;

  /// Tamamlanan toplantı sayısı (ana sayfa listesini yenilemek için).
  int completedCount = 0;

  Duration get elapsed => _stopwatch.elapsed;

  ValueListenable<double> get transcriptionLag => transcription.lagSeconds;
  ValueListenable<String?> get transcriptionProblem => transcription.problem;

  void _setBusy(String? message) {
    _busyMessage = message;
    notifyListeners();
  }

  // ---------------------------------------------------------------- Hazırlık

  void newMeeting() {
    final now = DateTime.now();
    _meeting = Meeting(
      id: _uuid.v4(),
      title: 'Toplantı ${formatDateTime(now)}',
      createdAt: now,
    );
    lastError = null;
    notifyListeners();
    // Model hazırlık sırasında belleğe yüklensin; toplantı başlarken beklenmesin.
    unawaited(transcription.warmUp());
  }

  void setTitle(String title) {
    _meeting?.title = title;
  }

  Future<void> addParticipant(Participant participant) async {
    _meeting?.participants.add(participant);
    notifyListeners();
    await speakers.enroll(participant);
  }

  void removeParticipant(String id) {
    _meeting?.participants.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void finishPreparation() {
    final m = _meeting;
    if (m == null || m.participants.isEmpty) return;
    m.phase = MeetingPhase.ready;
    notifyListeners();
  }

  void backToPreparation() {
    _meeting?.phase = MeetingPhase.preparation;
    notifyListeners();
  }

  // ----------------------------------------------------------------- Toplantı

  Future<bool> startMeeting() async {
    final m = _meeting;
    if (m == null) return false;
    if (!await recorder.hasPermission()) {
      lastError = 'Mikrofon izni verilmedi. Ayarlardan izin verip tekrar deneyin.';
      notifyListeners();
      return false;
    }

    m.startedAt = DateTime.now();
    m.folderPath = await storage.createMeetingFolder(m);
    m.audioPath = p.join(m.folderPath!, 'toplanti.wav');

    await recorder.start(wavPath: m.audioPath);
    m.phase = MeetingPhase.recording;
    _startClock();
    _listenLevel();

    await _segmentSub?.cancel();
    _segmentSub = transcription.segments.listen((segment) async {
      segment.speakerId ??= await speakers.identifyLive(
        segment: segment,
        participants: m.participants,
      );
      m.segments.add(segment);
      notifyListeners();
    });
    // Beklenmez: model yüklenirken gelen ses servis içinde tamponlanır.
    unawaited(transcription.startLive(
      mode: TranscriptionMode.meeting,
      participants: m.participants,
      audio: recorder.samples,
    ));

    await WakelockPlus.enable();
    await storage.saveMeeting(m);
    notifyListeners();
    return true;
  }

  Future<void> endMeeting() async {
    final m = _meeting;
    if (m == null) return;
    _setBusy('Kayıt kapatılıyor…');

    await recorder.stop();
    _stopClock();
    await _stopLevel();
    m.endedAt = DateTime.now();

    _setBusy('Kalan konuşmalar yazıya dökülüyor…');
    await transcription.stopLive();
    await _segmentSub?.cancel();
    _segmentSub = null;
    m.phase = MeetingPhase.ended;

    _setBusy('Konuşmacılar eşleştiriliyor…');
    final finalSegments = await speakers.assignSpeakers(
      audioPath: m.audioPath!,
      segments: List.of(m.segments),
      participants: m.participants,
    );
    m.segments
      ..clear()
      ..addAll(finalSegments)
      ..sort((a, b) => a.start.compareTo(b.start));

    await storage.saveMeeting(m);
    await storage.writeTranscriptText(m);
    await WakelockPlus.disable();
    _setBusy(null);
  }

  /// Bir konuşma parçasının konuşmacısını elle değiştirir (null = Bilinmeyen).
  Future<void> relabelSegment(Meeting m, String segmentId, String? participantId) async {
    for (final s in m.segments) {
      if (s.id == segmentId) {
        s.speakerId = participantId;
        s.manuallyLabeled = true;
        s.speakerConfidence = null;
      }
    }
    notifyListeners();
    await storage.saveMeeting(m);
    await storage.writeTranscriptText(m);
  }

  /// Kaydedilmiş toplantı sesini seçili modelle baştan yazıya döker.
  /// Model karşılaştırması için metin ayrıca "metin_<model>.txt" olarak saklanır.
  Future<void> retranscribe(Meeting m, {void Function(double)? onProgress}) async {
    final audio = m.audioPath;
    if (audio == null) return;
    final segments = await transcription.transcribeFile(audio, onProgress: onProgress);
    final labeled = await speakers.assignSpeakers(
      audioPath: audio,
      segments: segments,
      participants: m.participants,
    );
    m.segments
      ..clear()
      ..addAll(labeled);
    await storage.saveMeeting(m);
    await storage.writeTranscriptText(m);
    await storage.writeTranscriptText(m, fileName: 'metin_${transcription.modelId}.txt');
    notifyListeners();
  }

  // ------------------------------------------------------------ Karar dikte

  Future<bool> startDecisionDictation() async {
    final m = _meeting;
    if (m == null) return false;
    if (!await recorder.hasPermission()) {
      lastError = 'Mikrofon izni verilmedi.';
      notifyListeners();
      return false;
    }
    m.decisionsAudioPath = p.join(m.folderPath!, 'kararlar.wav');
    await recorder.start(wavPath: m.decisionsAudioPath);
    m.phase = MeetingPhase.dictatingDecisions;
    _startClock();
    _listenLevel();

    await _segmentSub?.cancel();
    // Karar modunda her söz, kişi etiketi olmadan ayrı bir madde olur.
    _segmentSub = transcription.segments.listen((segment) {
      addDecision(segment.text, at: segment.start);
    });
    unawaited(transcription.startLive(
      mode: TranscriptionMode.decisions,
      participants: m.participants,
      audio: recorder.samples,
    ));
    await WakelockPlus.enable();
    notifyListeners();
    return true;
  }

  void addDecision(String text, {Duration? at}) {
    final m = _meeting;
    final trimmed = text.trim();
    if (m == null || trimmed.isEmpty) return;
    m.decisions.add(DecisionItem(id: _uuid.v4(), text: trimmed, at: at ?? elapsed));
    notifyListeners();
  }

  void updateDecision(String id, String text) {
    final m = _meeting;
    if (m == null) return;
    for (final d in m.decisions) {
      if (d.id == id) d.text = text.trim();
    }
    notifyListeners();
  }

  void removeDecision(String id) {
    _meeting?.decisions.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void reorderDecision(int oldIndex, int newIndex) {
    final m = _meeting;
    if (m == null) return;
    if (newIndex > oldIndex) newIndex--;
    m.decisions.insert(newIndex, m.decisions.removeAt(oldIndex));
    notifyListeners();
  }

  /// "Toplantı Kararlarını Bitir". Kopyalama sonucunu mesaj olarak döndürür.
  Future<String?> finishDecisions() async {
    final m = _meeting;
    if (m == null) return null;
    _setBusy('Kayıt kapatılıyor…');
    await recorder.stop();
    _stopClock();
    await _stopLevel();

    _setBusy('Kalan kararlar yazıya dökülüyor…');
    await transcription.stopLive();
    await _segmentSub?.cancel();
    _segmentSub = null;
    return _complete(m);
  }

  /// Karar dikte etmeden tamamla.
  Future<String?> completeWithoutDecisions() async {
    final m = _meeting;
    if (m == null) return null;
    return _complete(m);
  }

  Future<String?> _complete(Meeting m) async {
    _setBusy('Kaydediliyor…');
    m.phase = MeetingPhase.completed;
    completedCount++;
    await storage.saveMeeting(m);
    await storage.writeTranscriptText(m);
    String? message;
    try {
      final exported = await storage.exportMeeting(m);
      if (exported != null) {
        m.exportPath = exported;
        await storage.saveMeeting(m);
        message = 'Kayıtlar seçilen klasöre kopyalandı.';
      }
    } catch (e) {
      message = 'Seçilen klasöre kopyalanamadı; kayıt uygulama içinde duruyor. ($e)';
    }
    await WakelockPlus.disable();
    _setBusy(null);
    return message;
  }

  // -------------------------------------------------------------- Yardımcılar

  void _startClock() {
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  void _stopClock() {
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
  }

  void _listenLevel() {
    _levelSub?.cancel();
    _levelSub = recorder.levels.listen((v) {
      _level = v;
      notifyListeners();
    });
  }

  Future<void> _stopLevel() async {
    await _levelSub?.cancel();
    _levelSub = null;
    _level = 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _segmentSub?.cancel();
    _levelSub?.cancel();
    super.dispose();
  }
}
