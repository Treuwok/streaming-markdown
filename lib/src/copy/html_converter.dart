part of '../render/view.dart';

String _selectedMarkdownToHtml(
  String markdown, {
  required bool allowUnclosedInlineDelimiters,
}) {
  final String normalized = markdown.replaceAll('\r', '').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
    normalized,
    backend: MarkdownSyncParserBackend.dart,
  );
  final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
    nodes: result.blocks,
    allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
  );
  final List<MarkdownRenderNode> blocks = view._collectRenderableBlocks(
    result.blocks,
  );
  final Map<String, String> linkReferences = view._extractLinkReferences(
    result.blocks,
  );
  final Map<String, int> footnoteNumbers = view._extractFootnoteNumbers(
    result.blocks,
  );
  final _MarkdownHtmlSelectionConverter converter =
      _MarkdownHtmlSelectionConverter(
    view: view,
    blocks: blocks,
    linkReferences: linkReferences,
    footnoteNumbers: footnoteNumbers,
  );
  return converter.convert();
}

class _MarkdownHtmlSelectionConverter {
  const _MarkdownHtmlSelectionConverter({
    required this.view,
    required this.blocks,
    required this.linkReferences,
    required this.footnoteNumbers,
  });

  final StreamingMarkdownRenderView view;
  final List<MarkdownRenderNode> blocks;
  final Map<String, String> linkReferences;
  final Map<String, int> footnoteNumbers;

  String convert() {
    final StringBuffer out = StringBuffer();
    for (final MarkdownRenderNode block in blocks) {
      final String html = _convertBlock(block);
      if (html.isEmpty) {
        continue;
      }
      out.write(html);
    }
    return out.toString();
  }

  String _convertBlock(MarkdownRenderNode block) {
    final String raw = view._normalizedRaw(block.raw);
    switch (block.type) {
      case 'atx_heading':
      case 'setext_heading':
        final int level = view._headingLevelForNode(block).clamp(1, 6);
        return '<h$level>${_convertInline(view._headingText(block))}</h$level>';
      case 'paragraph':
        final _ParsedTable? table = view._parseMarkdownTable(
          raw,
          allowLooseWithoutDelimiter: true,
          minLooseRowsWithoutDelimiter: 2,
        );
        if (table != null) {
          return _convertTable(table);
        }
        return '<p>${_convertInline(view._paragraphText(block).replaceAll('\n', ' '))}</p>';
      case 'list':
      case 'list_item':
        return _convertList(block);
      case 'block_quote':
        return '<blockquote>${_convertQuotedLines(view._quoteText(block))}</blockquote>';
      case 'fenced_code_block':
      case 'indented_code_block':
        final String language = view._codeLanguage(raw);
        final String classAttr = language.isEmpty
            ? ''
            : ' class="language-${_escapeHtmlAttribute(language)}"';
        return '<pre><code$classAttr>${_escapeHtml(view._codeText(block))}</code></pre>';
      case 'thematic_break':
        return '<hr />';
      case 'html_block':
        return raw;
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
        final _ParsedTable? table = view._parseMarkdownTable(
          raw,
          allowLooseWithoutDelimiter: true,
          minLooseRowsWithoutDelimiter: 2,
        );
        if (table != null) {
          return _convertTable(table);
        }
        return '<p>${_convertInline(view._contentOrRaw(block))}</p>';
      case 'pipe_table_delimiter_row':
        return '';
      case 'link_reference_definition':
      case 'footnote_definition':
        return '<p>${_escapeHtml(view._contentOrRaw(block))}</p>';
      default:
        return '<p>${_convertInline(view._contentOrRaw(block))}</p>';
    }
  }

  String _convertQuotedLines(String text) {
    final List<String> lines = text
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '';
    }
    return '<p>${lines.map(_convertInline).join('<br />')}</p>';
  }

  String _convertList(MarkdownRenderNode block) {
    final _ParsedList parsed = view._parseListNode(block);
    if (parsed.items.isEmpty) {
      return '<p>${_escapeHtml(view._contentOrRaw(block))}</p>';
    }
    final StringBuffer out = StringBuffer();
    int index = 0;
    while (index < parsed.items.length) {
      final _ListHtmlResult result = _convertListGroup(
        parsed.items,
        start: index,
        level: parsed.items[index].level,
        ordered: parsed.items[index].ordered,
      );
      out.write(result.html);
      index = result.nextIndex;
    }
    return out.toString();
  }

  _ListHtmlResult _convertListGroup(
    List<_ParsedListItem> items, {
    required int start,
    required int level,
    required bool ordered,
  }) {
    final String tag = ordered ? 'ol' : 'ul';
    final StringBuffer out = StringBuffer('<$tag>');
    int index = start;
    while (index < items.length) {
      final _ParsedListItem item = items[index];
      if (item.level < level) {
        break;
      }
      if (item.level > level || item.ordered != ordered) {
        break;
      }

      index += 1;
      final String prefix = item.taskState == null
          ? ''
          : item.taskState!
              ? '[x] '
              : '[ ] ';
      final StringBuffer itemHtml = StringBuffer(
        _convertInline('$prefix${item.text}'),
      );

      while (index < items.length && items[index].level > level) {
        final _ListHtmlResult nested = _convertListGroup(
          items,
          start: index,
          level: items[index].level,
          ordered: items[index].ordered,
        );
        itemHtml.write(nested.html);
        index = nested.nextIndex;
      }

      out.write('<li>$itemHtml</li>');
    }
    out.write('</$tag>');
    return _ListHtmlResult(html: out.toString(), nextIndex: index);
  }

  String _convertTable(_ParsedTable table) {
    final StringBuffer out = StringBuffer('<table>');
    if (table.headers.isNotEmpty) {
      out.write('<thead><tr>');
      for (final String header in table.headers) {
        out.write('<th>${_convertInline(header)}</th>');
      }
      out.write('</tr></thead>');
    }
    if (table.rows.isNotEmpty) {
      out.write('<tbody>');
      for (final List<String> row in table.rows) {
        out.write('<tr>');
        for (final String cell in row) {
          out.write('<td>${_convertInline(cell)}</td>');
        }
        out.write('</tr>');
      }
      out.write('</tbody>');
    }
    out.write('</table>');
    return out.toString();
  }

  String _convertInline(String markdown) {
    final List<_InlineToken> tokens = view
        ._inlineParserFor(linkReferences)
        .tokenize(markdown.replaceAll('\r', ''));
    final StringBuffer out = StringBuffer();
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        final String src = _escapeHtmlAttribute(token.imageUrl!);
        final String alt = _escapeHtmlAttribute(token.altText);
        out.write('<img src="$src" alt="$alt" />');
        continue;
      }
      if (token.isFootnoteReference) {
        final String id = token.footnoteReferenceId!;
        final int? number = _footnoteNumberForId(footnoteNumbers, id);
        out.write('<sup>${_escapeHtml((number ?? id).toString())}</sup>');
        continue;
      }
      if (token.isLatex) {
        out.write(_escapeHtml(token.sourceMarkdown));
        continue;
      }

      String content = _escapeHtml(token.text);
      if (token.style.code) {
        content = '<code>$content</code>';
      }
      if (token.style.strikethrough) {
        content = '<s>$content</s>';
      }
      if (token.style.italic) {
        content = '<em>$content</em>';
      }
      if (token.style.bold) {
        content = '<strong>$content</strong>';
      }
      final String? url = token.linkUrl;
      if (url != null && url.isNotEmpty) {
        content = '<a href="${_escapeHtmlAttribute(url)}">$content</a>';
      }
      out.write(content);
    }
    return out.toString();
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _escapeHtmlAttribute(String value) {
    return _escapeHtml(value).replaceAll('\n', '&#10;');
  }
}

class _ListHtmlResult {
  const _ListHtmlResult({
    required this.html,
    required this.nextIndex,
  });

  final String html;
  final int nextIndex;
}
