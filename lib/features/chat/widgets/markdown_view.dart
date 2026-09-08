import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders assistant markdown with fenced-code syntax highlighting and copy
/// buttons. Network-based widgets (images, remote content) are blocked.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.fontSize});

  final String data;
  final double? fontSize;

  /// Maps common fenced-language labels to highlight.js language ids.
  static String languageIdFor(String label) {
    final l = label.trim().toLowerCase();
    const aliases = <String, String>{
      'py': 'python',
      'js': 'javascript',
      'ts': 'typescript',
      'sh': 'bash',
      'shell': 'bash',
      'console': 'bash',
      'c++': 'cpp',
      'html': 'xml',
      'c#': 'cs',
      'yml': 'yaml',
      'md': 'markdown',
      'text': 'plaintext',
      'txt': 'plaintext',
    };
    return aliases[l] ?? l;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MarkdownBody(
      data: data,
      selectable: true,
      builders: {'pre': _PreBlockBuilder()},
      sizedImageBuilder: (_) => const SizedBox.shrink(),
      onTapLink: (text, href, title) {
        if (href != null && Uri.tryParse(href)?.hasScheme == true) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                content: Text('Link blocked in this preview: $href')));
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize),
        h1: TextStyle(
            fontSize: (fontSize ?? 15) + 6, fontWeight: FontWeight.w700),
        h2: TextStyle(
            fontSize: (fontSize ?? 15) + 4, fontWeight: FontWeight.w700),
        h3: TextStyle(
            fontSize: (fontSize ?? 15) + 2, fontWeight: FontWeight.w600),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: (fontSize ?? 14) - 1,
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        ),
        codeblockDecoration: const BoxDecoration(color: Colors.transparent),
        blockquote: TextStyle(
          color: cs.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: cs.primary, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.all(10),
        listIndent: 18,
        tableHead: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        tableBorder: TableBorder.all(color: cs.outlineVariant),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        tableColumnWidth: const FlexColumnWidth(),
      ),
    );
  }
}

class _PreBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    String rawLang = '';
    for (final child in (element.children ?? const <md.Node>[])) {
      if (child is md.Element && child.tag == 'code') {
        rawLang = (child.attributes['class'] ?? '')
            .replaceFirst(RegExp(r'^language-'), '');
        break;
      }
    }
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return CodeBlock(
      code: code,
      languageId: MarkdownView.languageIdFor(rawLang),
      languageLabel: rawLang,
    );
  }

  @override
  bool isBlockElement() => true;
}

/// Styled horizontally scrollable code block with copy button.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    required this.languageId,
    required this.languageLabel,
  });

  final String code;
  final String languageId;
  final String languageLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.55),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    languageLabel.isEmpty ? 'code' : languageLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              code,
              language: languageId.isEmpty ? 'plaintext' : languageId,
              theme: isDark ? atomOneDarkTheme : githubTheme,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
