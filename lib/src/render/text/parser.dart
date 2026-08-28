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
  });

  final Map<String, String> references;
  final bool allowUnclosedDelimiters;

  /// Hold back inline text whose link destination has not arrived yet.
  final bool withholdIncompleteDestinations;

  final List<(int, int)> _hiddenRanges = <(int, int)>[];
  int? _withheldFrom;

  /// Scan [text] and report both halves of the outcome.
  _InlineParseResult scan(String text, {_InlineStyle style = const _InlineStyle()}) {
    _hiddenRanges.clear();
    _withheldFrom = null;
    final List<_InlineToken> tokens = _parseInlineTokens(text, style: style);
    return _InlineParseResult(
      tokens: tokens,
      withheldFrom: _withheldFrom,
      hiddenRanges: List<(int, int)>.unmodifiable(_hiddenRanges),
    );
  }

  /// Scan [text] for rendering only.
  List<_InlineToken> tokenize(
    String text, {
    _InlineStyle style = const _InlineStyle(),
  }) =>
      scan(text, style: style).tokens;

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
    );
  }
}
