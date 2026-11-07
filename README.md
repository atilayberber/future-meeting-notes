# Future Meeting Notes — Faz 1e (Recco'dan alınan özellikler)

Yüz yüze toplantıları kişi bazında yazıya döken mobil uygulama. Flutter, iOS + Android.
Tüm işlem cihaz üzerinde yapılır.

## Bu sürümde ne var

| Bölüm | Durum |
|---|---|
| Hazırlık, katılımcı ekleme, ses örneği (~20 sn) | ✅ |
| Ad, soyad, e-posta alanlarını **sesle** doldurma (mikrofon düğmesi) | ✅ Faz 1b |
| Toplantı kaydı (16 kHz mono WAV) + **canlı konuşma metni** (Whisper, cihazda) | ✅ Faz 1b |
| Hiçbir konuşma atlanmaz: model yavaşsa metin geride kalır, toplantı bitince tamamlanır | ✅ Faz 1b |
| Whisper'ın Türkçe "Altyazı M.K." gibi uydurmalarının temizlenmesi | ✅ Faz 1b |
| Karar dikte: her söz ayrı madde (kişi etiketi yok) | ✅ Faz 1b |
| Kaydı seçilen modelle **yeniden metne dökme** (model karşılaştırması) | ✅ Faz 1b |
| Toplantı türü (genel, durum, birebir, tedarikçi, eğitim) | ✅ Faz 1e |
| Kayıt sırasında tek dokunuşla işaret: Önemli / Karar / Görev / Soru / Not | ✅ Faz 1e |
| Satıra dokununca kaydı o andan dinleme, çalan satır vurgusu, 1x/1.5x/2x | ✅ Faz 1e |
| Metni elle düzeltme (satırı basılı tut) | ✅ Faz 1e |
| Toplantı içinde ve **tüm toplantılarda** arama ("kim ne dedi"), kişiye göre süzme | ✅ Faz 1e |
| Kim ne kadar konuştu (süre, pay, söz sayısı) | ✅ Faz 1e |
| Paylaşma: toplantı notu (.md), kararlar, ses kaydı (.wav) | ✅ Faz 1e |
| Takip e-postası: katılımcılara kararlar + işaretlenenler (e-posta uygulamasında açılır) | ✅ Faz 1e |
| Faz 2 zemini: türe göre komut şablonu, JSON sonuç modeli, dayanıklı ayrıştırıcı | ✅ Faz 1e |
| Konuşmacı etiketi | ⏳ Faz 1c — şimdilik etikete dokunarak elle |
| Özet, konuşmadan karar/görev çıkarma, karşılaştırma | ⏳ Faz 2 — özet motoru seçimi bekleniyor |

## Recco'dan neler alındı, neler alınmadı

[Recco](https://apps.apple.com/us/app/recco-ai-meeting-note-taker/id6757509070) (Next Pixel
Limited) incelendi. Kapalı kaynak; ses buluta gönderiliyor ve dakika başı ücretlendiriliyor.

| Recco özelliği | FMN'deki karşılığı |
|---|---|
| Kayıt bağlamını otomatik tanıma | Toplantı türü hazırlıkta **seçilir** (yanlış tahmin yok); Faz 2 komutunu belirler |
| Kayıt sırasında not alma | Tek dokunuşla işaret + isteğe bağlı not; metinde ve kararlarda o anki cümleyle görünür |
| Ses çubuğu, transkripti düzenleme | Satıra dokun → o andan çal; basılı tut → düzelt |
| Global arama | Cihazda, Türkçe karakter duyarsız, konuşmacı adıyla da arar |
| Transkript dışa aktarma (kullanıcılar sesi de istiyor) | Not (.md) + ses (.wav) paylaşma |
| Takip e-postası taslağı | Yapay zekâsız da çalışır: dikte edilen kararlar + işaretlenen anlar |
| AI özet, aksiyon maddeleri, "notlarınla sohbet" | Faz 2 — şablon ve sonuç yapısı hazır (`lib/intelligence/`) |
| **Alınmadı:** buluta ses gönderme, hesap/abonelik, reklam takibi | KVKK ve cihaz içi ilkesi gereği |

## Konuşma tanıma nasıl çalışıyor

```
Mikrofon (PCM 16 kHz) ──┬──► toplanti.wav
                        └──► [ayrı isolate] Silero VAD ─► konuşma parçası ─► Whisper ─► metin
```

- VAD konuşmayı sessizliklerden böler (en fazla 15 sn'lik parçalar). Her parça Whisper'a
  `language: tr` ile verilir.
- Motor ayrı bir isolate'te çalışır; arayüz donmaz. Gelen ses kuyrukta bekler, hiçbir
  parça atlanmaz. Ekranda "Metin X sn geride" görünürse model cihaz için ağır demektir.
- Model ilk kullanımda **Ayarlar → Konuşma tanıma modeli**'nden bir kez indirilir
  (Hugging Face / GitHub). Sonrasında internet gerekmez; ses cihaz dışına çıkmaz.

| Model | Boyut | Not |
|---|---|---|
| Whisper Small | ~400 MB | Varsayılan. Hızlı, Türkçe doğruluğu orta |
| Whisper Medium | ~1 GB | Daha doğru, yavaş |
| Whisper Large-v3 Turbo | ~1 GB | En iyi Türkçe; 6 GB+ RAM önerilir |

### Model karşılaştırma (Faz 1d hazırlığı)

1. Uygulamayla gerçek bir toplantı kaydedin.
2. Ayarlar'dan başka bir model indirip seçin.
3. Toplantıyı açın → **Bilgi** → **Kaydı yeniden metne dök**.
4. Toplantı klasöründe her model için `metin_<model>.txt` oluşur; yan yana karşılaştırın.

## Kurulum (Windows)

Gerekenler: Flutter SDK (3.27 veya üstü), Android Studio (Android SDK için), bir Android telefon.

```powershell
cd future_meeting_notes
powershell -ExecutionPolicy Bypass -File kurulum.ps1
flutter run
```

`kurulum.ps1` şunları yapar: `flutter create` ile android/ios klasörlerini oluşturur
(mevcut kod korunur), mikrofon ve internet (model indirme) izinlerini ekler, Android
minSdk'yı 24, iOS'u 13.0 yapar, paketleri indirir ve testleri çalıştırır.
Faz 1a'yı kurduysanız betiği yeniden çalıştırmanız yeterli.

İlk açılışta: **Ayarlar → Konuşma tanıma modeli → Whisper Small → İndir** (Wi-Fi ile).

**iOS:** Derleme için Mac + Xcode gerekir; Windows'tan iOS'a derlenemez. Kod aynıdır,
Mac'te `flutter run` yeterli.

## Klasör yapısı

```
lib/
  main.dart                     Servislerin bağlandığı yer
  asr/
    asr_worker.dart             Isolate: VAD + Whisper (sherpa-onnx)
    sherpa_transcription_service.dart  Canlı / klip / dosya yazıya dökme
    model_catalog.dart, model_manager.dart  Model listesi, indirme
    text_cleaner.dart           Whisper uydurmalarını temizleme
  intelligence/                 Faz 2 zemini: komut şablonu, sonuç modeli, ayrıştırıcı, motor arayüzü
  models/                       Meeting, MeetingType, MeetingMark, Participant, TranscriptSegment, DecisionItem
  state/meeting_controller.dart Akışın durum makinesi
  services/
    audio_recorder_service.dart Mikrofon kaydı (16 kHz mono WAV)
    transcription_service.dart  Konuşma tanıma arayüzü
    speaker_service.dart        Konuşmacı tanıma arayüzü + yer tutucu ← Faz 1c
    email_parser.dart           Sesle söylenen e-postayı ayrıştırma
    storage_service.dart        Cihazda saklama ve klasöre kopyalama
    meeting_search.dart         Toplantı içi / tüm toplantılarda arama
    meeting_report.dart         Konuşma payları, Markdown notu, takip e-postası
    meeting_player.dart         Kaydı metinle eşzamanlı çalma
    settings_service.dart
  screens/                      home, search, preparation, enrollment, meeting, decisions, result, settings
test/  email_parser_test.dart, text_cleaner_test.dart, recco_features_test.dart
```

## Kayıtlar nerede

```
<Uygulama belgeleri>/FutureMeetingNotes/toplantilar/2026-10-19_22-29_Haftalik_Toplanti/
    toplanti.wav   toplantı kaydı
    kararlar.wav   karar dikte kaydı
    toplanti.json  katılımcılar, metin, kararlar
    toplanti_metni.txt  okunabilir döküm: [02:15] Ahmet Yılmaz: ...
    toplanti_notlari.md paylaşılan toplantı notu (paylaşınca oluşur)
    metin_<model>.txt   yeniden metne dökme sonuçları
<Uygulama belgeleri>/FutureMeetingNotes/ses_profilleri/<katılımcı-id>.wav
```

Ses örnekleri bilerek ayrı klasörde: KVKK açısından biyometrik veri sayılıyor,
saklama ve silme kuralları ileride bu klasöre uygulanacak.

## Sıradaki: Faz 1c — konuşmacı tanıma

1. Hazırlıktaki ses örneğinden ses izi çıkarma (sherpa-onnx speaker embedding).
2. Canlı ön etiket; toplantı sonunda tüm kaydı kümeleyip kesin etiket.
3. "Bilinmeyen Konuşmacı" eşiği ve elle düzeltmelerle ölçüm.
