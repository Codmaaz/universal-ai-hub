import 'package:flutter/material.dart';

import '../../../adapters/ai_provider_adapter.dart';
import '../widgets/inspector_sheet.dart';

/// Shows the outcome of “Test Connection”, including the request description.
void showConnectionResultDialog(
  BuildContext context,
  ConnectionTestResult result, {
  String? providerName,
}) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            result.ok ? Icons.check_circle : Icons.cancel,
            color: result.ok ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Connection test')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.summary),
            if (providerName != null) ...[
              const SizedBox(height: 12),
              _Row(label: 'Provider', value: providerName),
            ],
            const SizedBox(height: 6),
            _Row(label: 'Response time', value: '${result.durationMs ?? '—'} ms'),
            const SizedBox(height: 12),
            Text('What was sent',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Text(result.detail, style: TextStyle(fontSize: 12.5)),
            if (result.requestRecord != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.terminal, size: 18),
                  label: const Text('View request details'),
                  onPressed: () => showRequestInspectorSheet(
                      ctx, result.requestRecord!),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
