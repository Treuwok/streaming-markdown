part of '../view.dart';

/// One inline scan, and everything that scan decided.
///
/// [tokens] is what gets drawn. The other two fields are what the scan
/// deliberately did NOT draw — the part that used to be thrown away at the
/// point of decision and re-derived by whoever needed it.
final class _InlineParseResult {
  const _InlineParseResult({
    required this.tokens,
    required this.withheldFrom,
    required this.hiddenRanges,
  });

  final List<_InlineToken> tokens;

  /// Code-unit offset into the scanned text where tokenising stopped because a
  /// destination had not arrived yet; `null` when the whole text was consumed.
  final int? withheldFrom;

  /// Code-unit ranges the scan recognised as raw HTML and did not draw.
  final List<(int start, int end)> hiddenRanges;

  /// The part of [text] these tokens came from.
  ///
  /// [tokens] being empty has two causes that must not be confused: the text
  /// genuinely has nothing in it, or everything in it was held back. Callers
  /// that fall back to "just draw the source" on an empty list print the very
  /// destination the scan refused to draw — so the fallback has to ask this,
  /// not the list.
  String visibleSourceOf(String text) {
    final int? boundary = withheldFrom;
    return boundary == null ? text : text.substring(0, boundary);
  }
}

/// The inline grammar, detached from the widget that renders it.
///
/// It used to be an extension on the render view, which made the grammar a
/// capability of a widget. Anything that needed the scan's findings but not
/// its widgets — the mobile reveal timeline needs exactly that — had no way to
/// reach it and wrote a second copy of the grammar instead. Rendering and
/// analysis are now two consumers of one scan (#2343).
final class _InlineParser {
  _InlineParser({
    this.references = const <String, String>{},
    this.allowUnclosedDelimiters = false,
    this.withholdIncompleteDestinations = false,
    this.suppressRawHtml = false,
    this.sourceComplete = false,
  });

  final Map<String, String> references;
  final bool allowUnclosedDelimiters;

  /// Hold back inline text whose link destination has not arrived yet.
  final bool withholdIncompleteDestinations;

  /// Do not draw raw HTML at all, and report where it was.
  ///
  /// Deliberately a separate question from
  /// [withholdIncompleteDestinations]: that one is about a destination still
  /// in flight, which appears once it arrives. This one is a decision about
  /// content that is complete — the host does not render raw HTML — so the two
  /// cannot share a flag without one of them lying about what it does.
  final bool suppressRawHtml;

  /// Whether no more source can arrive.
  ///
  /// Only arms whose reason for holding back is "more may still arrive" change
  /// when this is set, and only where no destination is present to expose:
  /// `[unclosed`, a label whose `]` sits inside a code span with no `](` in
  /// reach, and an unterminated `<tag` carrying no attributes. A destination
  /// that is visibly mid-flight (`[x](https://…`, `<a href="…`) keeps being
  /// held back — the source ending does not make showing it correct.
  ///
  /// An unterminated autolink is in neither list: it is not held back at any
  /// point, because its destination IS its visible text.
  final bool sourceComplete;

  final List<(int, int)> _hiddenRanges = <(int, int)>[];
  int? _withheldFrom;

  /// Scan [text] and report both halves of the outcome.
  _InlineParseResult scan(String text,
      {_InlineStyle style = const _InlineStyle()}) {
    _hiddenRanges.clear();
    _withheldFrom = null;
    final List<_InlineToken> tokens = _parseInlineTokens(text, style: style);
    return _InlineParseResult(
      tokens: tokens,
      withheldFrom: _withheldFrom,
      hiddenRanges: List<(int, int)>.unmodifiable(_hiddenRanges),
    );
  }

  /// Records the first position that was held back, in top-level coordinates.
  void _withholdAt(int offset) {
    _withheldFrom ??= offset;
  }
}

extension _StreamingMarkdownInlineParserFactory on StreamingMarkdownRenderView {
  /// The one place the view's inline flags become a parser.
  ///
  /// [withholdIncompleteDestinations] is passed explicitly rather than read
  /// from the view: copy-to-clipboard and footnote bodies are not the live
  /// stream, and must keep tokenising the whole text.
  _InlineParser _inlineParserFor(
    Map<String, String> references, {
    bool withholdIncompleteDestinations = false,
  }) {
    return _InlineParser(
      references: references,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
      suppressRawHtml: suppressRawHtml,
      sourceComplete: sourceComplete,
    );
  }
}
