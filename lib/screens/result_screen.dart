import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../asr/model_manager.dart';
import '../models/meeting.dart';
import '../state/meeting_controller.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/transcript_tile.dart';

/// Tamamlanan (veya geçmişten açılan) toplantının sonucu.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.meeting});

  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    // Etiket düzeltme / yeniden metne dökme sonrası yeniden çizilsin.
    context.watch<MeetingController>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Ana sayfa',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          title: Text(meeting.title, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Konuşma (${meeting.segments.length})'),
              Tab(text: 'Kararlar (${meeting.decisions.length})'),
              const Tab(text: 'Bilgi'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TranscriptTab(meeting: meeting),
            _DecisionsTab(meeting: meeting),
            _InfoTab(meeting: meeting),
          ],
        ),
      ),
    );
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    if (meeting.segments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: PhaseNote(
          text: 'Bu toplantı için konuşma metni yok. "Bilgi" sekmesinden kaydı metne dökebilirsiniz.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: meeting.segments.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) => TranscriptTile(
        meeting: meeting,
        segment: meeting.segments[i],
        onRelabel: (pid) => context
            .read<MeetingController>()
            .relabelSegment(meeting, meeting.segments[i].id, pid),
      ),
    );
  }
}

class _DecisionsTab extends StatelessWidget {
  const _DecisionsTab({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Dikte edilen kararlar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (meeting.decisions.isEmpty)
          const Text('Karar dikte edilmedi.')
        else
          for (var i = 0; i < meeting.decisions.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
              title: Text(meeting.decisions[i].text),
            ),
        const SizedBox(height: 24),
        const PhaseNote(
          icon: Icons.auto_awesome_outlined,
          text: 'Faz 2: Yapay zekâ konuşmadan kararları çıkaracak, toplantı özetini '
              'hazırlayacak ve dikte edilen kararlarla karşılaştıracak '
              '(Eşleşen / Sadece dikte edilen / Sadece konuşmadan çıkan).',
        ),
      ],
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(label, style: theme.textTheme.bodySmall)),
              Expanded(child: SelectableText(value)),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        row('Başlangıç', formatDateTime(meeting.startedAt ?? meeting.createdAt)),
        row('Süre', formatDuration(meeting.duration)),
        row('Toplantı kaydı', meeting.audioPath ?? '-'),
        if (meeting.decisionsAudioPath != null) row('Karar kaydı', meeting.decisionsAudioPath!),
        row('Kopyalandığı yer', meeting.exportPath ?? 'Yalnızca uygulama içinde'),
        const SizedBox(height: 16),
        Text('Katılımcılar', style: theme.textTheme.titleMedium),
        for (var i = 0; i < meeting.participants.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ParticipantAvatar(participant: meeting.participants[i], index: i),
            title: Text(meeting.participants[i].fullName),
            subtitle: Text(meeting.participants[i].email),
          ),
        const SizedBox(height: 16),
        if (meeting.audioPath != null) _RetranscribeButton(meeting: meeting),
        const SizedBox(height: 8),
        const FilledButton(
          onPressed: null,
          child: Text('Kararları Katılımcılara Gönder (Faz 2)'),
        ),
      ],
    );
  }
}

/// Kaydı seçili modelle baştan yazıya döker (model karşılaştırması için de).
class _RetranscribeButton extends StatefulWidget {
  const _RetranscribeButton({required this.meeting});
  final Meeting meeting;

  @override
  State<_RetranscribeButton> createState() => _RetranscribeButtonState();
}

class _RetranscribeButtonState extends State<_RetranscribeButton> {
  double? _progress;

  Future<void> _run() async {
    final controller = context.read<MeetingController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıt yeniden metne dökülsün mü?'),
        content: const Text(
          'Mevcut metin ve elle düzeltilen konuşmacı etiketleri değişecek. '
          'Uzun kayıtlarda bu işlem toplantı süresi kadar sürebilir; uygulamayı açık tutun.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Başlat')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _progress = 0);
    try {
      await controller.retranscribe(
        widget.meeting,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      messenger.showSnackBar(const SnackBar(content: Text('Kayıt yeniden metne döküldü.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Metne dökülemedi: $e')));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ModelManager>().activeModel;
    final p = _progress;
    if (p != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Metne dökülüyor (${model.title})… %${(p * 100).round()}'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: p),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: _run,
      icon: const Icon(Icons.subtitles_outlined),
      label: Text('Kaydı yeniden metne dök (${model.title})'),
    );
  }
}
