import 'package:flutter/material.dart';

import '../models/meeting_mark.dart';
import '../utils/format.dart';

IconData markIcon(MarkKind k) => switch (k) {
      MarkKind.important => Icons.star_outline,
      MarkKind.decision => Icons.gavel_outlined,
      MarkKind.task => Icons.task_alt,
      MarkKind.question => Icons.help_outline,
      MarkKind.note => Icons.edit_note,
    };

Color markColor(MarkKind k, ColorScheme s) => switch (k) {
      MarkKind.important => Colors.amber.shade800,
      MarkKind.decision => s.primary,
      MarkKind.task => Colors.green.shade700,
      MarkKind.question => Colors.deepPurple,
      MarkKind.note => s.onSurfaceVariant,
    };

/// İşarete not yazdırma. İptal edilirse null.
Future<String?> showMarkNoteDialog(
  BuildContext context, {
  required MarkKind kind,
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${kind.label} — not'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Kısa bir not (isteğe bağlı)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}

/// Konuşma metninin arasında gösterilen işaret satırı.
class MarkTile extends StatelessWidget {
  const MarkTile({super.key, required this.mark, this.onTap, this.onLongPress});

  final MeetingMark mark;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = markColor(mark.kind, scheme);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Icon(markIcon(mark.kind), size: 18, color: color),
            const SizedBox(width: 8),
            Text(mark.kind.label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text(formatDuration(mark.at), style: Theme.of(context).textTheme.bodySmall),
            if (mark.note.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(mark.note, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
