import '../utils/turkish.dart';

/// Sesle söylenmiş (ve konuşma tanımayla yazıya dökülmüş) bir metinden
/// e-posta adresi çıkarır.
///
/// Örnekler:
///   "ahmet nokta yılmaz et bicen nokta com nokta tr" -> ahmet.yilmaz@bicen.com.tr
///   "Mail adresim ahmet.yılmaz@bicen.com.tr."       -> ahmet.yilmaz@bicen.com.tr
///   "my email john dot doe at gmail dot com"         -> john.doe@gmail.com
///   "ahmet nokta yılmaz" (defaultDomain: bicen.com.tr) -> ahmet.yilmaz@bicen.com.tr
///
/// Ad ile soyad arasında ayırıcı söylenmediyse ("ahmet yılmaz at ...") birden
/// fazla aday döner; arayüz bunları kullanıcıya seçtirir.
class EmailParser {
  EmailParser({String? defaultDomain})
      : defaultDomain = _normalizeDomain(defaultDomain);

  /// Alan adı söylenmezse eklenecek şirket alan adı (ör. bicen.com.tr).
  final String? defaultDomain;

  /// Başta söylenebilecek tetik ifadeleri (uzundan kısaya denenir).
  static const List<String> _triggers = [
    'benim mail adresim',
    'benim e-posta adresim',
    'e-posta adresim',
    'e posta adresim',
    'eposta adresim',
    'mail adresim',
    'mail adresi',
    'my email address',
    'my email',
    'myemail',
    'e-posta',
    'eposta',
    'email',
    'mail',
  ];

  /// Tetikten sonra gelebilecek dolgu kelimeleri.
  static const List<String> _fillers = ['is', 'şu', 'şöyle', ':'];

  /// Sesle söylenen semboller. İki kelimelik ifadeler önce denenir.
  static const Map<String, String> _spoken = {
    'at işareti': '@',
    'et işareti': '@',
    'kuyruklu a': '@',
    'alt çizgi': '_',
    'alt tire': '_',
    'kısa çizgi': '-',
    'at': '@',
    'et': '@',
    'nokta': '.',
    'dot': '.',
    'point': '.',
    'underscore': '_',
    'tire': '-',
    'çizgi': '-',
    'dash': '-',
    'eksi': '-',
  };

  static const Set<String> _symbols = {'@', '.', '_', '-'};

  static final RegExp _valid = RegExp(
    r'^[a-z0-9](?:[a-z0-9._%+-]*[a-z0-9])?@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$',
  );

  static bool isValid(String email) => _valid.hasMatch(email);

  /// En olası adres; bulunamazsa null.
  String? parse(String spoken) {
    final c = candidates(spoken);
    return c.isEmpty ? null : c.first;
  }

  /// Olası adresler, en olasıdan başlayarak.
  List<String> candidates(String spoken) {
    final tokens = _tokens(spoken);
    if (tokens.isEmpty) return const [];

    final atIndex = tokens.indexOf('@');
    final localTokens = atIndex >= 0 ? tokens.sublist(0, atIndex) : tokens;
    final domainTokens =
        atIndex >= 0 ? tokens.sublist(atIndex + 1) : const <String>[];

    String domain;
    if (domainTokens.isNotEmpty) {
      domain = _cleanDomain(domainTokens.join());
    } else if (defaultDomain != null) {
      domain = defaultDomain!;
    } else {
      return const [];
    }

    final results = <String>[];
    for (final sep in const ['.', '', '_']) {
      final local = _cleanLocal(_joinLocal(localTokens, sep));
      final email = '$local@$domain';
      if (isValid(email) && !results.contains(email)) results.add(email);
    }
    return results;
  }

  // ---------------------------------------------------------------------------

  List<String> _tokens(String spoken) {
    var text = trLower(spoken).trim();
    text = text
        .replaceAll(RegExp(r'[,;!?"“”‘’()]'), ' ')
        .replaceAll("'", ' ')
        .replaceAll('@', ' @ ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Cümle sonu noktası.
    while (text.endsWith('.')) {
      text = text.substring(0, text.length - 1).trim();
    }
    text = _stripPrefix(text, _triggers);
    text = _stripPrefix(text, _fillers);

    final raw = text.split(' ').where((t) => t.isNotEmpty).toList();
    final out = <String>[];
    var i = 0;
    while (i < raw.length) {
      if (i + 1 < raw.length) {
        final two = _spoken['${raw[i]} ${raw[i + 1]}'];
        if (two != null) {
          out.add(two);
          i += 2;
          continue;
        }
      }
      out.add(_spoken[raw[i]] ?? raw[i]);
      i++;
    }
    return out;
  }

  static String _stripPrefix(String text, List<String> prefixes) {
    final sorted = [...prefixes]..sort((a, b) => b.length.compareTo(a.length));
    for (final p in sorted) {
      if (text == p) return '';
      if (text.startsWith('$p ') || text.startsWith('$p:')) {
        return text.substring(p.length).replaceFirst(RegExp(r'^[:\s]+'), '');
      }
    }
    return text;
  }

  /// Kelimeleri birleştirir; aralarında söylenmiş sembol yoksa [sep] koyar.
  static String _joinLocal(List<String> tokens, String sep) {
    final b = StringBuffer();
    var prevWasWord = false;
    for (final t in tokens) {
      if (_symbols.contains(t)) {
        b.write(t);
        prevWasWord = false;
      } else {
        if (prevWasWord) b.write(sep);
        b.write(t);
        prevWasWord = true;
      }
    }
    return b.toString();
  }

  static String _cleanLocal(String s) {
    var r = toAscii(s).replaceAll(RegExp(r'[^a-z0-9._%+-]'), '');
    r = r.replaceAll(RegExp(r'\.{2,}'), '.');
    return r.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  }

  static String _cleanDomain(String s) {
    var r = toAscii(s).replaceAll(RegExp(r'[^a-z0-9.-]'), '');
    r = r.replaceAll(RegExp(r'\.{2,}'), '.');
    return r.replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
  }

  static String? _normalizeDomain(String? d) {
    if (d == null) return null;
    final cleaned = _cleanDomain(trLower(d.trim()).replaceAll('@', ''));
    return cleaned.isEmpty ? null : cleaned;
  }
}
