import '../models/meeting.dart';
import 'insights_parser.dart';
import 'meeting_insights.dart';
import 'prompt_builder.dart';

/// Metin üreten dil modeli motoru. Faz 2'de iki seçenekten biri bağlanacak:
///  - cihaz içi küçük model (ses ve metin cihazdan çıkmaz),
///  - şirket sunucusu / API (yalnızca metin gönderilir, ses gönderilmez).
abstract class LanguageEngine {
  /// Kayıtlara yazılan kimlik (ör. "cihaz:qwen2.5-1.5b").
  String get id;

  /// Motor kullanıma hazır mı (model indirilmiş / adres tanımlı vb.).
  bool get isReady;

  /// Kısa bir uyarı/hazırlık mesajı (hazır değilse ne yapılmalı).
  String get statusText;

  /// [contextChars]: tek seferde verilebilecek en uzun metin (karakter).
  int get contextChars;

  Future<String> complete({required String system, required String user});
}

/// Faz 2 motoru seçilene kadar kullanılan yer tutucu.
class UnconfiguredEngine implements LanguageEngine {
  const UnconfiguredEngine();

  @override
  String get id => 'yok';

  @override
  bool get isReady => false;

  @override
  String get statusText =>
      'Özet motoru henüz bağlanmadı (Faz 2). Kararları dikte edip "Takip e-postası" '
      'ile şimdiden gönderebilirsiniz.';

  @override
  int get contextChars => 0;

  @override
  Future<String> complete({required String system, required String user}) =>
      throw StateError(statusText);
}

/// Toplantıdan özet / karar / görev çıkarır.
class InsightsService {
  InsightsService(this.engine, {this.prompts = const PromptBuilder(), this.parser = const InsightsParser()});

  final LanguageEngine engine;
  final PromptBuilder prompts;
  final InsightsParser parser;

  Future<MeetingInsights> generate(Meeting m) async {
    if (!engine.isReady) throw StateError(engine.statusText);
    final chunks = prompts.transcriptChunks(m, maxChars: engine.contextChars);

    // Kısa toplantı: tek seferde.
    if (chunks.length <= 1) {
      final raw = await engine.complete(
        system: PromptBuilder.systemPrompt,
        user: prompts.buildUserPrompt(m),
      );
      return parser.parse(raw, participants: m.participants, engine: engine.id);
    }

    // Uzun toplantı: her parçadan ayrı çıkar, sonra birleştir.
    final parts = <MeetingInsights>[];
    for (final c in chunks) {
      final raw = await engine.complete(
        system: PromptBuilder.systemPrompt,
        user: prompts.buildUserPrompt(m, transcriptOverride: c),
      );
      parts.add(parser.parse(raw, participants: m.participants, engine: engine.id));
    }
    return merge(parts, engine.id);
  }

  /// Parça sonuçlarını birleştirir (özetler arka arkaya, listeler tekrarsız).
  static MeetingInsights merge(List<MeetingInsights> parts, String engineId) {
    Set<String> seen = {};
    bool fresh(String s) => seen.add(s.trim().toLowerCase());
    final merged = MeetingInsights(
      summary: parts.map((p) => p.summary.trim()).where((s) => s.isNotEmpty).join('\n\n'),
      generatedAt: DateTime.now(),
      engine: engineId,
    );
    for (final p in parts) {
      merged.keyPoints.addAll(p.keyPoints.where(fresh));
    }
    seen = {};
    for (final p in parts) {
      merged.decisions.addAll(p.decisions.where((d) => fresh(d.text)));
    }
    seen = {};
    for (final p in parts) {
      merged.actionItems.addAll(p.actionItems.where((a) => fresh(a.task)));
    }
    seen = {};
    for (final p in parts) {
      merged.openQuestions.addAll(p.openQuestions.where(fresh));
    }
    return merged;
  }
}
