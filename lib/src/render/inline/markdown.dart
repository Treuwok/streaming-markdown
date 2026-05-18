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
          onTap: showSelectionOverlay
              ? null
              : () => _onLinkPressed(context, token.linkUrl!),
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
    final Widget animatedRichText = RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget selectionSafeLayer = _SelectableAnimatedInlineTextLayer(
      renderer: this,
      tokens: tokens,
      baseStyle: resolvedStyle,
      footnoteNumbers: footnoteNumbers,
      textScaler: textScaler,
      tokenStartIndex: tokenStartIndex,
      fadeDuration: tokenFadeDuration,
      fadeCurve: tokenFadeInCurve,
      tokenStaggerDelay: resolvedTokenStep,
      tokenScheduleOrigin: tokenScheduleOrigin,
      animate: !compacted,
    );
    final Widget output = !showSelectionOverlay
        ? animatedRichText
        : _SelectionAwareInlineStack(
            animatedLayer: animatedRichText,
            selectionSafeLayer: selectionSafeLayer,
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

class _SelectionAwareInlineStack extends StatefulWidget {
  const _SelectionAwareInlineStack({
    required this.animatedLayer,
    required this.selectionSafeLayer,
    required this.selectableLayer,
  });

  final Widget animatedLayer;
  final Widget selectionSafeLayer;
  final Widget selectableLayer;

  @override
  State<_SelectionAwareInlineStack> createState() =>
      _SelectionAwareInlineStackState();
}

class _SelectionAwareInlineStackState
    extends State<_SelectionAwareInlineStack> {
  final SelectionListenerNotifier _selectionNotifier =
      SelectionListenerNotifier();
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _selectionNotifier.addListener(_syncSelectionState);
  }

  @override
  void dispose() {
    _selectionNotifier.removeListener(_syncSelectionState);
    _selectionNotifier.dispose();
    super.dispose();
  }

  void _syncSelectionState() {
    if (!_selectionNotifier.registered) {
      return;
    }
    final bool hasSelection =
        _selectionNotifier.selection.status != SelectionStatus.none;
    if (hasSelection == _hasSelection) {
      return;
    }
    setState(() {
      _hasSelection = hasSelection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget visibleLayer =
        _hasSelection ? widget.selectionSafeLayer : widget.animatedLayer;
    return SelectionListener(
      selectionNotifier: _selectionNotifier,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(child: widget.selectableLayer),
          SelectionContainer.disabled(
            child: IgnorePointer(child: visibleLayer),
          ),
        ],
      ),
    );
  }
}

class _SelectableAnimatedInlineTextLayer extends StatefulWidget {
  const _SelectableAnimatedInlineTextLayer({
    required this.renderer,
    required this.tokens,
    required this.baseStyle,
    required this.footnoteNumbers,
    required this.textScaler,
    required this.tokenStartIndex,
    required this.fadeDuration,
    required this.fadeCurve,
    required this.tokenStaggerDelay,
    required this.tokenScheduleOrigin,
    required this.animate,
  });

  final StreamingMarkdownRenderView renderer;
  final List<_InlineToken> tokens;
  final TextStyle baseStyle;
  final Map<String, int> footnoteNumbers;
  final TextScaler textScaler;
  final int tokenStartIndex;
  final Duration fadeDuration;
  final Curve fadeCurve;
  final Duration tokenStaggerDelay;
  final DateTime? tokenScheduleOrigin;
  final bool animate;

  @override
  State<_SelectableAnimatedInlineTextLayer> createState() =>
      _SelectableAnimatedInlineTextLayerState();
}

class _SelectableAnimatedInlineTextLayerState
    extends State<_SelectableAnimatedInlineTextLayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  late DateTime _localOrigin;
  Duration _elapsed = Duration.zero;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _localOrigin = DateTime.now();
    _configureTicker();
  }

  @override
  void didUpdateWidget(covariant _SelectableAnimatedInlineTextLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokens != widget.tokens ||
        oldWidget.tokenStartIndex != widget.tokenStartIndex ||
        oldWidget.fadeDuration != widget.fadeDuration ||
        oldWidget.tokenStaggerDelay != widget.tokenStaggerDelay ||
        oldWidget.tokenScheduleOrigin != widget.tokenScheduleOrigin ||
        oldWidget.animate != widget.animate) {
      _localOrigin = DateTime.now();
      _elapsed = Duration.zero;
      _completed = false;
      _configureTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _configureTicker() {
    _ticker?.dispose();
    _ticker = null;
    if (!widget.animate || widget.fadeDuration <= Duration.zero) {
      return;
    }
    _ticker = createTicker((Duration elapsed) {
      if (!mounted) {
        return;
      }
      _elapsed = elapsed;
      if (_isComplete()) {
        _ticker?.stop();
        if (!_completed) {
          _completed = true;
          widget.renderer.onTokenFadeInEnd?.call();
        }
      }
      setState(() {});
    })
      ..start();
  }

  bool _isComplete() {
    final int tokenCount = _animatedTextTokenCount();
    if (tokenCount <= 0) {
      return true;
    }
    final int lastTokenIndex = widget.tokenStartIndex + tokenCount - 1;
    final Duration lastStart = _tokenStartOffset(lastTokenIndex);
    return _elapsed >= lastStart + widget.fadeDuration;
  }

  int _animatedTextTokenCount() {
    int count = 0;
    for (final _InlineToken token in widget.tokens) {
      if (token.isImage || token.isFootnoteReference || token.style.code) {
        continue;
      }
      if (token.isLatex) {
        count += 1;
        continue;
      }
      count += widget.renderer._inlineWordCount(token.text);
    }
    return count;
  }

  Duration _tokenStartOffset(int tokenIndex) {
    final Duration staggerOffset = widget.tokenStaggerDelay * tokenIndex;
    final DateTime? scheduleOrigin = widget.tokenScheduleOrigin;
    if (scheduleOrigin == null) {
      return staggerOffset;
    }
    final Duration originOffset = scheduleOrigin.difference(_localOrigin);
    final Duration offset = originOffset + staggerOffset;
    return offset <= Duration.zero ? Duration.zero : offset;
  }

  double _tokenOpacity(int tokenIndex) {
    if (!widget.animate || widget.fadeDuration <= Duration.zero) {
      return 1;
    }
    final Duration start = _tokenStartOffset(tokenIndex);
    if (_elapsed < start) {
      return 0;
    }
    final int fadeMicros = widget.fadeDuration.inMicroseconds;
    if (fadeMicros <= 0) {
      return 1;
    }
    final double rawProgress = (_elapsed - start).inMicroseconds / fadeMicros;
    if (rawProgress >= 1) {
      return 1;
    }
    return widget.fadeCurve.transform(rawProgress.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = widget.tokenStartIndex;
    for (final _InlineToken token in widget.tokens) {
      if (token.isImage) {
        visualTokenIndex = widget.renderer._appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: widget.fadeDuration,
          fadeCurve: widget.fadeCurve,
          tokenStaggerDelay: widget.tokenStaggerDelay,
          tokenScheduleOrigin: widget.tokenScheduleOrigin,
          tokenAnimationBuilder: widget.renderer.tokenAnimationBuilder,
          animate: widget.animate,
          alignment: widget.renderer.inlineImageAlignment,
          baseline: widget.renderer._baselineForPlaceholderAlignment(
            widget.renderer.inlineImageAlignment,
          ),
          child: widget.renderer._buildInlineImageToken(
            context,
            token,
            widget.baseStyle,
          ),
        );
        continue;
      }

      if (token.isLatex) {
        visualTokenIndex = widget.renderer._appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: widget.fadeDuration,
          fadeCurve: widget.fadeCurve,
          tokenStaggerDelay: widget.tokenStaggerDelay,
          tokenScheduleOrigin: widget.tokenScheduleOrigin,
          tokenAnimationBuilder: widget.renderer.tokenAnimationBuilder,
          animate: widget.animate,
          alignment: PlaceholderAlignment.middle,
          child: widget.renderer._buildLatexToken(
            context,
            token,
            widget.baseStyle,
          ),
        );
        continue;
      }

      if (token.style.code) {
        final TextStyle inlineCodeStyle =
            widget.renderer.markdownTheme.inlineCodeTextStyle ??
                const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontFamily: 'monospace',
                  fontSize: 12,
                );
        visualTokenIndex = widget.renderer._appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: widget.fadeDuration,
          fadeCurve: widget.fadeCurve,
          tokenStaggerDelay: widget.tokenStaggerDelay,
          tokenScheduleOrigin: widget.tokenScheduleOrigin,
          tokenAnimationBuilder: widget.renderer.tokenAnimationBuilder,
          animate: widget.animate,
          alignment: PlaceholderAlignment.middle,
          tokenUnits: widget.renderer._inlineWordCount(token.text),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: widget.renderer.markdownTheme.inlineCodeBackgroundColor ??
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
          widget.footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        visualTokenIndex = widget.renderer._appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: widget.fadeDuration,
          fadeCurve: widget.fadeCurve,
          tokenStaggerDelay: widget.tokenStaggerDelay,
          tokenScheduleOrigin: widget.tokenScheduleOrigin,
          tokenAnimationBuilder: widget.renderer.tokenAnimationBuilder,
          animate: widget.animate,
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

      TextStyle style = widget.baseStyle;
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
          widget.renderer.markdownTheme.linkTextStyle ??
              const TextStyle(
                color: Color(0xFF58A6FF),
                decoration: TextDecoration.underline,
              ),
        );
      }
      visualTokenIndex = _appendAnimatedTextSpans(
        spans: spans,
        text: token.text,
        style: style,
        startTokenIndex: visualTokenIndex,
      );
    }

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
      text: TextSpan(style: widget.baseStyle, children: spans),
    );
  }

  int _appendAnimatedTextSpans({
    required List<InlineSpan> spans,
    required String text,
    required TextStyle style,
    required int startTokenIndex,
  }) {
    int tokenIndex = startTokenIndex;
    for (final RegExpMatch match in RegExp(r'\S+|\s+').allMatches(text)) {
      final String piece = match.group(0) ?? '';
      if (piece.isEmpty) {
        continue;
      }
      if (piece.trim().isEmpty) {
        spans.add(TextSpan(text: piece, style: style));
        continue;
      }
      final double opacity = _tokenOpacity(tokenIndex);
      spans
          .add(TextSpan(text: piece, style: _styleWithOpacity(style, opacity)));
      tokenIndex += 1;
    }
    return tokenIndex;
  }

  TextStyle _styleWithOpacity(TextStyle style, double opacity) {
    final double clamped = opacity.clamp(0.0, 1.0);
    final Color color = (style.color ??
            DefaultTextStyle.of(context).style.color ??
            Colors.black)
        .withValues(alpha: clamped);
    final Color? decorationColor =
        style.decorationColor?.withValues(alpha: clamped);
    return style.copyWith(color: color, decorationColor: decorationColor);
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
