/// Türkçe büyük/küçük harf ve ASCII dönüşüm yardımcıları.
///
/// Dart'ın varsayılan toLowerCase/toUpperCase fonksiyonları Türkçe I/İ/ı/i
/// harflerini doğru dönüştürmez; bu yüzden önce bu harfler elle çevrilir.
library;

String trLower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

String trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

const Map<String, String> _asciiMap = {
  'ç': 'c',
  'ğ': 'g',
  'ı': 'i',
  'ö': 'o',
  'ş': 's',
  'ü': 'u',
  'â': 'a',
  'î': 'i',
  'û': 'u',
  'Ç': 'C',
  'Ğ': 'G',
  'İ': 'I',
  'Ö': 'O',
  'Ş': 'S',
  'Ü': 'U',
};

/// Türkçe karakterleri ASCII karşılıklarına çevirir (e-posta, dosya adı için).
String toAscii(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_asciiMap[ch] ?? ch);
  }
  return b.toString();
}
