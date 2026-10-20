import 'package:flutter/material.dart';

import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import '../utils/format.dart';
import 'common.dart';

/// Konuşma metnindeki tek satır: konuşmacı etiketi, zaman, metin.
class TranscriptTile extends StatelessWidget {
  const TranscriptTile({
    super.key,
    required this.meeting,
    required this.segment,
    this.onRelabel,
  });

  final Meeting meeting;
  final TranscriptSegment segment;

  /// Verilirse etikete dokunulunca konuşmacı değiştirme menüsü açılır.
  final void Function(String? participantId)? onRelabel;

  @override
  Widget build(BuildContext context) {
    final participant = meeting.participantById(segment.speakerId);
    final index = meeting.participantIndex(segment.speakerId);
    return Padding(
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
            ],
          ),
          const SizedBox(height: 4),
          Text(segment.text, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
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
