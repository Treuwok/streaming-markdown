part of '../view.dart';

class _ParsedList {
  const _ParsedList({required this.items});

  final List<_ParsedListItem> items;
}

class _ParsedListItem {
  const _ParsedListItem({
    required this.level,
    required this.ordered,
    required this.order,
    required this.taskState,
    required this.text,
    required this.stableKey,
  });

  final int level;
  final bool ordered;
  final int order;
  final bool? taskState;
  final String text;
  final String stableKey;
}

class _ParsedTable {
  const _ParsedTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class _CalloutData {
  const _CalloutData({
    required this.kind,
    required this.title,
    required this.body,
  });

  final String kind;
  final String title;
  final String body;
}

class _DelimitedMatch {
  const _DelimitedMatch({required this.inner, required this.end});

  final String inner;
  final int end;
}

class _InlineImageMatch {
  const _InlineImageMatch({
    required this.alt,
    required this.url,
    required this.end,
  });

  final String alt;
  final String url;
  final int end;
}

/// Why `_scanInlineLinkAt` cannot answer with a nullable match.
///
/// A null conflates two opposite facts: "this is not a link, paint the source
/// as written" and "this IS a link whose destination has not arrived yet, so
/// painting the source as written puts the destination on screen". Streaming
/// makes the second one routine — every transport chunk can land mid-URL — and
/// the caller has no way to tell them apart, so it paints both.
///
/// Splitting the return type is what makes the distinction available at all.
/// The scanner already knows which branch it took; it was simply discarding
/// that on the way out.
enum _InlineLinkScanKind { matched, notALink, incompleteDestination }

class _InlineLinkScan {
  const _InlineLinkScan.matched(_InlineLinkMatch this.match)
      : kind = _InlineLinkScanKind.matched;
  const _InlineLinkScan.notALink()
      : kind = _InlineLinkScanKind.notALink,
        match = null;
  const _InlineLinkScan.incompleteDestination()
      : kind = _InlineLinkScanKind.incompleteDestination,
        match = null;

  final _InlineLinkScanKind kind;
  final _InlineLinkMatch? match;
}

class _InlineLinkMatch {
  const _InlineLinkMatch({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
}

class _FootnoteReferenceMatch {
  const _FootnoteReferenceMatch({required this.id, required this.end});

  final String id;
  final int end;
}

class _LatexMatch {
  const _LatexMatch({
    required this.expression,
    required this.sourceMarkdown,
    required this.display,
    required this.end,
  });

  final String expression;
  final String sourceMarkdown;
  final bool display;
  final int end;
}

class _FootnoteDefinition {
  const _FootnoteDefinition({required this.id, required this.body});

  final String id;
  final String body;
}

int? _footnoteNumberForId(Map<String, int> footnoteNumbers, String id) {
  return footnoteNumbers[_normalizeFootnoteKey(id)];
}

String _normalizeFootnoteKey(String key) {
  return key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Reference keys and footnote keys normalise identically.
String _normalizeReferenceKey(String key) {
  return _normalizeFootnoteKey(key);
}

/// `<https://x>` -> `https://x`. Pure string work, shared by the grammar and
/// by the reference-definition extractor, so it lives at library level rather
/// than on either consumer.
String _stripEnclosingAngles(String value) {
  final String trimmed = value.trim();
  if (trimmed.startsWith('<') && trimmed.endsWith('>') && trimmed.length > 2) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
    );
  }
}

class _InlineToken {
  const _InlineToken.text({
    required this.text,
    required this.style,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
    this.linkUrl,
  })  : altText = '',
        imageUrl = null,
        footnoteReferenceId = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.image({
    required this.altText,
    required this.imageUrl,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        footnoteReferenceId = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.footnote({
    required this.footnoteReferenceId,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.latex({
    required this.latexExpression,
    required this.latexDisplay,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null,
        footnoteReferenceId = null;

  final String text;
  final _InlineStyle style;
  final String? linkUrl;
  final String altText;
  final String? imageUrl;
  final String? footnoteReferenceId;
  final String? latexExpression;
  final bool latexDisplay;
  final String sourceMarkdown;

  /// Where this token's visible [text] begins in the source handed to `scan`.
  ///
  /// Absolute, in the same code-unit coordinates as the reported hidden
  /// ranges — a nested scan is given its caller's offset, so a link label
  /// reports where the LABEL sits, not where the construct does.
  ///
  /// Anything mapping painted characters back to source needs this. Without
  /// it, a caller can only re-derive the mapping by parsing the text a second
  /// time with a second parser and aligning the two results heuristically,
  /// which is what mobile did before #2360 — and the two parsers did not have
  /// to agree.
  final int visibleSourceStart;

  /// Whether [text] is a verbatim slice of the source at [visibleSourceStart].
  ///
  /// True for ordinary text runs, so character `k` of [text] came from source
  /// offset `visibleSourceStart + k`. False where the visible text is not in
  /// the source at all — an image's alt text, a footnote marker, rendered
  /// LaTeX — and every character of those maps to the construct's start.
  bool get isVerbatimSlice => !isImage && !isFootnoteReference && !isLatex;

  bool get isImage => imageUrl != null;
  bool get isFootnoteReference => footnoteReferenceId != null;
  bool get isLatex => latexExpression != null;

  _InlineToken withLink(String url, {required String sourceMarkdown}) {
    if (isImage || isFootnoteReference || isLatex) {
      return this;
    }
    return _InlineToken.text(
      text: text,
      style: style,
      linkUrl: url,
      sourceMarkdown: sourceMarkdown,
      visibleSourceStart: visibleSourceStart,
    );
  }
}
