import 'package:flutter_test/flutter_test.dart';
import 'package:future_meeting_notes/services/email_parser.dart';

void main() {
  group('EmailParser', () {
    final p = EmailParser();

    test('Türkçe sesli söyleniş', () {
      expect(p.parse('ahmet nokta yılmaz et bicen nokta com nokta tr'),
          'ahmet.yilmaz@bicen.com.tr');
    });

    test('Whisper hazır adres yazdıysa ve sonda nokta varsa', () {
      expect(p.parse('Mail adresim ahmet.yılmaz@bicen.com.tr.'),
          'ahmet.yilmaz@bicen.com.tr');
    });

    test('İngilizce söyleniş ve dolgu kelimesi', () {
      expect(p.parse('my email is john dot doe at gmail dot com'),
          'john.doe@gmail.com');
    });

    test('Varsayılan şirket alan adı eklenir', () {
      final withDomain = EmailParser(defaultDomain: '@bicen.com.tr');
      expect(withDomain.parse('Şükrü nokta Öztürk'), 'sukru.ozturk@bicen.com.tr');
      expect(withDomain.parse('ahmet at'), 'ahmet@bicen.com.tr');
    });

    test('Alt çizgi, tire ve kuyruklu a', () {
      expect(p.parse('ayşe alt çizgi kaya at bicen nokta com nokta tr'),
          'ayse_kaya@bicen.com.tr');
      expect(p.parse('E-posta adresim: mehmet tire can et bicen nokta com nokta tr'),
          'mehmet-can@bicen.com.tr');
      expect(p.parse('veli kuyruklu a firma nokta com'), 'veli@firma.com');
    });

    test('Büyük İ harfi doğru küçülür', () {
      expect(p.parse('İLKER at gmail nokta com'), 'ilker@gmail.com');
    });

    test('Ayırıcı söylenmediyse birden fazla aday döner', () {
      expect(p.candidates('ahmet yılmaz at bicen nokta com'), [
        'ahmet.yilmaz@bicen.com',
        'ahmetyilmaz@bicen.com',
        'ahmet_yilmaz@bicen.com',
      ]);
    });

    test('Adres yoksa null', () {
      expect(p.parse('merhaba'), isNull);
    });
  });
}
