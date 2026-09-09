import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/api_request_record.dart';

/// Developer request inspector: shows a *sanitized* request/response pair.
/// Secrets are masked before this widget ever sees them, and the copy button
/// only copies masked content.
void showRequestInspectorSheet(BuildContext context, ApiRequestRecord record) {
  final content = record.toText();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Request inspector',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Copy (sanitized)'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                            content: Text('Sanitized request copied.')));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace', height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Authorizations, API keys and secret headers are masked here.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ),
  );
}
