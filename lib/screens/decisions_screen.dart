import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meeting.dart';
import '../state/meeting_controller.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Toplantı bittikten sonra: "Toplantı Kararlarını Yaz" → dikte →
/// "Toplantı Kararlarını Bitir". Kişi etiketi yok; her söz bir madde.
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key});

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addTyped(MeetingController c) {
    c.addDecision(_input.text);
    _input.clear();
  }

  Future<void> _finish(Future<String?> Function() action) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<MeetingController>();
    final message = await action();
    final meeting = controller.meeting!;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => ResultScreen(meeting: meeting)),
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editDecision(MeetingController c, String id, String text) async {
    final edit = TextEditingController(text: text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kararı düzenle'),
        content: TextField(controller: edit, maxLines: null, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, edit.text), child: const Text('Kaydet')),
        ],
      ),
    );
    edit.dispose();
    if (result != null && result.trim().isNotEmpty) c.updateDecision(id, result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MeetingController>();
    final m = c.meeting;
    if (m == null) return const SizedBox.shrink();
    final dictating = m.phase == MeetingPhase.dictatingDecisions;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Toplantı Kararları'),
        ),
        body: dictating ? _dictationBody(c, m, theme) : _startBody(c, m, theme),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: c.busy
                ? BusyBar(message: c.busyMessage!, lag: c.transcriptionLag)
                : dictating
                    ? PrimaryActionButton(
                        label: 'Toplantı Kararlarını Bitir',
                        icon: Icons.done_all,
                        onPressed: () => _finish(c.finishDecisions),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PrimaryActionButton(
                            label: 'Toplantı Kararlarını Yaz',
                            icon: Icons.edit_note,
                            onPressed: () async {
                              final ok = await c.startDecisionDictation();
                              if (!ok && context.mounted && c.lastError != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(c.lastError!)));
                              }
                            },
                          ),
                          TextButton(
                            onPressed: () => _finish(c.completeWithoutDecisions),
                            child: const Text('Karar dikte etmeden bitir'),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _startBody(MeetingController c, Meeting m, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Toplantı tamamlandı', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${formatDuration(m.duration)} · ${m.segments.length} konuşma parçası · '
          '${m.participants.length} katılımcı',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        const PhaseNote(
          icon: Icons.edit_note,
          text: '"Toplantı Kararlarını Yaz" ile kararları sesli olarak söyleyin. '
              'Söylenen her söz ayrı bir madde olarak yazılır (kişi etiketi olmadan). '
              'Faz 2\'de bu maddeler, uygulamanın konuşmadan çıkardığı kararlarla karşılaştırılacak.',
        ),
      ],
    );
  }

  Widget _dictationBody(MeetingController c, Meeting m, ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const RecordingDot(),
                  const SizedBox(width: 8),
                  Text('Kararlar kaydediliyor', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(formatDuration(c.elapsed), style: theme.textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 10),
              LevelMeter(level: c.level),
              ValueListenableBuilder<String?>(
                valueListenable: c.transcriptionProblem,
                builder: (context, problem, _) => problem == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: PhaseNote(icon: Icons.warning_amber_rounded, text: problem),
                      ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: m.decisions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: PhaseNote(
                    text: 'Kararları sırayla söyleyin; her söz, kısa bir sessizlikten sonra '
                        'ayrı bir madde olarak eklenir. Maddeye dokunarak düzeltebilir, '
                        'aşağıdan elle de ekleyebilirsiniz.',
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: m.decisions.length,
                  onReorder: c.reorderDecision,
                  itemBuilder: (_, i) {
                    final d = m.decisions[i];
                    return ListTile(
                      key: ValueKey(d.id),
                      leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                      title: Text(d.text),
                      onTap: () => _editDecision(c, d.id, d.text),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => c.removeDecision(d.id),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTyped(c),
                  decoration: const InputDecoration(
                    hintText: 'Karar maddesi ekle',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _addTyped(c),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
