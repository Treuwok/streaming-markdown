part of '../view.dart';

extension _StreamingMarkdownInlineMarkdownRenderer
    on StreamingMarkdownRenderView {
  Widget _buildInlineMarkdown(
    BuildContext context,
    String text, {
    int tokenStartIndex = 0,
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
    Map<String, int> footnoteNumbers = const <String, int>{},
  }) {
    final String normalized = text.replaceAll('\r', '');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle = baseStyle ??
        markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final bool showSelectionOverlay = enableTextSelection;
    final bool compacted = _TokenCompactionScope.isCompacted(context);
    final bool animatePerWord = !compacted;
    final List<_InlineToken> tokens = _parseInlineTokens(
      normalized,
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return Text(normalized, style: resolvedStyle);
    }
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;
    final _MarkdownSelectionRange? sourceVisualRange =
        _sourceSelectionVisualRangeForInline(context, normalized.length);
    final Color? sourceVisualColor = sourceVisualRange == null
        ? null
        : _MarkdownSourceSelectionVisualScope.maybeOf(context)?.selectionColor;

    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = tokenStartIndex;
    int plainCursor = 0;
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
        plainCursor += _plainTextForVisualInlineToken(
          token,
          footnoteNumbers: footnoteNumbers,
        ).length;
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
        plainCursor += _plainTextForVisualInlineToken(
          token,
          footnoteNumbers: footnoteNumbers,
        ).length;
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
        plainCursor += token.text.length;
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
        plainCursor += _plainTextForVisualInlineToken(
          token,
          footnoteNumbers: footnoteNumbers,
        ).length;
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
          sourceSelectionRange: _localRangeForTextSlice(
            sourceVisualRange,
            start: plainCursor,
            length: token.text.length,
          ),
          sourceSelectionColor: sourceVisualColor,
          onTap: showSelectionOverlay
              ? null
              : () => _onLinkPressed(context, token.linkUrl!),
        );
        plainCursor += token.text.length;
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
        sourceSelectionRange: _localRangeForTextSlice(
          sourceVisualRange,
          start: plainCursor,
          length: token.text.length,
        ),
        sourceSelectionColor: sourceVisualColor,
      );
      plainCursor += token.text.length;
    }

    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final Widget animatedRichText = RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget output = !showSelectionOverlay
        ? animatedRichText
        : _SelectionAwareInlineStack(
            animatedLayer: animatedRichText,
            selectableLayer: _SelectableInlineTextOverlay(
              tokens: tokens,
              baseStyle: resolvedStyle,
              footnoteNumbers: footnoteNumbers,
              textScaler: textScaler,
              selectionColor:
                  markdownTheme.selectionColor ?? const Color(0x6658A6FF),
              onLinkTap: (String url) => _onLinkPressed(context, url),
            ),
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

_MarkdownSelectionRange? _sourceSelectionVisualRangeForInline(
  BuildContext context,
  int textLength,
) {
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

  final int start =
      (plainRange.start - blockRange.plainRange.start).clamp(0, textLength);
  final int end =
      (plainRange.end - blockRange.plainRange.start).clamp(start, textLength);
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

class _SelectionAwareInlineStack extends StatelessWidget {
  const _SelectionAwareInlineStack({
    required this.animatedLayer,
    required this.selectableLayer,
  });

  final Widget animatedLayer;
  final Widget selectableLayer;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Positioned.fill(child: selectableLayer),
        SelectionContainer.disabled(
          child: IgnorePointer(child: animatedLayer),
        ),
      ],
    );
  }
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
