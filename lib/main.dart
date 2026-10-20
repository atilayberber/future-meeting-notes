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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.load();
  final storage = StorageService(settings);
  final recorder = AudioRecorderService();
  final models = ModelManager(settings);
  await models.refresh();

  // Faz 1b: cihaz üzerinde Whisper (sherpa-onnx).
  final TranscriptionService transcription = SherpaTranscriptionService(models: models);
  // Faz 1c'de gerçek konuşmacı tanıma ile değişecek.
  final SpeakerIdentificationService speakers = PlaceholderSpeakerService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<ModelManager>.value(value: models),
        Provider<StorageService>.value(value: storage),
        Provider<AudioRecorderService>.value(value: recorder),
        Provider<TranscriptionService>.value(value: transcription),
        ChangeNotifierProvider<MeetingController>(
          create: (_) => MeetingController(
            storage: storage,
            recorder: recorder,
            transcription: transcription,
            speakers: speakers,
          ),
        ),
      ],
      child: const FutureMeetingNotesApp(),
    ),
  );
}
