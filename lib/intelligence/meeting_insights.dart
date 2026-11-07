/// Faz 2: yapay zekânın konuşmadan çıkardığı sonuç (özet, kararlar, görevler).
///
/// Recco'daki "AI Summary + Action Items" karşılığı. Model, hangi motorun
/// (cihaz içi küçük dil modeli veya sunucu) ürettiğinden bağımsızdır; motor
/// [engine] alanına yazılır.
class MeetingInsights {
  MeetingInsights({
    required this.summary,
    required this.generatedAt,
    required this.engine,
    List<String>? keyPoints,
    List<InsightDecision>? decisions,
    List<ActionItem>? actionItems,
    List<String>? openQuestions,
  })  : keyPoints = keyPoints ?? [],
        decisions = decisions ?? [],
        actionItems = actionItems ?? [],
        openQuestions = openQuestions ?? [];

  /// Birkaç cümlelik genel özet.
  String summary;

  /// Konuşulan ana başlıklar.
  final List<String> keyPoints;

  /// Konuşmadan çıkarılan kararlar (dikte edilen kararlarla karşılaştırılacak).
  final List<InsightDecision> decisions;

  /// Görevler: ne, kim, ne zamana.
  final List<ActionItem> actionItems;

  /// Karara bağlanmadan kalan konular.
  final List<String> openQuestions;

  final DateTime generatedAt;

  /// Üreten motorun kimliği (ör. "cihaz:qwen2.5-1.5b" veya "sunucu:...").
  final String engine;

  bool get isEmpty =>
      summary.trim().isEmpty &&
      keyPoints.isEmpty &&
      decisions.isEmpty &&
      actionItems.isEmpty &&
      openQuestions.isEmpty;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'keyPoints': keyPoints,
        'decisions': decisions.map((d) => d.toJson()).toList(),
        'actionItems': actionItems.map((a) => a.toJson()).toList(),
        'openQuestions': openQuestions,
        'generatedAt': generatedAt.toIso8601String(),
        'engine': engine,
      };

  factory MeetingInsights.fromJson(Map<String, dynamic> j) => MeetingInsights(
        summary: j['summary'] as String? ?? '',
        keyPoints: _strings(j['keyPoints']),
        decisions: _maps(j['decisions']).map(InsightDecision.fromJson).toList(),
        actionItems: _maps(j['actionItems']).map(ActionItem.fromJson).toList(),
        openQuestions: _strings(j['openQuestions']),
        generatedAt: DateTime.tryParse(j['generatedAt'] as String? ?? '') ?? DateTime.now(),
        engine: j['engine'] as String? ?? '',
      );
}

class InsightDecision {
  InsightDecision({required this.text, this.ownerId, this.at});

  String text;

  /// Kararı söyleyen / sorumlu katılımcı (biliniyorsa).
  String? ownerId;

  /// Kararın konuşulduğu an (kayıtta oraya atlamak için).
  Duration? at;

  Map<String, dynamic> toJson() => {
        'text': text,
        'ownerId': ownerId,
        'atMs': at?.inMilliseconds,
      };

  factory InsightDecision.fromJson(Map<String, dynamic> j) => InsightDecision(
        text: j['text'] as String? ?? '',
        ownerId: j['ownerId'] as String?,
        at: j['atMs'] == null ? null : Duration(milliseconds: j['atMs'] as int),
      );
}

class ActionItem {
  ActionItem({required this.task, this.ownerId, this.ownerName, this.due, this.at});

  String task;

  /// Katılımcılardan biriyse id'si.
  String? ownerId;

  /// Katılımcı listesinde yoksa söylendiği gibi ad (ör. "muhasebe").
  String? ownerName;

  /// Söylendiği gibi tarih ("cuma", "ay sonu").
  String? due;

  Duration? at;

  Map<String, dynamic> toJson() => {
        'task': task,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'due': due,
        'atMs': at?.inMilliseconds,
      };

  factory ActionItem.fromJson(Map<String, dynamic> j) => ActionItem(
        task: j['task'] as String? ?? '',
        ownerId: j['ownerId'] as String?,
        ownerName: j['ownerName'] as String?,
        due: j['due'] as String?,
        at: j['atMs'] == null ? null : Duration(milliseconds: j['atMs'] as int),
      );
}

List<String> _strings(Object? v) =>
    (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

List<Map<String, dynamic>> _maps(Object? v) =>
    (v as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
