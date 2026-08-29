part of '../view.dart';

extension _StreamingMarkdownInlineMarkdownRenderer
    on StreamingMarkdownRenderView {
  /// Paints inline Markdown, and takes a [_SourceSlice] rather than a
  /// `String` on purpose.
  ///
  /// Every block type projects its own text before arriving here — a list
  /// splits items, a table splits cells, a callout lifts its title out. Those
  /// projections are where provenance was being dropped, and while this took a
  /// `String` there was nothing to stop the next one from dropping it too:
  /// anything that needed to map painted characters back to the source had to
  /// re-derive the projection, per block type, by hand.
  ///
  /// Requiring the slice puts that on the compiler. A new block type cannot
  /// reach the screen without saying where its text came from.
  Widget _buildInlineMarkdown(
    BuildContext context,
    _SourceSlice slice, {
    int tokenStartIndex = 0,
    int plainTextStart = 0,
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
    Map<String, int> footnoteNumbers = const <String, int>{},
  }) {
    final _SourceSlice normalizedSlice = slice.withoutCarriageReturns();
    final String normalized = normalizedSlice.text;
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle = baseStyle ??
        markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final bool compacted = _TokenCompactionScope.isCompacted(context);
    final bool animatePerWord = !compacted;
    final _InlineParseResult scan = _inlineParserFor(
      linkReferences,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
    ).scan(normalized);
    final List<_InlineToken> tokens = scan.tokens;
    if (tokens.isEmpty) {
      // NOT `normalized`. An empty list also means "everything here was held
      // back", and drawing the source then prints the destination the scan
      // just refused to draw.
      final String visible = scan.visibleSourceOf(normalized);
      if (visible.isEmpty) {
        return const SizedBox.shrink();
      }
      return Text(visible, style: resolvedStyle);
    }
    final String selectableText = _plainTextForVisualInlineTokens(
      tokens,
      footnoteNumbers: footnoteNumbers,
    );
    final TextSpan selectionText = _selectionTextSpanForInlineTokens(
      tokens,
      resolvedStyle,
      footnoteNumbers: footnoteNumbers,
    );
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;
    final _MarkdownSelectionRange? sourceVisualRange =
        _sourceSelectionVisualRangeForInline(
      context,
      selectableText.length,
      plainTextStart: plainTextStart,
    );
    final Color? sourceVisualColor = sourceVisualRange == null
        ? null
        : _MarkdownSourceSelectionVisualScope.maybeOf(context)?.selectionColor;

    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = tokenStartIndex;
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: inlineImageAlignment,
          baseline: _baselineForPlaceholderAlignment(inlineImageAlignment),
          child: _buildInlineImageToken(context, token, resolvedStyle),
        );
        continue;
      }

      if (token.isLatex) {
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.middle,
          child: _buildLatexToken(context, token, resolvedStyle),
        );
        continue;
      }

      if (token.style.code) {
        final TextStyle inlineCodeStyle = markdownTheme.inlineCodeTextStyle ??
            const TextStyle(
              color: Color(0xFFE6EDF3),
              fontFamily: 'monospace',
              fontSize: 12,
            );
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.middle,
          tokenUnits: _inlineWordCount(token.text),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: markdownTheme.inlineCodeBackgroundColor ??
                  const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(token.text, style: inlineCodeStyle),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        continue;
      }

      TextStyle style = resolvedStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.linkUrl != null && token.linkUrl!.isNotEmpty) {
        style = style.merge(
          markdownTheme.linkTextStyle ??
              const TextStyle(
                color: Color(0xFF58A6FF),
                decoration: TextDecoration.underline,
              ),
        );
        visualTokenIndex = _appendTokenizedTextSpans(
          spans: spans,
          text: token.text,
          style: style,
          startTokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animatePerWord: animatePerWord,
          onTap: () => _onLinkPressed(context, token.linkUrl!),
        );
        continue;
      }
      visualTokenIndex = _appendTokenizedTextSpans(
        spans: spans,
        text: token.text,
        style: style,
        startTokenIndex: visualTokenIndex,
        fadeDuration: tokenFadeDuration,
        fadeCurve: tokenFadeInCurve,
        tokenStaggerDelay: resolvedTokenStep,
        tokenScheduleOrigin: tokenScheduleOrigin,
        tokenAnimationBuilder: tokenAnimationBuilder,
        animatePerWord: animatePerWord,
      );
    }

    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final _MarkdownSelectionBlockRange? selectionBlockRange =
        _MarkdownSelectionBlockVisualScope.maybeOf(context)?.blockRange;
    final int absolutePlainTextStart =
        (selectionBlockRange?.plainRange.start ?? 0) + plainTextStart;
    final int compactPlainTextStart =
        (selectionBlockRange?.compactRange.start ?? absolutePlainTextStart) +
            plainTextStart;
    final _MarkdownInlineSelectionRegistry? inlineSelectionRegistry =
        _MarkdownInlineSelectionRegistryScope.maybeOf(context);
    final Widget animatedRichText = RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget selectableOutput = !enableTextSelection
        ? animatedRichText
        : _SelectableInlineTextProxy(
            plainText: selectableText,
            absolutePlainTextStart: absolutePlainTextStart,
            compactPlainTextStart: compactPlainTextStart,
            text: selectionText,
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            registrar: SelectionContainer.maybeOf(context),
            selectionRegistry: inlineSelectionRegistry,
            child: SelectionContainer.disabled(
              child: _InlineSourceSelectionBackdrop(
                range: sourceVisualRange,
                selectedText: _selectedTextForRange(
                  selectableText,
                  sourceVisualRange,
                ),
                text: selectionText,
                textDirection: TextDirection.ltr,
                textScaler: textScaler,
                selectionColor: sourceVisualColor,
                child: animatedRichText,
              ),
            ),
          );
    final Widget output = MouseRegion(
      cursor: SystemMouseCursors.text,
      child: selectableOutput,
    );

    final List<String> inlineImageUrls = tokens
        .where((_InlineToken token) => token.isImage)
        .map((_InlineToken token) => token.imageUrl ?? '')
        .where((String url) => url.isNotEmpty)
        .toList(growable: false);
    if (inlineImageUrls.isEmpty || customImageBuilder != null) {
      return output;
    }
    return _MarkdownImageLoadBarrier(urls: inlineImageUrls, child: output);
  }
}

String _selectedTextForRange(
  String text,
  _MarkdownSelectionRange? range,
) {
  if (range == null || text.isEmpty) {
    return '';
  }
  final int start = range.start.clamp(0, text.length);
  final int end = range.end.clamp(start, text.length);
  return start >= end ? '' : text.substring(start, end);
}

String _plainTextForVisualInlineTokens(
  List<_InlineToken> tokens, {
  required Map<String, int> footnoteNumbers,
}) {
  final StringBuffer buffer = StringBuffer();
  for (final _InlineToken token in tokens) {
    buffer.write(
      _plainTextForVisualInlineToken(
        token,
        footnoteNumbers: footnoteNumbers,
      ),
    );
  }
  return buffer.toString();
}

TextSpan _selectionTextSpanForInlineTokens(
  List<_InlineToken> tokens,
  TextStyle baseStyle, {
  required Map<String, int> footnoteNumbers,
}) {
  final List<InlineSpan> spans = <InlineSpan>[];
  for (final _InlineToken token in tokens) {
    TextStyle style = baseStyle;
    if (token.style.bold) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (token.style.italic) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (token.style.code) {
      style = style.copyWith(fontFamily: 'monospace', fontSize: 12);
    }
    spans.add(
      TextSpan(
        text: _plainTextForVisualInlineToken(
          token,
          footnoteNumbers: footnoteNumbers,
        ),
        style: style,
      ),
    );
  }
  return TextSpan(style: baseStyle, children: spans);
}

_MarkdownSelectionRange? _sourceSelectionVisualRangeForInline(
  BuildContext context,
  int textLength, {
  required int plainTextStart,
}) {
  final _MarkdownSourceSelectionVisualScope? visualScope =
      _MarkdownSourceSelectionVisualScope.maybeOf(context);
  final _MarkdownSelectionBlockVisualScope? blockScope =
      _MarkdownSelectionBlockVisualScope.maybeOf(context);
  final _MarkdownSourceSelectionRange? sourceRange = visualScope?.sourceRange;
  final _MarkdownSelectionRange? plainRange = visualScope?.plainRange;
  if (visualScope == null ||
      blockScope == null ||
      sourceRange == null ||
      plainRange == null) {
    return null;
  }

  final _MarkdownSelectionBlockRange blockRange = blockScope.blockRange;
  if (sourceRange.end <= blockRange.sourceRange.start ||
      sourceRange.start >= blockRange.sourceRange.end ||
      plainRange.end <= blockRange.plainRange.start ||
      plainRange.start >= blockRange.plainRange.end) {
    return null;
  }

  final int absoluteTextStart = blockRange.plainRange.start + plainTextStart;
  final int absoluteTextEnd = absoluteTextStart + textLength;
  if (plainRange.end <= absoluteTextStart ||
      plainRange.start >= absoluteTextEnd) {
    return null;
  }

  final int start = (plainRange.start - absoluteTextStart).clamp(0, textLength);
  final int end = (plainRange.end - absoluteTextStart).clamp(start, textLength);
  if (start >= end) {
    return null;
  }
  return _MarkdownSelectionRange(start: start, end: end);
}

String _plainTextForVisualInlineToken(
  _InlineToken token, {
  required Map<String, int> footnoteNumbers,
}) {
  if (token.isImage) {
    return token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]';
  }
  if (token.isFootnoteReference) {
    final int? number = _footnoteNumberForId(
      footnoteNumbers,
      token.footnoteReferenceId!,
    );
    return number?.toString() ?? token.footnoteReferenceId!;
  }
  if (token.isLatex) {
    return token.sourceMarkdown;
  }
  return token.text;
}

extension _StreamingMarkdownLinkActions on StreamingMarkdownRenderView {
  void _onLinkPressed(BuildContext context, String url) {
    final ValueChanged<String>? callback = onLinkTap;
    if (callback != null) {
      callback(url);
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied link: $url')));
  }
}
