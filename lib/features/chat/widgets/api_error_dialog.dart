import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';

/// Shows a user-friendly error with an expandable “Technical details” block.
/// The details have already been sanitized upstream — no keys can appear.
void showApiErrorDialog(BuildContext context, ApiException error) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.error_outline, color: theme.colorScheme.error, size: 34),
      title: Text(error.kind.heading),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error.message),
            if (error.tip != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tip: ${error.tip}',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Technical details'),
              childrenPadding: const EdgeInsets.only(top: 4),
              children: [
                _DetailRow(label: 'Error type', value: error.kind.heading),
                if (error.providerName != null)
                  _DetailRow(label: 'Provider', value: error.providerName!),
                if (error.httpStatus != null)
                  _DetailRow(label: 'HTTP status', value: '${error.httpStatus}'),
                if (error.sanitizedUrl != null)
                  _DetailRow(label: 'URL', value: error.sanitizedUrl!),
                if (error.sanitizedBody != null && error.sanitizedBody!.isNotEmpty)
                  _DetailRow(label: 'Response body', value: error.sanitizedBody!, multiline: true),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            maxLines: multiline ? null : 3,
            style: TextStyle(
              fontSize: 12,
              fontFamily: multiline ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
