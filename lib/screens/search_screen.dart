import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meeting.dart';
import '../services/meeting_search.dart';
import '../services/storage_service.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Tüm toplantılarda arama: "kim, ne zaman, ne dedi?" (Recco: global arama).
/// Arama tamamen cihazda yapılır.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Meeting>? _meetings;
  List<SearchHit> _hits = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    context.read<StorageService>().listMeetings().then((list) {
      if (mounted) setState(() => _meetings = list);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final list = _meetings;
      if (list == null || !mounted) return;
      setState(() => _hits = searchMeetings(list, q));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _ctrl.text;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Tüm toplantılarda ara',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _ctrl.clear();
                _hits = const [];
              }),
            ),
        ],
      ),
      body: _meetings == null
          ? const Center(child: CircularProgressIndicator())
          : query.trim().isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: PhaseNote(
                    icon: Icons.manage_search,
                    text: 'Bir kelime ya da kişi adı yazın. Örnek: "bütçe", "Ahmet teslim", '
                        '"kampanya fiyat". Türkçe karakter yazmasanız da bulunur.',
                  ),
                )
              : _hits.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: PhaseNote(icon: Icons.search_off, text: 'Sonuç yok.'),
                    )
                  : ListView.separated(
                      itemCount: _hits.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final meetings = _hits.map((h) => h.meeting.id).toSet().length;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Text('${_hits.length} sonuç · $meetings toplantı',
                                style: theme.textTheme.bodySmall),
                          );
                        }
                        final h = _hits[i - 1];
                        final idx = h.meeting.participantIndex(h.segment.speakerId);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: speakerColor(idx),
                            foregroundColor: Colors.white,
                            child: Text(h.meeting.participantById(h.segment.speakerId)?.initials ?? '?'),
                          ),
                          title: Text(h.segment.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${h.speakerName} · ${h.meeting.title} · '
                            '${formatDateTime(h.meeting.startedAt ?? h.meeting.createdAt)} · '
                            '${formatDuration(h.segment.start)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ResultScreen(meeting: h.meeting, initialQuery: query),
                          )),
                        );
                      },
                    ),
    );
  }
}
