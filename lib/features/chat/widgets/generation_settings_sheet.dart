import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/generation_settings.dart';
import '../../../core/models/provider.dart';
import '../../../core/models/types.dart';

/// Opens the advanced generation-settings panel. Returns the new settings or
/// null when cancelled. Only parameters the provider supports are shown.
Future<GenerationSettings?> showGenerationSettingsSheet(
  BuildContext context, {
  required AIProvider provider,
  required GenerationSettings settings,
}) {
  final caps = provider.capabilities;
  return showModalBottomSheet<GenerationSettings>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _Sheet(
      caps: caps,
      initial: settings,
      providerName: provider.name,
    ),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.caps,
    required this.initial,
    required this.providerName,
  });

  final ProviderCapabilities caps;
  final GenerationSettings initial;
  final String providerName;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late double _temperature;
  late int _maxTokens;
  late double _topP;
  late bool _temperatureSet;
  late bool _maxTokensSet;
  late bool _topPSet;
  late bool _freqEnabled;
  late double _freq;
  late bool _presenceEnabled;
  late double _presence;
  late final TextEditingController _stopsCtrl;
  late final TextEditingController _seedCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _temperature = init.temperature ?? 0.7;
    _maxTokens = init.maxTokens ?? 2048;
    _topP = init.topP ?? 1.0;
    _temperatureSet = init.temperature != null;
    _maxTokensSet = init.maxTokens != null;
    _topPSet = init.topP != null;
    _freqEnabled = init.frequencyPenalty != null;
    _freq = init.frequencyPenalty ?? 0.0;
    _presenceEnabled = init.presencePenalty != null;
    _presence = init.presencePenalty ?? 0.0;
    _stopsCtrl = TextEditingController(
        text: init.stopSequences.isEmpty
            ? ''
            : init.stopSequences.join(','));
    _seedCtrl =
        TextEditingController(text: init.seed?.toString() ?? '');
  }

  @override
  void dispose() {
    _stopsCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  GenerationSettings _result() {
    final stops = _stopsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final seed = int.tryParse(_seedCtrl.text.trim());
    return GenerationSettings(
      temperature: _temperatureSet && widget.caps.supportsTemperature
          ? _temperature
          : null,
      maxTokens: _maxTokensSet && widget.caps.supportsMaxTokens
          ? _maxTokens
          : null,
      topP: _topPSet && widget.caps.supportsTopP ? _topP : null,
      frequencyPenalty: _freqEnabled && widget.caps.supportsFrequencyPenalty
          ? _freq
          : null,
      presencePenalty: _presenceEnabled && widget.caps.supportsPresencePenalty
          ? _presence
          : null,
      stopSequences:
          widget.caps.supportsStopSequences ? stops : const [],
      seed: widget.caps.supportsSeed ? seed : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = widget.caps;
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generation settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Only parameters supported by ${widget.providerName} are '
                'shown below.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final preset in GenerationPresets.presets)
                  ActionChip(
                    label: Text(preset.name),
                    onPressed: () =>
                        Navigator.pop(context, _filterByCaps(preset.settings)),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (caps.supportsTemperature) ...[
              _SwitchRow(
                title: 'Temperature',
                subtitle: 'Creativity / randomness',
                enabled: _temperatureSet,
                onChanged: (v) => setState(() => _temperatureSet = v),
              ),
              if (_temperatureSet) _SliderRow(
                value: _temperature,
                min: 0,
                max: 2,
                label: '${_temperature.toStringAsFixed(2)}',
                onChanged: (v) => setState(() => _temperature = v),
              ),
              const SizedBox(height: 8),
            ],
            if (caps.supportsMaxTokens) ...[
              _SwitchRow(
                title: 'Maximum tokens',
                subtitle: '$_maxTokens tokens',
                enabled: _maxTokensSet,
                onChanged: (v) => setState(() => _maxTokensSet = v),
              ),
              if (_maxTokensSet)
                Slider(
                  value: _maxTokens.toDouble().clamp(16, 128000),
                  min: 16,
                  max: 128000,
                  divisions: 499,
                  label: '$_maxTokens',
                  onChanged: (v) => setState(() => _maxTokens = v.round()),
                ),
              const SizedBox(height: 8),
            ],
            if (caps.supportsTopP) ...[
              _SwitchRow(
                title: 'Top P',
                subtitle: 'Nucleus sampling',
                enabled: _topPSet,
                onChanged: (v) => setState(() => _topPSet = v),
              ),
              if (_topPSet) _SliderRow(
                value: _topP,
                min: 0,
                max: 1,
                label: _topP.toStringAsFixed(2),
                onChanged: (v) => setState(() => _topP = v),
              ),
              const SizedBox(height: 8),
            ],
            if (caps.supportsFrequencyPenalty) ...[
              _SwitchRow(
                title: 'Frequency penalty',
                subtitle: 'Repetition dampening',
                enabled: _freqEnabled,
                onChanged: (v) => setState(() => _freqEnabled = v),
              ),
              if (_freqEnabled)
                _SliderRow(
                    value: _freq,
                    min: -2,
                    max: 2,
                    label: _freq.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _freq = v)),
              const SizedBox(height: 8),
            ],
            if (caps.supportsPresencePenalty) ...[
              _SwitchRow(
                title: 'Presence penalty',
                subtitle: 'Topic diversity',
                enabled: _presenceEnabled,
                onChanged: (v) => setState(() => _presenceEnabled = v),
              ),
              if (_presenceEnabled)
                _SliderRow(
                    value: _presence,
                    min: -2,
                    max: 2,
                    label: _presence.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _presence = v)),
              const SizedBox(height: 8),
            ],
            if (caps.supportsStopSequences) ...[
              TextField(
                controller: _stopsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Stop sequences',
                  hintText: 'Comma separated, e.g. END,###',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (caps.supportsSeed) ...[
              TextField(
                controller: _seedCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Seed',
                  hintText: 'Optional integer',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _result()),
                child: const Text('Apply'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Drops parameters not supported by the current provider's capabilities.
  GenerationSettings _filterByCaps(GenerationSettings s) {
    final caps = widget.caps;
    return GenerationSettings(
      temperature: caps.supportsTemperature ? s.temperature : null,
      maxTokens: caps.supportsMaxTokens ? s.maxTokens : null,
      topP: caps.supportsTopP ? s.topP : null,
      frequencyPenalty:
          caps.supportsFrequencyPenalty ? s.frequencyPenalty : null,
      presencePenalty:
          caps.supportsPresencePenalty ? s.presencePenalty : null,
      stopSequences: caps.supportsStopSequences ? s.stopSequences : const [],
      seed: caps.supportsSeed ? s.seed : null,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: onChanged,
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Slider(value: value.clamp(min, max), min: min, max: max,
            onChanged: onChanged),
      ),
      SizedBox(
        width: 52,
        child: Text(label, textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12)),
      ),
    ]);
  }
}
