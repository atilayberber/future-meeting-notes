import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'asr/model_manager.dart';
import 'asr/sherpa_transcription_service.dart';
import 'services/audio_recorder_service.dart';
import 'services/settings_service.dart';
import 'services/speaker_service.dart';
import 'services/storage_service.dart';
import 'services/transcription_service.dart';
import 'state/meeting_controller.dart';

/// Açılış: önce hemen bir ekran çizilir, servisler sonra hazırlanır.
/// Herhangi bir adım takılır ya da hata verirse, hangi adım olduğu ekranda
/// gösterilir (açılış ekranında sessizce kalmak yerine).
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      StartupLog.add('Flutter hatası: ${details.exceptionAsString()}');
    };
    // Release modda çizim hatası gri ekran yerine okunabilir metin olarak görünsün.
    ErrorWidget.builder = (details) => Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text('Ekran hatası:\n${details.exceptionAsString()}\n\n${details.stack ?? ''}',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ),
        );
    runApp(const Bootstrap());
  }, (error, stack) {
    StartupLog.add('Beklenmeyen hata: $error\n${_firstLines(stack)}');
  });
}

String _firstLines(StackTrace s, [int n = 6]) => s.toString().split('\n').take(n).join('\n');

/// Açılış sırasında olanların kaydı (hata ekranında gösterilir).
class StartupLog {
  static final ValueNotifier<List<String>> lines = ValueNotifier(const []);
  static void add(String line) {
    debugPrint('[FMN] $line');
    lines.value = [...lines.value, line];
  }
}

class _Services {
  _Services(this.settings, this.storage, this.recorder, this.models, this.transcription,
      this.speakers);
  final SettingsService settings;
  final StorageService storage;
  final AudioRecorderService recorder;
  final ModelManager models;
  final TranscriptionService transcription;
  final SpeakerIdentificationService speakers;
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  _Services? _services;
  String? _failedStep;
  Object? _error;
  String _step = 'Başlatılıyor';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<T> _run<T>(String step, Future<T> Function() f) async {
    if (mounted) setState(() => _step = step);
    StartupLog.add('→ $step');
    final r = await f().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('$step 15 sn içinde tamamlanamadı'),
    );
    StartupLog.add('✓ $step');
    return r;
  }

  Future<void> _init() async {
    var current = '';
    try {
      final settings = SettingsService();
      current = 'Ayarlar yükleniyor';
      await _run(current, settings.load);

      current = 'Depolama hazırlanıyor';
      final storage = StorageService(settings);
      await _run(current, () => storage.meetingsDir());

      current = 'Mikrofon servisi hazırlanıyor';
      final recorder = await _run(current, () async => AudioRecorderService());

      current = 'Konuşma tanıma modelleri kontrol ediliyor';
      final models = ModelManager(settings);
      await _run(current, models.refresh);

      final transcription = SherpaTranscriptionService(models: models);
      final speakers = PlaceholderSpeakerService();

      if (!mounted) return;
      setState(() {
        _services = _Services(settings, storage, recorder, models, transcription, speakers);
      });
    } catch (e, s) {
      StartupLog.add('✗ $current: $e\n${_firstLines(s)}');
      if (!mounted) return;
      setState(() {
        _failedStep = current;
        _error = e;
      });
    }
  }

  void _retry() {
    setState(() {
      _failedStep = null;
      _error = null;
      _step = 'Başlatılıyor';
    });
    _init();
  }

  @override
  Widget build(BuildContext context) {
    final s = _services;
    if (s != null) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: s.settings),
          ChangeNotifierProvider<ModelManager>.value(value: s.models),
          Provider<StorageService>.value(value: s.storage),
          Provider<AudioRecorderService>.value(value: s.recorder),
          Provider<TranscriptionService>.value(value: s.transcription),
          ChangeNotifierProvider<MeetingController>(
            create: (_) => MeetingController(
              storage: s.storage,
              recorder: s.recorder,
              transcription: s.transcription,
              speakers: s.speakers,
            ),
          ),
        ],
        child: const FutureMeetingNotesApp(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1F5F6B)),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failedStep == null ? _loading() : _failure(),
          ),
        ),
      ),
    );
  }

  Widget _loading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_step),
          ],
        ),
      );

  Widget _failure() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Uygulama başlatılamadı',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Adım: $_failedStep'),
          const SizedBox(height: 4),
          Text('Hata: $_error', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          const Text('Ayrıntı (ekran görüntüsünü gönderin):'),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: StartupLog.lines,
              builder: (_, lines, __) => SingleChildScrollView(
                child: SelectableText(lines.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ),
          FilledButton(onPressed: _retry, child: const Text('Tekrar dene')),
        ],
      );
}
