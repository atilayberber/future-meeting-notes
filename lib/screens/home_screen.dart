import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meeting.dart';
import '../services/storage_service.dart';
import '../state/meeting_controller.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'preparation_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Meeting>> _meetings;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _meetings = context.read<StorageService>().listMeetings();
  }

  Future<void> _startPreparation() async {
    context.read<MeetingController>().newMeeting();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PreparationScreen()),
    );
    if (mounted) setState(_reload);
  }

  int _seenCompleted = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bir toplantı tamamlandığında geçmiş listesini yenile.
    final completed = context.select<MeetingController, int>((c) => c.completedCount);
    if (completed != _seenCompleted) {
      _seenCompleted = completed;
      _reload();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Future Meeting Notes'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _meetings;
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Yüz yüze toplantılarınızı kişi bazında kayda alın.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Katılımcılar toplantı öncesinde sesleriyle tanıtılır; toplantıda söylenen '
              'her söz kimin söylediğiyle birlikte yazıya dökülür.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            PrimaryActionButton(
              label: 'Toplantı Öncesi Hazırlığı Başlat',
              icon: Icons.group_add_outlined,
              onPressed: _startPreparation,
            ),
            const SizedBox(height: 32),
            Text('Geçmiş Toplantılar', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<Meeting>>(
              future: _meetings,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final list = snap.data ?? const <Meeting>[];
                if (list.isEmpty) {
                  return const PhaseNote(text: 'Henüz kayıtlı toplantı yok.');
                }
                return Column(
                  children: [
                    for (final m in list)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.record_voice_over_outlined),
                          title: Text(m.title),
                          subtitle: Text(
                            '${formatDateTime(m.startedAt ?? m.createdAt)} · '
                            '${formatDuration(m.duration)} · '
                            '${m.participants.length} katılımcı',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ResultScreen(meeting: m)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
