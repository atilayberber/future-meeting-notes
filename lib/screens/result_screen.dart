import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../asr/model_manager.dart';
import '../intelligence/insights_service.dart';
import '../intelligence/meeting_insights.dart';
import '../models/meeting.dart';
import '../models/meeting_mark.dart';
import '../models/meeting_type.dart';
import '../models/transcript_segment.dart';
import '../services/meeting_player.dart';
import '../services/meeting_report.dart';
import '../services/meeting_search.dart';
import '../services/storage_service.dart';
import '../state/meeting_controller.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/marks.dart';
import '../widgets/transcript_tile.dart';

/// Tamamlanan (veya geçmişten açılan) toplantının sonucu.
///
/// Recco'dan alınanlar: satıra dokununca kaydı o andan dinleme, metni düzeltme,
/// toplantı içinde "kim ne dedi" araması, işaretlenen anlar, kişi başı konuşma
/// süresi, notları/sesi paylaşma ve takip e-postası.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.meeting, this.initialQuery = ''});

  final Meeting meeting;

  /// Genel aramadan açıldıysa arama kutusu bu sorguyla açılır.
  final String initialQuery;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final MeetingPlayer _player;
  late final TextEditingController _search;
  bool _searching = false;

  /// null = herkes, '' = Bilinmeyen, diğer = katılımcı id'si.
  String? _speakerFilter;

  Meeting get m => widget.meeting;

  @override
  void initState() {
    super.initState();
    _player = MeetingPlayer(segments: () => m.segments)..load(m.audioPath);
    _search = TextEditingController(text: widget.initialQuery);
    _searching = widget.initialQuery.isNotEmpty;
  }

  @override
  void dispose() {
    _player.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Etiket/metin düzeltme ve yeniden metne dökme sonrası yeniden çizilsin.
    context.watch<MeetingController>();
    final hasAudio = m.audioPath != null && File(m.audioPath!).existsSync();
    final decisionCount = m.decisions.length +
        m.marks.where((k) => k.kind == MarkKind.decision || k.kind == MarkKind.task).length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Ana sayfa',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          title: Text(m.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Takip e-postası',
              icon: const Icon(Icons.forward_to_inbox_outlined),
              onPressed: () => sendFollowUpEmail(context, m),
            ),
            IconButton(
              tooltip: 'Paylaş',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _shareSheet(context),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Konuşma (${m.segments.length})'),
              Tab(text: 'Kararlar ($decisionCount)'),
              const Tab(text: 'Bilgi'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _transcriptTab(context),
            _DecisionsTab(meeting: m, player: _player),
            _InfoTab(meeting: m),
          ],
        ),
        bottomNavigationBar: hasAudio ? PlayerBar(player: _player) : null,
      ),
    );
  }

  // ------------------------------------------------------------- Konuşma sekmesi

  Widget _transcriptTab(BuildContext context) {
    if (m.segments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: PhaseNote(
          text: 'Bu toplantı için konuşma metni yok. "Bilgi" sekmesinden kaydı metne dökebilirsiniz.',
        ),
      );
    }
    final query = _search.text;
    final filtering = query.trim().isNotEmpty || _speakerFilter != null;
    final segments = filtering ? searchMeeting(m, query, speakerId: _speakerFilter) : m.segments;
    final items = filtering ? <Object>[...segments] : _timeline();

    return Column(
      children: [
        _searchHeader(context, segments.length, filtering),
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: PhaseNote(icon: Icons.search_off, text: 'Eşleşen konuşma yok.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is MeetingMark) {
                      return MarkTile(
                        mark: item,
                        onTap: () => _player.playFrom(item.at),
                        onLongPress: () => _editMark(context, item),
                      );
                    }
                    final s = item as TranscriptSegment;
                    return TranscriptTile(
                      meeting: m,
                      segment: s,
                      query: query,
                      current: _player.currentSegmentId,
                      onTap: () => _player.playFrom(s.start),
                      onLongPress: () => _editSegment(context, s),
                      onRelabel: (pid) =>
                          context.read<MeetingController>().relabelSegment(m, s.id, pid),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Konuşma parçaları ve işaretler zaman sırasıyla.
  List<Object> _timeline() {
    final marks = [...m.marks]..sort((a, b) => a.at.compareTo(b.at));
    final out = <Object>[];
    var k = 0;
    for (final s in m.segments) {
      while (k < marks.length && marks[k].at <= s.start) {
        out.add(marks[k++]);
      }
      out.add(s);
    }
    out.addAll(marks.skip(k));
    return out;
  }

  Widget _searchHeader(BuildContext context, int count, bool filtering) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searching)
              TextField(
                controller: _search,
                autofocus: widget.initialQuery.isEmpty,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Metinde ara (ör. bütçe, teslim tarihi)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Aramayı kapat',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _searching = false;
                    }),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            if (_searching) const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!_searching) ...[
                    ActionChip(
                      avatar: const Icon(Icons.search, size: 18),
                      label: const Text('Ara'),
                      onPressed: () => setState(() => _searching = true),
                    ),
                    const SizedBox(width: 6),
                  ],
                  FilterChip(
                    label: const Text('Herkes'),
                    selected: _speakerFilter == null,
                    onSelected: (_) => setState(() => _speakerFilter = null),
                  ),
                  for (var i = 0; i < m.participants.length; i++) ...[
                    const SizedBox(width: 6),
                    FilterChip(
                      avatar: CircleAvatar(backgroundColor: speakerColor(i), radius: 6),
                      label: Text(m.participants[i].firstName),
                      selected: _speakerFilter == m.participants[i].id,
                      onSelected: (on) =>
                          setState(() => _speakerFilter = on ? m.participants[i].id : null),
                    ),
                  ],
                  if (m.segments.any((s) => s.speakerId == null)) ...[
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Bilinmeyen'),
                      selected: _speakerFilter == '',
                      onSelected: (on) => setState(() => _speakerFilter = on ? '' : null),
                    ),
                  ],
                ],
              ),
            ),
            if (filtering)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text('$count konuşma', style: theme.textTheme.bodySmall),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Dinlemek için satıra dokunun · düzeltmek için basılı tutun',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSegment(BuildContext context, TranscriptSegment s) async {
    final controller = context.read<MeetingController>();
    final ctrl = TextEditingController(text: s.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Metni düzelt · ${formatDuration(s.start)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () {
              _player.playFrom(s.start);
            },
            child: const Text('Dinle'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty && text.trim() != s.text) {
      await controller.editSegmentText(m, s.id, text);
    }
  }

  Future<void> _editMark(BuildContext context, MeetingMark mark) async {
    final controller = context.read<MeetingController>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in MarkKind.values)
              ListTile(
                leading: Icon(markIcon(k)),
                title: Text(k.label),
                trailing: k == mark.kind ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, 'kind:${k.name}'),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Notu düzenle'),
              onTap: () => Navigator.pop(ctx, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('İşareti sil'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') {
      await controller.removeMark(m, mark.id);
    } else if (action == 'note') {
      final text = await showMarkNoteDialog(context, kind: mark.kind, initial: mark.note);
      if (text != null) await controller.updateMark(m, mark.id, note: text);
    } else if (action.startsWith('kind:')) {
      await controller.updateMark(m, mark.id, kind: MarkKind.fromName(action.substring(5)));
    }
  }

  Future<void> _shareSheet(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Toplantı notu (kararlar + tam metin)'),
              subtitle: const Text('Markdown dosyası'),
              onTap: () => Navigator.pop(ctx, 'full'),
            ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Sadece kararlar ve işaretler'),
              subtitle: const Text('Metin olarak'),
              onTap: () => Navigator.pop(ctx, 'short'),
            ),
            if (m.audioPath != null)
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: const Text('Ses kaydı'),
                subtitle: const Text('WAV dosyası'),
                onTap: () => Navigator.pop(ctx, 'audio'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (choice) {
        case 'full':
          final path = await storage.writeMarkdown(m);
          if (path == null) return;
          await SharePlus.instance.share(ShareParams(
            title: m.title,
            subject: 'Toplantı notu: ${m.title}',
            files: [XFile(path, mimeType: 'text/markdown')],
          ));
        case 'short':
          await SharePlus.instance.share(ShareParams(
            title: m.title,
            subject: 'Toplantı notu: ${m.title}',
            text: meetingToMarkdown(m, includeTranscript: false),
          ));
        case 'audio':
          await SharePlus.instance.share(ShareParams(
            title: m.title,
            files: [XFile(m.audioPath!, mimeType: 'audio/wav')],
          ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
    }
  }
}

/// Katılımcılara takip e-postası: e-posta uygulaması alıcılar, konu ve metinle açılır.
/// E-posta uygulaması açılamazsa paylaşım menüsü gösterilir.
Future<void> sendFollowUpEmail(BuildContext context, Meeting m) async {
  final mail = buildFollowUpEmail(m);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Takip e-postası'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Alıcılar: ${mail.to.isEmpty ? '(e-postası olan katılımcı yok)' : mail.to.join(', ')}'),
              const SizedBox(height: 8),
              Text('Konu: ${mail.subject}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Divider(),
              SelectableText(mail.body),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('E-posta uygulamasında aç'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  var opened = false;
  try {
    opened = await launchUrl(mail.toMailtoUri(), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    try {
      await SharePlus.instance.share(ShareParams(subject: mail.subject, text: mail.body));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('E-posta açılamadı: $e')));
    }
  }
}

/// Alt kısımdaki oynatma çubuğu.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.player});
  final MeetingPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            if (player.error != null) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(player.error!, style: theme.textTheme.bodySmall),
              );
            }
            final total = player.duration.inMilliseconds.toDouble();
            final pos = player.position.inMilliseconds.clamp(0, total.toInt()).toDouble();
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '10 sn geri',
                    icon: const Icon(Icons.replay_10),
                    onPressed: player.loaded ? () => player.skip(const Duration(seconds: -10)) : null,
                  ),
                  IconButton.filled(
                    tooltip: player.playing ? 'Duraklat' : 'Çal',
                    icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
                    onPressed: player.loaded ? player.toggle : null,
                  ),
                  IconButton(
                    tooltip: '10 sn ileri',
                    icon: const Icon(Icons.forward_10),
                    onPressed: player.loaded ? () => player.skip(const Duration(seconds: 10)) : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: total > 0 ? pos : 0,
                          max: total > 0 ? total : 1,
                          onChanged: total > 0
                              ? (v) => player.seek(Duration(milliseconds: v.round()))
                              : null,
                        ),
                        Text(
                          '${formatDuration(player.position)} / ${formatDuration(player.duration)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: player.loaded ? player.cycleSpeed : null,
                    child: Text('${player.speed.toStringAsFixed(player.speed % 1 == 0 ? 0 : 1)}x'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Kararlar sekmesi

class _DecisionsTab extends StatelessWidget {
  const _DecisionsTab({required this.meeting, required this.player});
  final Meeting meeting;
  final MeetingPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flagged = meeting.marks
        .where((k) => k.kind == MarkKind.decision || k.kind == MarkKind.task)
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final insights = meeting.insights;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Dikte edilen kararlar', style: theme.textTheme.titleMedium),
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
        if (flagged.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Toplantıda işaretlenen kararlar ve görevler', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Dokununca kayıt o andan çalar.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final k in flagged) _FlaggedMoment(meeting: meeting, mark: k, player: player),
        ],
        const SizedBox(height: 20),
        if (insights != null && !insights.isEmpty)
          _InsightsView(meeting: meeting, insights: insights, player: player)
        else
          const PhaseNote(
            icon: Icons.auto_awesome_outlined,
            text: 'Faz 2: Yapay zekâ konuşmadan özet, kararlar ve görevleri (kim, ne zamana) '
                'çıkaracak; dikte edilen kararlar ve işaretlenen anlarla karşılaştıracak. '
                'Şablonlar ve sonuç yapısı hazır; özet motoru seçildiğinde burada görünecek.',
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => sendFollowUpEmail(context, meeting),
          icon: const Icon(Icons.forward_to_inbox_outlined),
          label: const Text('Katılımcılara takip e-postası'),
        ),
      ],
    );
  }
}

/// İşaretlenen an + o anda söylenen cümle.
class _FlaggedMoment extends StatelessWidget {
  const _FlaggedMoment({required this.meeting, required this.mark, required this.player});
  final Meeting meeting;
  final MeetingMark mark;
  final MeetingPlayer player;

  @override
  Widget build(BuildContext context) {
    final said = meeting.segmentAt(mark.at);
    final scheme = Theme.of(context).colorScheme;
    final who = meeting.participantById(said?.speakerId)?.fullName ?? 'Bilinmeyen';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => player.playFrom(said?.start ?? mark.at),
        leading: Icon(markIcon(mark.kind), color: markColor(mark.kind, scheme)),
        title: Text(
          mark.note.isNotEmpty ? mark.note : (said?.text ?? '(o anda konuşma yok)'),
        ),
        subtitle: Text(
          '${mark.kind.label} · ${formatDuration(mark.at)}'
          '${said != null ? ' · $who${mark.note.isNotEmpty ? ': «${said.text}»' : ''}' : ''}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.play_circle_outline),
      ),
    );
  }
}

/// Faz 2 sonucu (yapay zekâ özeti) — motor bağlandığında dolar.
class _InsightsView extends StatelessWidget {
  const _InsightsView({required this.meeting, required this.insights, required this.player});
  final Meeting meeting;
  final MeetingInsights insights;
  final MeetingPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(title, style: theme.textTheme.titleMedium),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 18),
            const SizedBox(width: 6),
            Text('Yapay zekâ özeti', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        if (insights.summary.isNotEmpty) Text(insights.summary),
        if (insights.decisions.isNotEmpty) ...[
          section('Konuşmadan çıkan kararlar'),
          for (final d in insights.decisions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.gavel_outlined),
              title: Text(d.text),
              subtitle: Text([
                if (meeting.participantById(d.ownerId) != null)
                  meeting.participantById(d.ownerId)!.fullName,
                if (d.at != null) formatDuration(d.at!),
              ].join(' · ')),
              onTap: d.at == null ? null : () => player.playFrom(d.at!),
            ),
        ],
        if (insights.actionItems.isNotEmpty) ...[
          section('Görevler'),
          for (final a in insights.actionItems)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.task_alt),
              title: Text(a.task),
              subtitle: Text([
                meeting.participantById(a.ownerId)?.fullName ?? a.ownerName ?? 'Sorumlu belirtilmedi',
                if (a.due != null) a.due!,
              ].join(' · ')),
              onTap: a.at == null ? null : () => player.playFrom(a.at!),
            ),
        ],
        if (insights.openQuestions.isNotEmpty) ...[
          section('Açık kalan konular'),
          for (final q in insights.openQuestions)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $q')),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Motor: ${insights.engine} · ${formatDateTime(insights.generatedAt)}',
              style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- Bilgi sekmesi

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

    final shares = speakingShares(meeting);
    final spoken = shares.fold<Duration>(Duration.zero, (a, s) => a + s.time);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        row('Başlangıç', formatDateTime(meeting.startedAt ?? meeting.createdAt)),
        row('Süre', formatDuration(meeting.duration)),
        Row(
          children: [
            SizedBox(width: 110, child: Text('Tür', style: theme.textTheme.bodySmall)),
            Expanded(
              child: DropdownButton<MeetingType>(
                value: meeting.type,
                isExpanded: true,
                items: [
                  for (final t in MeetingType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) {
                  if (t == null) return;
                  meeting.type = t;
                  context.read<MeetingController>().save(meeting);
                },
              ),
            ),
          ],
        ),
        row('Toplantı kaydı', meeting.audioPath ?? '-'),
        if (meeting.decisionsAudioPath != null) row('Karar kaydı', meeting.decisionsAudioPath!),
        row('Kopyalandığı yer', meeting.exportPath ?? 'Yalnızca uygulama içinde'),
        if (shares.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Kim ne kadar konuştu', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final s in shares)
            _ShareRow(
              share: s,
              fraction: spoken.inMilliseconds == 0 ? 0 : s.time.inMilliseconds / spoken.inMilliseconds,
              color: speakerColor(meeting.participantIndex(s.participantId)),
            ),
        ],
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
        FilledButton.icon(
          onPressed: () => sendFollowUpEmail(context, meeting),
          icon: const Icon(Icons.forward_to_inbox_outlined),
          label: const Text('Kararları Katılımcılara Gönder'),
        ),
        const SizedBox(height: 8),
        Text(const UnconfiguredEngine().statusText, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.fraction, required this.color});
  final SpeakerShare share;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(share.name)),
              Text(
                '${formatDuration(share.time)} · %${(fraction * 100).round()} · ${share.turns} söz',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
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
          'Mevcut metin, elle yapılan metin düzeltmeleri ve konuşmacı etiketleri değişecek. '
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
