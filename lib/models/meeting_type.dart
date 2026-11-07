/// Toplantının türü. Recco'daki "kayıt bağlamını tanıma" fikrinin karşılığı:
/// tür, Faz 2'de özetin ve karar çıkarmanın neye odaklanacağını belirler.
/// Otomatik tahmin yerine hazırlıkta seçilir (yanlış tahmin riski yok).
enum MeetingType {
  general(
    'Genel toplantı',
    'Ekip toplantısı, değerlendirme',
    'Alınan kararlar, görev dağılımı ve açık kalan konular',
  ),
  status(
    'Proje / durum toplantısı',
    'İlerleme, engeller, sonraki adımlar',
    'Her işin durumu, engeller, tarihler ve sorumlular',
  ),
  oneOnOne(
    'Birebir görüşme',
    'Yönetici – çalışan, değerlendirme',
    'Konuşulan konular, verilen sözler ve takip edilecekler',
  ),
  client(
    'Tedarikçi / müşteri görüşmesi',
    'Fiyat, şartlar, teklif',
    'Rakamlar, şartlar, karşı tarafın talepleri ve verilen taahhütler',
  ),
  training(
    'Eğitim / sunum',
    'Bilgilendirme, eğitim',
    'Ana kavramlar, önemli noktalar ve sorulan sorular',
  );

  const MeetingType(this.label, this.hint, this.focus);

  /// Ekranda görünen ad.
  final String label;

  /// Seçim listesinde kısa açıklama.
  final String hint;

  /// Özet ve karar çıkarma bu türde neye odaklanmalı (Faz 2 şablonu).
  final String focus;

  static MeetingType fromName(Object? name) =>
      MeetingType.values.asNameMap()[name] ?? MeetingType.general;
}
