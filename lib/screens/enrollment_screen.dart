import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/participant.dart';
import '../services/audio_recorder_service.dart';
import '../services/email_parser.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/transcription_service.dart';
import '../utils/turkish.dart';
import '../widgets/common.dart';

/// Kayıt sırasında okunacak metin (~20 saniye). Farklı ses türlerini
/// içerecek şekilde seçildi; ses izi bu kayıttan çıkarılacak (Faz 1c).
const String kEnrollmentText =
    'Bugün toplantıya katılıyorum ve sesimi uygulamaya tanıtıyorum. '
    'Hafta sonu sahilde yürüyüş yaptık, ardından çay içip güneşin batışını izledik. '
    'Yeni projeler için fikirlerimizi paylaşmak, kararları birlikte almak ve işleri '
    'zamanında tamamlamak bizim için önemli. Sayıları da söyleyeyim: bir, iki, üç, '
    'dört, beş, altı, yedi, sekiz, dokuz, on.';

const int kMinSampleSeconds = 15;
const int kMaxSampleSeconds = 40;

/// Tek bir katılımcının kaydı: Ad → Soyad → E-posta → Ses örneği.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final String _id = const Uuid().v4();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _emailRaw = TextEditingController();

  int _step = 0;
  List<String> _emailCandidates = const [];
  String? _email;

  // Ses örneği
  bool _recording = false;
  int _seconds = 0;
  String? _samplePath;
  double _level = 0;
  Timer? _timer;
  StreamSubscription<double>? _levelSub;

  // Sesle alan doldurma (ad, soyad, e-posta)
  int? _listeningField; // 0: ad, 1: soyad, 2: e-posta
  int? _transcribingField;
  final List<Float32List> _clipChunks = [];
  StreamSubscription<Float32List>? _clipSub;
  Timer? _clipTimer;

  late final AudioRecorderService _recorder = context.read<AudioRecorderService>();

  @override
  void dispose() {
    _timer?.cancel();
    _clipTimer?.cancel();
    _clipSub?.cancel();
    _levelSub?.cancel();
    if (_recording || _listeningField != null) _recorder.stop();
    _first.dispose();
    _last.dispose();
    _emailRaw.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ E-posta

  void _onEmailChanged(String text) {
    final domain = context.read<SettingsService>().companyDomain;
    final parser = EmailParser(defaultDomain: domain.isEmpty ? null : domain);
    final list = parser.candidates(text);
    setState(() {
      _emailCandidates = list;
      _email = list.isEmpty ? null : (list.contains(_email) ? _email : list.first);
    });
  }

  // ------------------------------------------------------------- Ses örneği

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (_listeningField != null) return;
    final storage = context.read<StorageService>();
    if (!await _recorder.hasPermission()) {
      _snack('Mikrofon izni verilmedi.');
      return;
    }
    final dir = await storage.voiceProfilesDir();
    if (!mounted) return;
    final path = p.join(dir.path, '$_id.wav');
    await _recorder.start(wavPath: path);
    _levelSub = _recorder.levels.listen((v) {
      if (mounted) setState(() => _level = v);
    });
    setState(() {
      _recording = true;
      _seconds = 0;
      _samplePath = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      if (_seconds >= kMaxSampleSeconds) _stopRecording();
    });
    // Geçici yol; kayıt bitince atanır.
    _pendingPath = path;
  }

  String? _pendingPath;

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _levelSub?.cancel();
    await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _level = 0;
      _samplePath = _pendingPath;
    });
  }

  // ------------------------------------------------- Sesle alan doldurma

  Future<void> _toggleClip(int field) async {
    if (_listeningField == field) {
      await _finishClip();
      return;
    }
    if (_recording || _listeningField != null || _transcribingField != null) return;
    if (!await _recorder.hasPermission()) {
      _snack('Mikrofon izni verilmedi.');
      return;
    }
    _clipChunks.clear();
    await _recorder.start();
    _clipSub = _recorder.samples.listen(_clipChunks.add);
    _levelSub = _recorder.levels.listen((v) {
      if (mounted) setState(() => _level = v);
    });
    if (!mounted) return;
    setState(() => _listeningField = field);
    // Söyleyip durdurmayı unutursa 12 sn sonra kendiliğinden biter.
    _clipTimer = Timer(const Duration(seconds: 12), _finishClip);
  }

  Future<void> _finishClip() async {
    final field = _listeningField;
    if (field == null) return;
    _clipTimer?.cancel();
    final transcription = context.read<TranscriptionService>();
    await _recorder.stop();
    await _clipSub?.cancel();
    await _levelSub?.cancel();
    if (!mounted) return;
    setState(() {
      _listeningField = null;
      _transcribingField = field;
      _level = 0;
    });

    final total = _clipChunks.fold<int>(0, (n, c) => n + c.length);
    final samples = Float32List(total);
    var offset = 0;
    for (final c in _clipChunks) {
      samples.setAll(offset, c);
      offset += c.length;
    }
    _clipChunks.clear();

    final text = await transcription.transcribeClip(samples);
    if (!mounted) return;
    setState(() => _transcribingField = null);
    if (text.isEmpty) {
      _snack(transcription.problem.value ?? 'Anlaşılamadı; tekrar söyleyin veya yazın.');
      return;
    }
    switch (field) {
      case 0:
        _first.text = _nameCase(text);
      case 1:
        _last.text = _nameCase(text);
      default:
        _emailRaw.text = text;
        _onEmailChanged(text);
    }
    setState(() {});
  }

  /// "ahmet." → "Ahmet", "ali rıza" → "Ali Rıza"
  static String _nameCase(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[.,!?;:"]'), ' ').trim();
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => trUpper(w.substring(0, 1)) + trLower(w.substring(1)))
        .join(' ');
  }

  // ------------------------------------------------------------------ Akış

  bool get _canContinue => switch (_step) {
        0 => _first.text.trim().isNotEmpty,
        1 => _last.text.trim().isNotEmpty,
        2 => _email != null,
        _ => !_recording && _samplePath != null && _seconds >= kMinSampleSeconds,
      };

  void _next() {
    if (!_canContinue) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _save(withSample: true);
    }
  }

  void _save({required bool withSample}) {
    Navigator.of(context).pop(Participant(
      id: _id,
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      email: _email!,
      voiceSamplePath: withSample ? _samplePath : null,
      voiceSampleSeconds: withSample ? _seconds : 0,
    ));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------------ Arayüz

  @override
  Widget build(BuildContext context) {
    final domain = context.watch<SettingsService>().companyDomain;
    return Scaffold(
      appBar: AppBar(title: const Text('Katılımcı Ekle')),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (i) {
          if (i < _step && !_recording) setState(() => _step = i);
        },
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: _canContinue ? _next : null,
                child: Text(_step < 3 ? 'Devam' : 'Katılımcıyı Kaydet'),
              ),
              const SizedBox(width: 8),
              if (_step == 3 && _email != null && !_recording)
                TextButton(
                  onPressed: () => _save(withSample: false),
                  child: const Text('Ses örneği olmadan kaydet'),
                ),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('Ad'),
            subtitle: _step > 0 ? Text(_first.text) : null,
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: _VoiceTextField(
              controller: _first,
              label: 'Adınızı söyleyin',
              onChanged: (_) => setState(() {}),
              listening: _listeningField == 0,
              transcribing: _transcribingField == 0,
              onMic: () => _toggleClip(0),
            ),
          ),
          Step(
            title: const Text('Soyad'),
            subtitle: _step > 1 ? Text(_last.text) : null,
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: _VoiceTextField(
              controller: _last,
              label: 'Soyadınızı söyleyin',
              onChanged: (_) => setState(() {}),
              listening: _listeningField == 1,
              transcribing: _transcribingField == 1,
              onMic: () => _toggleClip(1),
            ),
          ),
          Step(
            title: const Text('E-posta'),
            subtitle: _step > 2 && _email != null ? Text(_email!) : null,
            isActive: _step >= 2,
            state: _step > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VoiceTextField(
                  controller: _emailRaw,
                  label: 'E-posta adresinizi söyleyin',
                  hint: '"ahmet nokta yılmaz et bicen nokta com nokta tr"',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _onEmailChanged,
                  listening: _listeningField == 2,
                  transcribing: _transcribingField == 2,
                  onMic: () => _toggleClip(2),
                ),
                if (_listeningField != null) ...[
                  const SizedBox(height: 8),
                  LevelMeter(level: _level),
                ],
                const SizedBox(height: 8),
                if (domain.isNotEmpty)
                  Text('Alan adı söylenmezse @$domain eklenir.',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_emailCandidates.length > 1)
                  const Text('Hangisi doğru?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final e in _emailCandidates)
                      ChoiceChip(
                        label: Text(e),
                        selected: e == _email,
                        onSelected: (_) => setState(() => _email = e),
                      ),
                  ],
                ),
                if (_emailRaw.text.isNotEmpty && _emailCandidates.isEmpty)
                  Text('Geçerli bir adres algılanamadı.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          Step(
            title: const Text('Ses örneği'),
            isActive: _step >= 3,
            content: _sampleStep(context),
          ),
        ],
      ),
    );
  }

  Widget _sampleStep(BuildContext context) {
    final theme = Theme.of(context);
    final enough = _seconds >= kMinSampleSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kayda basın ve aşağıdaki metni normal sesinizle okuyun.'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(kEnrollmentText,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _toggleRecording,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording
                  ? 'Durdur'
                  : (_samplePath == null ? 'Kaydı Başlat' : 'Yeniden Kaydet')),
            ),
            const SizedBox(width: 16),
            if (_recording) const RecordingDot(),
            const SizedBox(width: 8),
            Text('$_seconds sn', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        if (_recording) LevelMeter(level: _level),
        const SizedBox(height: 8),
        if (!_recording && _samplePath != null)
          Text(
            enough
                ? 'Ses örneği hazır.'
                : 'En az $kMinSampleSeconds saniye gerekli; lütfen metni baştan okuyun.',
            style: TextStyle(color: enough ? Colors.green : theme.colorScheme.error),
          ),
      ],
    );
  }
}

/// Metin alanı + mikrofon düğmesi. Mikrofona dokunup söyleyin, tekrar dokunun
/// (veya 12 sn bekleyin); söylenen cihaz üzerinde yazıya dökülür.
class _VoiceTextField extends StatelessWidget {
  const _VoiceTextField({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.onMic,
    required this.listening,
    required this.transcribing,
    this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  final VoidCallback onMic;
  final bool listening;
  final bool transcribing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget suffix;
    if (transcribing) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      suffix = IconButton(
        tooltip: listening ? 'Bitir' : 'Sesle doldur',
        onPressed: onMic,
        icon: Icon(listening ? Icons.stop_circle : Icons.mic,
            color: listening ? scheme.error : scheme.primary),
      );
    }
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization:
          keyboardType == null ? TextCapitalization.words : TextCapitalization.none,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: listening ? 'Dinleniyor… bitince durdurun' : label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
    );
  }
}
