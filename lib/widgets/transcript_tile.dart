import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import '../services/meeting_search.dart';
import '../utils/format.dart';
import 'common.dart';

/// Konuşma metnindeki tek satır: konuşmacı etiketi, zaman, metin.
class TranscriptTile extends StatelessWidget {
  const TranscriptTile({
    super.key,
    required this.meeting,
    required this.segment,
    this.onRelabel,
    this.onTap,
    this.onLongPress,
    this.current,
    this.query = '',
  });

  final Meeting meeting;
  final TranscriptSegment segment;

  /// Verilirse etikete dokunulunca konuşmacı değiştirme menüsü açılır.
  final void Function(String? participantId)? onRelabel;

  /// Satıra dokunma (kayıtta o ana atlamak için).
  final VoidCallback? onTap;

  /// Uzun basma (metni düzeltmek için).
  final VoidCallback? onLongPress;

  /// Çalan parçanın id'si; bu satırsa vurgulanır.
  final ValueListenable<String?>? current;

  /// Arama sorgusu; eşleşen kelimeler vurgulanır.
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = current;
    if (c == null) return _tile(context, false);
    return ValueListenableBuilder<String?>(
      valueListenable: c,
      builder: (context, id, _) => _tile(context, id == segment.id),
    );
  }

  Widget _tile(BuildContext context, bool playing) {
    final participant = meeting.participantById(segment.speakerId);
    final index = meeting.participantIndex(segment.speakerId);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
      color: playing ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SpeakerChip(
                participant: participant,
                index: index,
                manual: segment.manuallyLabeled,
                onTap: onRelabel == null ? null : () => _pick(context),
              ),
              const SizedBox(width: 8),
              Text(
                formatDuration(segment.start),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (playing) ...[
                const SizedBox(width: 6),
                Icon(Icons.volume_up, size: 14, color: scheme.primary),
              ],
            ],
          ),
          const SizedBox(height: 4),
          _highlighted(context),
        ],
      ),
      ),
    );
  }

  Widget _highlighted(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final ranges = query.trim().isEmpty ? const <(int, int)>[] : matchRanges(segment.text, query);
    if (ranges.isEmpty) return Text(segment.text, style: style);
    final mark = TextStyle(
      backgroundColor: Colors.yellow.withValues(alpha: 0.55),
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var pos = 0;
    for (final (s, e) in ranges) {
      if (s > pos) spans.add(TextSpan(text: segment.text.substring(pos, s)));
      spans.add(TextSpan(text: segment.text.substring(s, e), style: mark));
      pos = e;
    }
    if (pos < segment.text.length) spans.add(TextSpan(text: segment.text.substring(pos)));
    return Text.rich(TextSpan(style: style, children: spans));
  }

  Future<void> _pick(BuildContext context) async {
    // Seçim: katılımcı id'si, '' = Bilinmeyen, null = iptal.
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Bu sözü kim söyledi?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (var i = 0; i < meeting.participants.length; i++)
              ListTile(
                leading: ParticipantAvatar(participant: meeting.participants[i], index: i),
                title: Text(meeting.participants[i].fullName),
                trailing: meeting.participants[i].id == segment.speakerId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, meeting.participants[i].id),
              ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.help_outline)),
              title: const Text('Bilinmeyen Konuşmacı'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    onRelabel?.call(selected.isEmpty ? null : selected);
  }
}
