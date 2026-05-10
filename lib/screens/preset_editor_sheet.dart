import 'package:flutter/material.dart';
import '../main.dart';
import '../models/coin.dart';
import '../models/pool_preset.dart';
import '../theme/volt_theme.dart';

class PresetEditorSheet extends StatefulWidget {
  final PoolPreset preset;
  final bool isNew;
  const PresetEditorSheet(
      {super.key, required this.preset, this.isNew = false});
  @override
  State<PresetEditorSheet> createState() => _PresetEditorSheetState();
}

class _PresetEditorSheetState extends State<PresetEditorSheet> {
  late TextEditingController _name, _host, _port, _worker, _pass;
  late WorkerFormat _format;
  late bool _isSolo;
  late Coin _coin;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _name = TextEditingController(text: p.name);
    _host = TextEditingController(text: p.host);
    _port = TextEditingController(text: p.port.toString());
    _worker = TextEditingController(text: p.worker);
    _pass = TextEditingController(text: p.password);
    _format = p.format;
    _isSolo = p.isSolo;
    _coin = p.coin;
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _worker, _pass]) c.dispose();
    super.dispose();
  }

  void _onHostChanged(String val) {
    if (val.isNotEmpty) {
      setState(() {
        _format = PoolPreset.detectFormat(val);
        _isSolo = PoolPreset.detectSolo(val);
      });
    }
  }

  /// Parse full stratum URL pasted by user: stratum+tcp://host:port
  void _parseUrl(String raw) {
    var s = raw
        .trim()
        .replaceAll('stratum+tcp://', '')
        .replaceAll('stratum+ssl://', '')
        .replaceAll('tcp://', '');
    final parts = s.split(':');
    if (parts.isNotEmpty && parts[0].contains('.')) {
      _host.text = parts[0].trim();
      if (parts.length > 1) _port.text = parts[1].trim();
      _onHostChanged(_host.text);
      setState(() {});
    }
  }

  void _save() {
    final host = _host.text.trim();
    if (host.isEmpty || _worker.text.trim().isEmpty) return;
    final updated = widget.preset.copyWith(
      name: _name.text.trim().isEmpty ? 'Preset' : _name.text.trim(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 3333,
      worker: _worker.text.trim(),
      password: _pass.text.trim().isEmpty ? 'x' : _pass.text.trim(),
      format: _format,
      isSolo: _isSolo,
      coin: _coin,
    );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final kc = KratosColors.of(context);
    final color = _isSolo ? KratosTheme.orange : KratosTheme.blue;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // Handle
            Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: kc.line,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Text(widget.isNew ? 'New Pool Preset' : 'Edit Preset',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kc.text))),
              // Solo / Pool chip
              GestureDetector(
                onTap: () => setState(() => _isSolo = !_isSolo),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_isSolo ? Icons.person : Icons.groups,
                        size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(_isSolo ? 'SOLO' : 'POOL',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: color)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            _FieldLabel('COIN', kc),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [Coin.btc, Coin.bch, Coin.sha256Auto].map((coin) {
                final selected = _coin == coin;
                return GestureDetector(
                  onTap: () => setState(() => _coin = coin),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? coin.color.withOpacity(0.14) : kc.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            selected ? coin.color.withOpacity(0.55) : kc.line,
                      ),
                    ),
                    child: Text(coin.ticker,
                        style: TextStyle(
                          color: selected ? coin.color : kc.muted,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Name
            _FieldLabel('PRESET NAME', kc),
            const SizedBox(height: 6),
            _field(_name, 'e.g. Mineshop Solo — Guntis', kc, color),
            const SizedBox(height: 16),

            // Pool URL / Host
            _FieldLabel('POOL ADDRESS', kc),
            const SizedBox(height: 4),
            Text('Paste a full stratum URL or just the hostname',
                style: TextStyle(fontSize: 10, color: kc.muted)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _field(_host, 'solo.mineshop.eu', kc, color,
                      onChanged: _onHostChanged)),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: _field(_port, '3333', kc, color,
                    keyboardType: TextInputType.number),
              ),
            ]),
            TextButton.icon(
              onPressed: () async {
                final v = await showDialog<String>(
                  context: context,
                  builder: (ctx) {
                    final c = TextEditingController();
                    return AlertDialog(
                      backgroundColor: kc.surface,
                      title: Text('Paste stratum URL',
                          style: TextStyle(color: kc.text)),
                      content: TextField(
                        controller: c,
                        autofocus: true,
                        style: TextStyle(color: kc.text, fontFamily: 'Courier'),
                        decoration: InputDecoration(
                          hintText: 'stratum+tcp://solo.mineshop.eu:3333',
                          hintStyle: TextStyle(color: kc.muted),
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, c.text),
                            child: const Text('Parse')),
                      ],
                    );
                  },
                );
                if (v != null && v.isNotEmpty) _parseUrl(v);
              },
              icon: Icon(Icons.content_paste, size: 14, color: kc.muted),
              label: Text('Paste full stratum URL',
                  style: TextStyle(fontSize: 11, color: kc.muted)),
            ),
            const SizedBox(height: 16),

            // Worker
            _FieldLabel('WORKER / USERNAME', kc),
            const SizedBox(height: 4),
            Text(
                _format.hint +
                    '\nTip: use {miner} for auto worker name per miner',
                style: TextStyle(fontSize: 10, color: kc.muted, height: 1.4)),
            const SizedBox(height: 6),
            _field(_worker, 'bc1q... or bc1q....{miner}', kc, color),
            const SizedBox(height: 8),

            // Format chips
            Wrap(
                spacing: 6,
                children: WorkerFormat.values.map((f) {
                  final sel = _format == f;
                  return GestureDetector(
                    onTap: () => setState(() => _format = f),
                    child: Chip(
                      label: Text(f.label,
                          style: TextStyle(
                              fontSize: 10,
                              color: sel ? color : kc.muted,
                              fontWeight:
                                  sel ? FontWeight.w800 : FontWeight.normal)),
                      backgroundColor: sel ? color.withOpacity(0.12) : kc.bg,
                      side: BorderSide(
                          color: sel ? color.withOpacity(0.4) : kc.line),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList()),
            const SizedBox(height: 16),

            // Password
            _FieldLabel('PASSWORD (optional)', kc),
            const SizedBox(height: 6),
            _field(_pass, 'x (default)', kc, color),
            const SizedBox(height: 24),

            // Save
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed:
                    _host.text.trim().isEmpty || _worker.text.trim().isEmpty
                        ? null
                        : _save,
                child: Text(
                  widget.isNew ? 'Save Preset' : 'Update Preset',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
          TextEditingController c, String hint, KratosPalette kc, Color accent,
          {Function(String)? onChanged, TextInputType? keyboardType}) =>
      TextField(
        controller: c,
        autocorrect: false,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(color: kc.text, fontFamily: 'Courier', fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: kc.muted, fontSize: 12),
          filled: true,
          fillColor: kc.bg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kc.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kc.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: accent, width: 1.5)),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final KratosPalette kc;
  const _FieldLabel(this.text, this.kc);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: kc.muted,
          letterSpacing: 1.5));
}
