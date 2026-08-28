part of '../view.dart';

extension _StreamingMarkdownSelectionInlineBuilder
    on StreamingMarkdownRenderView {
  _MarkdownSelectionSegment _inlineSelectionSegment(
    String text, {
    required String markdownText,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
    bool preserveBlockMarkdownOnPartial = false,
  }) {
    final String normalized = text.replaceAll('\r', '');
    final _InlineParseResult scan = _inlineParserFor(
      linkReferences,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
    ).scan(normalized);
    final List<_InlineToken> tokens = scan.tokens;
    final List<_MarkdownSelectionPiece> pieces = <_MarkdownSelectionPiece>[];
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        pieces.add(
          _MarkdownSelectionPiece(
            plainText:
                token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]',
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      if (token.isFootnoteReference) {
        final int? number = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        pieces.add(
          _MarkdownSelectionPiece(
            plainText: number?.toString() ?? token.footnoteReferenceId!,
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      if (token.isLatex) {
        pieces.add(
          _MarkdownSelectionPiece(
            plainText: token.sourceMarkdown,
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      pieces.add(
        _MarkdownSelectionPiece(
          plainText: token.text,
          markdownText: _semanticMarkdownForInlineToken(token),
        ),
      );
    }
    return _MarkdownSelectionSegment(
      pieces: pieces,
      // Selection is built from the same scan as the paint, so it has to honour
      // the same boundary: copying a reply must not hand back a destination the
      // screen deliberately never showed.
      // Hidden ranges count as much as a boundary does. A completed tag
      // leaves `withheldFrom` null while recording a hidden range, and this
      // branch then kept the raw source — so selecting the whole paragraph
      // copied the `href` that was never drawn.
      fallbackMarkdownText:
          scan.withheldFrom == null && scan.hiddenRanges.isEmpty
              ? markdownText
              : scan.visibleSourceOf(normalized),
      preserveBlockMarkdownOnPartial: preserveBlockMarkdownOnPartial,
    );
  }

  int _inlineSelectionPlainTextLength(
    String text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    return _inlineSelectionPlainText(
      text,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    ).length;
  }

  String _inlineSelectionPlainText(
    String text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    return _inlineSelectionSegment(
      text,
      markdownText: text,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    ).plainText;
  }

  String _semanticMarkdownForInlineToken(_InlineToken token) {
    if (token.sourceMarkdown != token.text) {
      return token.sourceMarkdown;
    }

    String markdown = token.text;
    if (token.style.code) {
      markdown = '`$markdown`';
    }
    if (token.style.strikethrough) {
      markdown = '~~$markdown~~';
    }
    if (token.style.bold && token.style.italic) {
      return '***$markdown***';
    }
    if (token.style.bold) {
      markdown = '**$markdown**';
    }
    if (token.style.italic) {
      markdown = '_${markdown}_';
    }
    return markdown;
  }

  String _linkReferencesDigest(Map<String, String> linkReferences) {
    if (linkReferences.isEmpty) {
      return '0';
    }
    final List<MapEntry<String, String>> entries =
        linkReferences.entries.toList(growable: false)
          ..sort(
            (MapEntry<String, String> a, MapEntry<String, String> b) =>
                a.key.compareTo(b.key),
          );
    final StringBuffer buffer = StringBuffer();
    for (final MapEntry<String, String> entry in entries) {
      buffer
        ..write(entry.key)
        ..write('=')
        ..write(entry.value)
        ..write(';');
    }
    return buffer.toString().hashCode.toString();
  }
}
