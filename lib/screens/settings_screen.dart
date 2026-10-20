import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../asr/model_manager.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'models_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickFolder(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Toplantı kayıtlarının kopyalanacağı klasör',
    );
    if (path != null) await settings.setExportDir(path);
  }

  Future<void> _editDomain(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final input = TextEditingController(text: settings.companyDomain);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şirket e-posta alan adı'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'bicen.com.tr'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, input.text), child: const Text('Kaydet')),
        ],
      ),
    );
    input.dispose();
    if (result != null) await settings.setCompanyDomain(result.replaceAll('@', ''));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          const _Header('Kayıt'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Kayıt klasörü'),
            subtitle: Text(s.exportDir ?? 'Uygulama içi (varsayılan)'),
            onTap: () => _pickFolder(context),
            trailing: s.exportDir == null
                ? null
                : IconButton(
                    tooltip: 'Varsayılana dön',
                    icon: const Icon(Icons.clear),
                    onPressed: () => s.setExportDir(null),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PhaseNote(
              text: 'Kayıtlar önce uygulama içine yazılır, toplantı tamamlanınca seçilen '
                  'klasöre kopyalanır. iOS\'ta kayıtlar Dosyalar uygulamasında '
                  '"Future Meeting Notes" altında da görünür.',
            ),
          ),
          const _Header('Katılımcı kaydı'),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('Şirket e-posta alan adı'),
            subtitle: Text(s.companyDomain.isEmpty
                ? 'Tanımlı değil'
                : '@${s.companyDomain} (söylenmezse otomatik eklenir)'),
            onTap: () => _editDomain(context),
          ),
          const _Header('Konuşma tanıma'),
          Builder(builder: (context) {
            final mm = context.watch<ModelManager>();
            final m = mm.activeModel;
            return ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Konuşma tanıma modeli'),
              subtitle: Text('${m.title} · ${mm.isInstalledCached(m) ? 'indirildi' : 'indirilmedi'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ModelsScreen()),
              ),
            );
          }),
          const _Header('Hakkında'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Sürüm'),
            subtitle: Text('0.2.0 · Faz 1b (cihaz üzerinde konuşma tanıma)'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
