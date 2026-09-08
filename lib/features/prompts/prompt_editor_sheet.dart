import 'package:flutter/material.dart';

import '../../core/models/system_prompt.dart';

/// Create/Edit dialog for a system prompt.
/// Returns a (title, content) record or null when dismissed.
Future<({String title, String content})?> showPromptEditor(
  BuildContext context, {
  SystemPrompt? existing,
}) {
  return showModalBottomSheet<({String title, String content})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PromptEditorSheet(existing: existing),
  );
}

class _PromptEditorSheet extends StatefulWidget {
  const _PromptEditorSheet({this.existing});

  final SystemPrompt? existing;

  @override
  State<_PromptEditorSheet> createState() => _PromptEditorSheetState();
}

class _PromptEditorSheetState extends State<_PromptEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.existing?.content ?? '');

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'New system prompt' : 'Edit prompt',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Coding Assistant',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                hintText:
                    'You are a … Keep it clear and specific. This text is '
                    'sent as the system prompt with each request.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, (
                  title: _title.text.trim(),
                  content: _content.text.trim(),
                ));
              },
              child: const Text('Save prompt'),
            ),
          ],
        ),
      ),
    );
  }
}
