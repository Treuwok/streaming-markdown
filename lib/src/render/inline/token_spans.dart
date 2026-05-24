part of '../view.dart';

extension _StreamingMarkdownInlineTokenSpans on StreamingMarkdownRenderView {
  static const List<Color> _tokenDebugColors = <Color>[
    Color(0xFFFFF3BF),
    Color(0xFFD3F9D8),
    Color(0xFFFFDEEB),
    Color(0xFFD0EBFF),
    Color(0xFFE5DBFF),
    Color(0xFFFFE8CC),
  ];

  int _appendTokenizedTextSpans({
    required List<InlineSpan> spans,
    required String text,
    required TextStyle style,
    required int startTokenIndex,
    required Duration fadeDuration,
    required Curve fadeCurve,
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder,
    required bool animatePerWord,
    _MarkdownSelectionRange? sourceSelectionRange,
    Color? sourceSelectionColor,
    VoidCallback? onTap,
  }) {
    final bool preserveStaticTokenLayout =
        !animatePerWord && fadeDuration > Duration.zero;
    if (!animatePerWord && !preserveStaticTokenLayout && onTap == null) {
      spans.addAll(
        _sourceHighlightedTextSpans(
          text,
          style,
          sourceSelectionRange,
          sourceSelectionColor,
        ),
      );
      return startTokenIndex + _inlineWordCount(text);
    }
    if (!animatePerWord && !preserveStaticTokenLayout) {
      final Widget textWidget =
          sourceSelectionRange == null || sourceSelectionColor == null
              ? Text(text, style: style)
              : Text.rich(
                  TextSpan(
                    style: style,
                    children: _sourceHighlightedTextSpans(
                      text,
                      style,
                      sourceSelectionRange,
                      sourceSelectionColor,
                    ),
                  ),
                );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(onTap: onTap, child: textWidget),
        ),
      );
      return startTokenIndex + _inlineWordCount(text);
    }

    int tokenIndex = startTokenIndex;
    for (final RegExpMatch match in RegExp(r'\S+|\s+').allMatches(text)) {
      final String piece = match.group(0) ?? '';
      if (piece.isEmpty) {
        continue;
      }
      final _MarkdownSelectionRange? pieceSelectionRange =
          _localRangeForTextSlice(
        sourceSelectionRange,
        start: match.start,
        length: piece.length,
      );

      if (piece.trim().isEmpty) {
        // Newlines must stay as raw text spans so blocks like quote/code/footnote
        // preserve line breaks exactly as source.
        spans.addAll(
          _sourceHighlightedTextSpans(
            piece,
            style,
            pieceSelectionRange,
            sourceSelectionColor,
          ),
        );
        continue;
      }

      final Widget tokenWidget;
      if (debugTokenHighlight) {
        final Color bgColor =
            _tokenDebugColors[tokenIndex % _tokenDebugColors.length];
        tokenWidget = Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            piece,
            style: style.copyWith(
              color: style.color ?? const Color(0xFF0D1117),
            ),
          ),
        );
      } else {
        tokenWidget =
            pieceSelectionRange == null || sourceSelectionColor == null
                ? Text(piece, style: style)
                : Text.rich(
                    TextSpan(
                      style: style,
                      children: _sourceHighlightedTextSpans(
                        piece,
                        style,
                        pieceSelectionRange,
                        sourceSelectionColor,
                      ),
                    ),
                  );
      }

      if (!animatePerWord) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: onTap == null
                ? tokenWidget
                : (debugTokenHighlight
                    ? InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(4),
                        child: tokenWidget,
                      )
                    : GestureDetector(onTap: onTap, child: tokenWidget)),
          ),
        );
        tokenIndex += 1;
        continue;
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _FadeInTokenHost(
            key: ValueKey<String>('token_${tokenIndex}_${piece.hashCode}'),
            // Use absolute token index in block so delays do not reset
            // across inline style segments (links/bold/italic/code...).
            initialDelay: tokenScheduleOrigin == null
                ? tokenStaggerDelay * tokenIndex
                : Duration.zero,
            scheduledStart: tokenScheduleOrigin?.add(
              tokenStaggerDelay * tokenIndex,
            ),
            duration: fadeDuration,
            curve: fadeCurve,
            animationBuilder: tokenAnimationBuilder,
            onFadeInEnd: onTokenFadeInEnd,
            child: onTap == null
                ? tokenWidget
                : (debugTokenHighlight
                    ? InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(4),
                        child: tokenWidget,
                      )
                    : GestureDetector(onTap: onTap, child: tokenWidget)),
          ),
        ),
      );
      tokenIndex += 1;
    }
    return tokenIndex;
  }

  int _appendAnimatedWidgetSpan({
    required List<InlineSpan> spans,
    required Widget child,
    required int tokenIndex,
    required Duration fadeDuration,
    required Curve fadeCurve,
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder,
    required PlaceholderAlignment alignment,
    TextBaseline? baseline,
    int tokenUnits = 1,
    bool animate = true,
  }) {
    if (!animate) {
      spans.add(
        WidgetSpan(
          alignment: alignment,
          baseline: baseline,
          child: child,
        ),
      );
      return tokenIndex + (tokenUnits <= 0 ? 1 : tokenUnits);
    }
    spans.add(
      WidgetSpan(
        alignment: alignment,
        baseline: baseline,
        child: _FadeInTokenHost(
          key: ValueKey<String>('widget_token_${tokenIndex}_${child.hashCode}'),
          initialDelay: tokenScheduleOrigin == null
              ? tokenStaggerDelay * tokenIndex
              : Duration.zero,
          scheduledStart: tokenScheduleOrigin?.add(
            tokenStaggerDelay * tokenIndex,
          ),
          duration: fadeDuration,
          curve: fadeCurve,
          animationBuilder: tokenAnimationBuilder,
          onFadeInEnd: onTokenFadeInEnd,
          child: child,
        ),
      ),
    );
    return tokenIndex + (tokenUnits <= 0 ? 1 : tokenUnits);
  }

  int _inlineWordCount(String text) {
    final int count = RegExp(r'\S+').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }

  int _countAnimatedTokenUnits(
    String text, {
    required Map<String, String> linkReferences,
  }) {
    if (text.trim().isEmpty) {
      return 0;
    }
    final List<_InlineToken> tokens = _parseInlineTokens(
      text.replaceAll('\r', ''),
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return _inlineWordCount(text);
    }
    int total = 0;
    for (final _InlineToken token in tokens) {
      if (token.isImage || token.isFootnoteReference || token.isLatex) {
        total += 1;
        continue;
      }
      total += _inlineWordCount(token.text);
    }
    return total;
  }
}

List<TextSpan> _sourceHighlightedTextSpans(
  String text,
  TextStyle style,
  _MarkdownSelectionRange? range,
  Color? color,
) {
  if (text.isEmpty || range == null || color == null) {
    return <TextSpan>[TextSpan(text: text, style: style)];
  }
  final int start = range.start.clamp(0, text.length);
  final int end = range.end.clamp(start, text.length);
  if (start >= end) {
    return <TextSpan>[TextSpan(text: text, style: style)];
  }

  final TextStyle highlightedStyle = style.copyWith(backgroundColor: color);
  final List<TextSpan> spans = <TextSpan>[];
  if (start > 0) {
    spans.add(TextSpan(text: text.substring(0, start), style: style));
  }
  spans
      .add(TextSpan(text: text.substring(start, end), style: highlightedStyle));
  if (end < text.length) {
    spans.add(TextSpan(text: text.substring(end), style: style));
  }
  return spans;
}

_MarkdownSelectionRange? _localRangeForTextSlice(
  _MarkdownSelectionRange? range, {
  required int start,
  required int length,
}) {
  if (range == null || length <= 0) {
    return null;
  }
  final int end = start + length;
  if (range.end <= start || range.start >= end) {
    return null;
  }
  return _MarkdownSelectionRange(
    start: (range.start - start).clamp(0, length),
    end: (range.end - start).clamp(0, length),
  );
}
