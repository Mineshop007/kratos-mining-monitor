import 'package:flutter/material.dart';
import '../main.dart';
import 'package:uuid/uuid.dart';
import '../models/pool_preset.dart';
import '../services/pool_preset_service.dart';
import '../theme/volt_theme.dart';
import '../widgets/kratos_app_bar.dart';
import 'preset_editor_sheet.dart';

class PoolPresetsScreen extends StatefulWidget {
  const PoolPresetsScreen({super.key});
  @override
  State<PoolPresetsScreen> createState() => _PoolPresetsScreenState();
}

class _PoolPresetsScreenState extends State<PoolPresetsScreen> {
  List<PoolPreset> _presets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await PoolPresetService.instance.loadAll();
    if (mounted) setState(() { _presets = p; _loading = false; });
  }

  Future<void> _addPreset() async {
    final preset = await showModalBottomSheet<PoolPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PresetEditorSheet(
        preset: PoolPreset(
          id: const Uuid().v4(),
          name: 'Preset ${_presets.length + 1}',
          host: '',
          port: 3333,
          worker: '',
          createdAt: DateTime.now(),
        ),
        isNew: true,
      ),
    );
    if (preset != null) {
      await PoolPresetService.instance.save(preset);
      await _load();
    }
  }

  Future<void> _editPreset(PoolPreset preset) async {
    final updated = await showModalBottomSheet<PoolPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PresetEditorSheet(preset: preset),
    );
    if (updated != null) {
      await PoolPresetService.instance.save(updated);
      await _load();
    }
  }

  Future<void> _deletePreset(PoolPreset preset) async {
    await PoolPresetService.instance.delete(preset.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    return Scaffold(
      backgroundColor: kc.bg,
      appBar: KratosAppBar(
        title: const Text('Pool Presets'),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: kc.accent),
            onPressed: _addPreset,
            tooltip: 'New preset',
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kc.accent))
          : _presets.isEmpty
              ? _EmptyState(kc: kc, onAdd: _addPreset)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _presets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _PresetCard(
                    preset: _presets[i],
                    kc: kc,
                    onEdit: () => _editPreset(_presets[i]),
                    onDelete: () => _deletePreset(_presets[i]),
                  ),
                ),
      floatingActionButton: _presets.isEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: kc.accent,
              foregroundColor: Colors.black,
              onPressed: _addPreset,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final PoolPreset preset;
  final KratosPalette kc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PresetCard({required this.preset, required this.kc,
      required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = preset.isSolo ? KratosTheme.orange : KratosTheme.blue;
    return Dismissible(
      key: Key(preset.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                preset.isSolo ? 'SOLO' : 'POOL',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                    color: color, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.name, style: TextStyle(
                    fontWeight: FontWeight.w700, color: kc.text)),
                const SizedBox(height: 2),
                Text('${preset.host}:${preset.port}',
                    style: TextStyle(fontSize: 12, color: kc.muted,
                        fontFamily: 'Courier')),
                if (preset.worker.isNotEmpty)
                  Text(preset.worker,
                      style: TextStyle(fontSize: 11, color: kc.muted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            Icon(Icons.chevron_right, color: kc.muted, size: 18),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final KratosPalette kc;
  final VoidCallback onAdd;
  const _EmptyState({required this.kc, required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.dns_outlined, size: 56, color: kc.muted.withOpacity(0.4)),
      const SizedBox(height: 16),
      Text('No presets yet', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, color: kc.muted)),
      const SizedBox(height: 8),
      Text('Save pool configs and apply to any miner\nwith one tap.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: kc.muted, height: 1.4)),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add First Preset'),
      ),
    ],
  ));
}
