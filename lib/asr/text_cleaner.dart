import '../utils/turkish.dart';

/// Whisper'ın sessizlik veya gürültüde "uydurduğu" bilinen Türkçe kalıpları
/// ve tekrar döngülerini temizler.
///
/// Whisper YouTube altyazılarıyla eğitildiği için Türkçede sessiz bölümlerde
/// "Altyazı M.K." gibi satırlar üretebilir. Bunlar gerçek konuşma değildir.
class TextCleaner {
  static const List<String> _hallucinations = [
    'altyazı m.k',
    'altyazı mk',
    'altyazı m k',
    'izlediğiniz için teşekkür ederim',
    'izlediğiniz için teşekkürler',
    'kanalıma abone olmayı unutmayın', // uzun kalıp kısa olandan önce
    'abone olmayı unutmayın',
    'bir sonraki videoda görüşmek üzere',
    'videoyu beğenmeyi unutmayın',
    'altyazılar amara.org topluluğu tarafından yapılmıştır',
  ];

  /// Temizlenmiş metni döndürür; parçanın tamamı uydurmaysa null.
  static String? clean(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;

    // Bilinen kalıpları cümle içinden de çıkar.
    for (final h in _hallucinations) {
      text = _removeIgnoringCase(text, h);
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'^[\s.,;:!?\-–]+'), '').trim();

    if (!RegExp(r'[0-9A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(text)) return null;

    return _collapseRepeats(text);
  }

  static String _removeIgnoringCase(String text, String phrase) {
    final lower = trLower(text);
    final b = StringBuffer();
    var i = 0;
    while (true) {
      final idx = lower.indexOf(phrase, i);
      if (idx < 0) break;
      b.write(text.substring(i, idx));
      var end = idx + phrase.length;
      // Kalıbın arkasındaki noktalamayı da al.
      while (end < text.length && '.!,'.contains(text[end])) {
        end++;
      }
      i = end;
    }
    b.write(text.substring(i));
    return b.toString();
  }

  /// "Tamam. Tamam. Tamam. Tamam." gibi art arda tekrarları en fazla 2'ye indirir
  /// (Whisper'ın döngüye girmesi).
  static String _collapseRepeats(String text) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final out = <String>[];
    var run = 0;
    for (final s in sentences) {
      if (out.isNotEmpty && trLower(out.last) == trLower(s)) {
        run++;
        if (run >= 2) continue; // en fazla 2 kez
      } else {
        run = 0;
      }
      out.add(s);
    }
    return out.join(' ');
  }
}
