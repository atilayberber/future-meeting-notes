# Future Meeting Notes — Faz 1b (cihaz üzerinde konuşma tanıma)

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
| Konuşmacı etiketi | ⏳ Faz 1c — şimdilik etikete dokunarak elle |
| Özet, karar çıkarma, karşılaştırma, e-posta | ⏳ Faz 2 |

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
  models/                       Meeting, Participant, TranscriptSegment, DecisionItem
  state/meeting_controller.dart Akışın durum makinesi
  services/
    audio_recorder_service.dart Mikrofon kaydı (16 kHz mono WAV)
    transcription_service.dart  Konuşma tanıma arayüzü
    speaker_service.dart        Konuşmacı tanıma arayüzü + yer tutucu ← Faz 1c
    email_parser.dart           Sesle söylenen e-postayı ayrıştırma
    storage_service.dart        Cihazda saklama ve klasöre kopyalama
    settings_service.dart
  screens/                      home, preparation, enrollment, meeting, decisions, result, settings
test/  email_parser_test.dart, text_cleaner_test.dart
```

## Kayıtlar nerede

```
<Uygulama belgeleri>/FutureMeetingNotes/toplantilar/2026-10-19_22-29_Haftalik_Toplanti/
    toplanti.wav   toplantı kaydı
    kararlar.wav   karar dikte kaydı
    toplanti.json  katılımcılar, metin, kararlar
    toplanti_metni.txt  okunabilir döküm: [02:15] Ahmet Yılmaz: ...
    metin_<model>.txt   yeniden metne dökme sonuçları
<Uygulama belgeleri>/FutureMeetingNotes/ses_profilleri/<katılımcı-id>.wav
```

Ses örnekleri bilerek ayrı klasörde: KVKK açısından biyometrik veri sayılıyor,
saklama ve silme kuralları ileride bu klasöre uygulanacak.

## Sıradaki: Faz 1c — konuşmacı tanıma

1. Hazırlıktaki ses örneğinden ses izi çıkarma (sherpa-onnx speaker embedding).
2. Canlı ön etiket; toplantı sonunda tüm kaydı kümeleyip kesin etiket.
3. "Bilinmeyen Konuşmacı" eşiği ve elle düzeltmelerle ölçüm.
