import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/participant.dart';

/// Ekranın altındaki büyük ana eylem butonu.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        style: destructive
            ? FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              )
            : null,
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Kayıt sırasında ses seviyesini gösteren çubuk.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(value: level, minHeight: 10),
    );
  }
}

/// Yanıp sönen kırmızı "kayıt" noktası.
class RecordingDot extends StatefulWidget {
  const RecordingDot({super.key});

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}

const List<Color> _speakerColors = [
  Color(0xFF1F7A8C),
  Color(0xFFB5563B),
  Color(0xFF5B6CC2),
  Color(0xFF3F8F4E),
  Color(0xFF9A4F96),
  Color(0xFFB08A1E),
  Color(0xFF2F6D9E),
  Color(0xFF8C5B3E),
];

Color speakerColor(int index) =>
    index < 0 ? Colors.grey : _speakerColors[index % _speakerColors.length];

/// Konuşmacı etiketi. [participant] null ise "Bilinmeyen".
class SpeakerChip extends StatelessWidget {
  const SpeakerChip({
    super.key,
    required this.participant,
    required this.index,
    this.onTap,
    this.manual = false,
  });

  final Participant? participant;
  final int index;
  final VoidCallback? onTap;
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final color = speakerColor(index);
    final name = participant?.fullName ?? 'Bilinmeyen';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (manual) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 12, color: color),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({super.key, required this.participant, required this.index});

  final Participant participant;
  final int index;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: speakerColor(index),
      foregroundColor: Colors.white,
      child: Text(participant.initials),
    );
  }
}

/// Henüz yapılmamış özellikler için bilgi kutusu.
class PhaseNote extends StatelessWidget {
  const PhaseNote({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}

/// Toplantı/karar sonu: kalan konuşmalar yazıya dökülürken gösterilir.
class BusyBar extends StatelessWidget {
  const BusyBar({super.key, required this.message, required this.lag});

  final String message;
  final ValueListenable<double> lag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator()),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: lag,
              builder: (context, seconds, _) => Text(
                seconds >= 1 ? '$message (yaklaşık ${seconds.round()} sn ses kaldı)' : message,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
