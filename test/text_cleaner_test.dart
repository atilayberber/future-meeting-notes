import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_meeting_notes/asr/asr_worker.dart';
import 'package:future_meeting_notes/asr/text_cleaner.dart';
import 'package:future_meeting_notes/services/audio_recorder_service.dart';

void main() {
  group('TextCleaner', () {
    test('Bilinen Whisper uydurmaları atılır', () {
      expect(TextCleaner.clean('Altyazı M.K.'), isNull);
      expect(TextCleaner.clean('İzlediğiniz için teşekkürler.'), isNull);
      expect(TextCleaner.clean('Kanalıma abone olmayı unutmayın!'), isNull);
      expect(TextCleaner.clean('...'), isNull);
    });

    test('Gerçek konuşma korunur, eklenen uydurma çıkarılır', () {
      expect(TextCleaner.clean('  Bütçeyi onaylıyoruz.  Altyazı M.K.'), 'Bütçeyi onaylıyoruz.');
      expect(TextCleaner.clean('Peki, yarın konuşalım.'), 'Peki, yarın konuşalım.');
    });

    test('Tekrar döngüsü kısaltılır', () {
      expect(TextCleaner.clean('Tamam. Tamam. Tamam. Tamam.'), 'Tamam. Tamam.');
    });
  });

  group('WAV', () {
    test('Başlık 16 kHz mono 16-bit', () {
      final h = ByteData.sublistView(wavHeader(32000));
      expect(String.fromCharCodes(wavHeader(0).sublist(0, 4)), 'RIFF');
      expect(h.getUint32(4, Endian.little), 36 + 32000);
      expect(h.getUint32(24, Endian.little), 16000);
      expect(h.getUint16(22, Endian.little), 1);
      expect(h.getUint16(34, Endian.little), 16);
      expect(h.getUint32(40, Endian.little), 32000);
    });

    test('PCM16 → float dönüşümü', () {
      final pcm = ByteData(6)
        ..setInt16(0, 0, Endian.little)
        ..setInt16(2, 16384, Endian.little)
        ..setInt16(4, -32768, Endian.little);
      final f = pcm16ToFloat32(pcm.buffer.asUint8List());
      expect(f, [0.0, 0.5, -1.0]);
    });
  });
}
