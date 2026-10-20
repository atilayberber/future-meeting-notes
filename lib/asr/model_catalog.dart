/// Cihazda çalışacak konuşma tanıma modelleri.
///
/// Dosyalar sherpa-onnx'in yayımladığı int8 Whisper modelleridir. Yalnızca
/// ilk kurulumda indirilir; sonrasında konuşma tanıma tamamen çevrimdışıdır,
/// hiçbir ses cihaz dışına gönderilmez.
class AsrModel {
  const AsrModel({
    required this.id,
    required this.title,
    required this.description,
    required this.approxSize,
    required this.hfName,
  });

  final String id;
  final String title;
  final String description;
  final String approxSize;

  /// Hugging Face'teki ad: csukuangfj/sherpa-onnx-whisper-<hfName>
  final String hfName;

  String _url(String file) =>
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-$hfName/resolve/main/$file';

  String get encoderFile => '$hfName-encoder.int8.onnx';
  String get decoderFile => '$hfName-decoder.int8.onnx';
  String get tokensFile => '$hfName-tokens.txt';

  /// Dosya adı → indirme adresi
  Map<String, String> get files => {
        encoderFile: _url(encoderFile),
        decoderFile: _url(decoderFile),
        tokensFile: _url(tokensFile),
      };
}

const String kVadFile = 'silero_vad.onnx';
const String kVadUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';

const List<AsrModel> kAsrModels = [
  AsrModel(
    id: 'whisper-small',
    title: 'Whisper Small',
    description: 'Hızlı. Orta seviye cihazlarda canlıya yakın çalışır; Türkçe doğruluğu orta.',
    approxSize: '~400 MB',
    hfName: 'small',
  ),
  AsrModel(
    id: 'whisper-medium',
    title: 'Whisper Medium',
    description: 'Daha doğru, belirgin şekilde daha yavaş. Metin toplantının gerisinde kalabilir.',
    approxSize: '~1 GB',
    hfName: 'medium',
  ),
  AsrModel(
    id: 'whisper-turbo',
    title: 'Whisper Large-v3 Turbo',
    description: 'En iyi Türkçe doğruluğu. Güçlü cihaz ister (en az 6 GB RAM önerilir).',
    approxSize: '~1 GB',
    hfName: 'turbo',
  ),
];

const String kDefaultAsrModelId = 'whisper-small';

AsrModel asrModelById(String? id) =>
    kAsrModels.firstWhere((m) => m.id == id, orElse: () => kAsrModels.first);
