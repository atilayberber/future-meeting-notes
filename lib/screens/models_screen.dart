import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../asr/model_catalog.dart';
import '../asr/model_manager.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';

/// Konuşma tanıma modelini seçme, indirme ve silme.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ModelManager>().refresh();
  }

  Future<void> _confirmDownload(ModelManager mm, AsrModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.title} indirilsin mi?'),
        content: Text(
          'Yaklaşık ${m.approxSize.replaceAll('~', '')} indirilecek. Wi-Fi önerilir. '
          'Bu yalnızca bir kez yapılır; sonrasında konuşma tanıma internet olmadan çalışır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İndir')),
        ],
      ),
    );
    if (ok == true) await mm.download(m);
  }

  @override
  Widget build(BuildContext context) {
    final mm = context.watch<ModelManager>();
    final settings = context.watch<SettingsService>();
    final active = mm.activeModel;

    return Scaffold(
      appBar: AppBar(title: const Text('Konuşma Tanıma Modeli')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PhaseNote(
            icon: Icons.lock_outline,
            text: 'Model telefona bir kez indirilir. Toplantı sesleri hiçbir zaman cihaz '
                'dışına gönderilmez; yazıya dökme tamamen telefonda yapılır.',
          ),
          if (mm.lastError != null) ...[
            const SizedBox(height: 12),
            Text(mm.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          for (final m in kAsrModels)
            _ModelCard(
              model: m,
              selected: m.id == active.id,
              installed: mm.isInstalledCached(m),
              download: mm.downloadOf(m),
              onSelect: () => settings.setAsrModelId(m.id),
              onDownload: () => _confirmDownload(mm, m),
              onCancel: () => mm.cancel(m),
              onDelete: () => mm.delete(m),
            ),
          const SizedBox(height: 8),
          const PhaseNote(
            text: 'Hangi modelin sizin toplantılarınızda daha iyi olduğunu görmek için: '
                'bir toplantıyı kaydedin, sonra toplantının "Bilgi" sekmesinden '
                '"Kaydı yeniden metne dök" ile farklı modellerle deneyin. Her modelin '
                'metni toplantı klasörüne ayrı dosya olarak kaydedilir.',
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.selected,
    required this.installed,
    required this.download,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final AsrModel model;
  final bool selected;
  final bool installed;
  final DownloadState? download;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = download;
    return Card(
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(model.title, style: theme.textTheme.titleMedium)),
                Text(model.approxSize, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(model.description),
            const SizedBox(height: 12),
            if (d != null) ...[
              LinearProgressIndicator(value: d.fraction),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.total > 0
                          ? '${_mb(d.received)} / ${_mb(d.total)}'
                          : '${_mb(d.received)} indirildi',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(onPressed: onCancel, child: const Text('İptal')),
                ],
              ),
            ] else
              Wrap(
                spacing: 8,
                children: [
                  if (!installed)
                    FilledButton.tonalIcon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('İndir'),
                    )
                  else ...[
                    const Chip(
                      avatar: Icon(Icons.check_circle, color: Colors.green, size: 18),
                      label: Text('İndirildi'),
                    ),
                    TextButton(onPressed: onDelete, child: const Text('Sil')),
                  ],
                  if (!selected)
                    OutlinedButton(onPressed: onSelect, child: const Text('Bunu kullan')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
