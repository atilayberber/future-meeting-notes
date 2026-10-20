import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meeting.dart';
import '../models/participant.dart';
import '../state/meeting_controller.dart';
import '../widgets/common.dart';
import 'enrollment_screen.dart';
import 'meeting_screen.dart';

/// "Toplantı Öncesi Hazırlık": katılımcılar sırayla kaydedilir.
class PreparationScreen extends StatelessWidget {
  const PreparationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MeetingController>();
    final m = c.meeting;
    if (m == null) return const SizedBox.shrink();
    final ready = m.phase == MeetingPhase.ready;
    final missingVoice = m.participants.where((p) => !p.hasVoiceSample).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(ready ? 'Hazırlık Tamamlandı' : 'Toplantı Öncesi Hazırlık'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            initialValue: m.title,
            enabled: !ready,
            decoration: const InputDecoration(
              labelText: 'Toplantı başlığı',
              border: OutlineInputBorder(),
            ),
            onChanged: c.setTitle,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Katılımcılar (${m.participants.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (!ready)
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Katılımcı Ekle'),
                  onPressed: () => _addParticipant(context),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (m.participants.isEmpty)
            const PhaseNote(
              icon: Icons.record_voice_over_outlined,
              text: 'Her katılımcı sırayla adını, soyadını ve e-posta adresini söyler, '
                  'ardından kısa bir metni okur. Uygulama konuşmacıları bu ses örneğinden tanır.',
            ),
          for (var i = 0; i < m.participants.length; i++)
            _ParticipantCard(
              participant: m.participants[i],
              index: i,
              onDelete: ready ? null : () => c.removeParticipant(m.participants[i].id),
            ),
          if (missingVoice > 0) ...[
            const SizedBox(height: 12),
            PhaseNote(
              icon: Icons.warning_amber_rounded,
              text: '$missingVoice katılımcının ses örneği yok. Bu kişilerin sözleri '
                  '"Bilinmeyen" olarak etiketlenebilir.',
            ),
          ],
          if (c.lastError != null) ...[
            const SizedBox(height: 12),
            Text(c.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: ready
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryActionButton(
                      label: 'Toplantıyı Başlat',
                      icon: Icons.mic,
                      onPressed: () => _start(context),
                    ),
                    TextButton(
                      onPressed: c.backToPreparation,
                      child: const Text('Hazırlığa geri dön'),
                    ),
                  ],
                )
              : PrimaryActionButton(
                  label: 'Hazırlığı Bitir',
                  icon: Icons.check_circle_outline,
                  onPressed: m.participants.isEmpty ? null : c.finishPreparation,
                ),
        ),
      ),
    );
  }

  Future<void> _addParticipant(BuildContext context) async {
    final controller = context.read<MeetingController>();
    final participant = await Navigator.of(context).push<Participant>(
      MaterialPageRoute(builder: (_) => const EnrollmentScreen()),
    );
    if (participant != null) await controller.addParticipant(participant);
  }

  Future<void> _start(BuildContext context) async {
    final controller = context.read<MeetingController>();
    final navigator = Navigator.of(context);
    final ok = await controller.startMeeting();
    if (ok) {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MeetingScreen()),
      );
    }
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({required this.participant, required this.index, this.onDelete});

  final Participant participant;
  final int index;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ParticipantAvatar(participant: participant, index: index),
        title: Text(participant.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(participant.email),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  participant.hasVoiceSample ? Icons.graphic_eq : Icons.mic_off_outlined,
                  size: 14,
                  color: participant.hasVoiceSample ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  participant.hasVoiceSample
                      ? 'Ses örneği: ${participant.voiceSampleSeconds} sn'
                      : 'Ses örneği yok',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: onDelete == null
            ? null
            : IconButton(
                tooltip: 'Çıkar',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
      ),
    );
  }
}
