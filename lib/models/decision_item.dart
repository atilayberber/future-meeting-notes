/// Toplantı sonunda dikte edilen tek bir karar maddesi (kişi etiketi yok).
class DecisionItem {
  DecisionItem({required this.id, required this.text, required this.at});

  final String id;
  String text;

  /// Karar dikte kaydının başından itibaren geçen süre.
  final Duration at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'atMs': at.inMilliseconds,
      };

  factory DecisionItem.fromJson(Map<String, dynamic> j) => DecisionItem(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        at: Duration(milliseconds: j['atMs'] as int? ?? 0),
      );
}
