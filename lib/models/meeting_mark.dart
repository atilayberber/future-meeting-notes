/// Kayıt sırasında tek dokunuşla işaretlenen an (Recco'daki "kayıt sırasında not").
///
/// Toplantıyı yöneten kişi önemli bir anı, söylenen bir kararı ya da verilen
/// bir görevi o an işaretler. Bu işaretler:
///  - Konuşma metninde ilgili saniyede gösterilir (kayıtta o ana atlanabilir),
///  - Faz 2'de yapay zekâya "burası önemli" ipucu olarak verilir,
///  - "Karar" işaretleri dikte edilen kararlarla karşılaştırmada kullanılır.
enum MarkKind {
  important('Önemli'),
  decision('Karar'),
  task('Görev'),
  question('Soru'),
  note('Not');

  const MarkKind(this.label);
  final String label;

  static MarkKind fromName(Object? name) =>
      MarkKind.values.asNameMap()[name] ?? MarkKind.note;
}

class MeetingMark {
  MeetingMark({
    required this.id,
    required this.at,
    required this.kind,
    this.note = '',
  });

  final String id;

  /// Toplantı kaydının başından itibaren geçen süre.
  final Duration at;
  MarkKind kind;

  /// İsteğe bağlı açıklama (yazılarak eklenir).
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'atMs': at.inMilliseconds,
        'kind': kind.name,
        'note': note,
      };

  factory MeetingMark.fromJson(Map<String, dynamic> j) => MeetingMark(
        id: j['id'] as String,
        at: Duration(milliseconds: j['atMs'] as int? ?? 0),
        kind: MarkKind.fromName(j['kind']),
        note: j['note'] as String? ?? '',
      );
}
