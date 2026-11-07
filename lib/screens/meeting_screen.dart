import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meeting_mark.dart';
import '../state/meeting_controller.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/marks.dart';
import '../widgets/transcript_tile.dart';
import 'decisions_screen.dart';

/// Toplantı kaydı sürerken gösterilen ekran.
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplantı bitirilsin mi?'),
        content: const Text('Kayıt durdurulacak. Ardından kararları dikte edebilirsiniz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bitir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final controller = context.read<MeetingController>();
    final navigator = Navigator.of(context);
    await controller.endMeeting();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const DecisionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MeetingController>();
    final m = c.meeting;
    if (m == null) return const SizedBox.shrink();
    _autoScroll(m.segments.length);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !c.busy) _confirmEnd();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(m.title, overflow: TextOverflow.ellipsis),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const RecordingDot(),
                      const SizedBox(width: 8),
                      Text('Kayıt sürüyor', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Text(formatDuration(c.elapsed), style: theme.textTheme.headlineMedium),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LevelMeter(level: c.level),
                  _TranscriptionStatus(controller: c),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: m.participants.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) =>
                          SpeakerChip(participant: m.participants[i], index: i),
                    ),
                  ),
                  const SizedBox(height: 10),
                  MarkBar(controller: c),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: m.segments.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: PhaseNote(
                        text: 'Konuşulanlar burada görünecek. Metin, konuşma bitip kısa bir '
                            'sessizlik olduğunda eklenir. Konuşmacı etiketlerini şimdilik '
                            'etikete dokunarak düzeltebilirsiniz (otomatik tanıma Faz 1c\'de).',
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: m.segments.length,
                      itemBuilder: (_, i) => TranscriptTile(
                        meeting: m,
                        segment: m.segments[i],
                        onRelabel: (pid) => c.relabelSegment(m, m.segments[i].id, pid),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: c.busy
                ? BusyBar(message: c.busyMessage!, lag: c.transcriptionLag)
                : PrimaryActionButton(
                    label: 'Toplantıyı Bitir',
                    icon: Icons.stop_circle_outlined,
                    destructive: true,
                    onPressed: _confirmEnd,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Kayıt sırasında tek dokunuşla anı işaretleme (Recco: "kayıt sırasında not").
class MarkBar extends StatelessWidget {
  const MarkBar({super.key, required this.controller});
  final MeetingController controller;

  static const _quick = [MarkKind.important, MarkKind.decision, MarkKind.task, MarkKind.question];

  Future<void> _mark(BuildContext context, MarkKind kind, {bool askNote = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    // Zamanı not yazılmadan önce al: işaret, düğmeye basılan ana ait olsun.
    final at = controller.elapsed;
    var note = '';
    if (askNote) {
      final text = await showMarkNoteDialog(context, kind: kind);
      if (text == null) return;
      note = text;
    }
    final mark = controller.addMark(kind, note: note, at: at);
    if (mark == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('${kind.label} işaretlendi (${formatDuration(at)})'),
        action: askNote
            ? null
            : SnackBarAction(
                label: 'Not ekle',
                onPressed: () async {
                  final m = controller.meeting;
                  if (m == null || !context.mounted) return;
                  final text = await showMarkNoteDialog(context, kind: kind);
                  if (text != null) await controller.updateMark(m, mark.id, note: text);
                },
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final count = controller.meeting?.marks.length ?? 0;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in _quick) ...[
                  ActionChip(
                    avatar: Icon(markIcon(k), size: 18),
                    label: Text(k.label),
                    onPressed: () => _mark(context, k),
                  ),
                  const SizedBox(width: 6),
                ],
                ActionChip(
                  avatar: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Not'),
                  onPressed: () => _mark(context, MarkKind.note, askNote: true),
                ),
              ],
            ),
          ),
        ),
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: '$count işaret',
              child: Badge(
                label: Text('$count'),
                child: const Icon(Icons.bookmark_outline),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kayıt sırasında: konuşma tanımanın durumu (geride kalma, model sorunu).
class _TranscriptionStatus extends StatelessWidget {
  const _TranscriptionStatus({required this.controller});
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: controller.transcriptionProblem,
      builder: (context, problem, _) {
        if (problem != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PhaseNote(icon: Icons.warning_amber_rounded, text: problem),
          );
        }
        return ValueListenableBuilder<double>(
          valueListenable: controller.transcriptionLag,
          builder: (context, lag, _) {
            if (lag < 5) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Metin canlı sesin ${lag.round()} sn gerisinde — hiçbir konuşma atlanmaz, '
                'toplantı bitince tamamlanır.',
                style: theme.textTheme.bodySmall,
              ),
            );
          },
        );
      },
    );
  }
}
