part of '../view.dart';

extension _StreamingMarkdownBlockWidgets on StreamingMarkdownRenderView {
  Widget _buildListBlock(
    BuildContext context,
    _ListPlan plan, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedList parsed = plan.list;
    final TextStyle baseStyle = _paragraphStyle(context);
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenArrivalDelay;
    int tokenStartIndex = 0;
    int plainTextStart = 0;
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < parsed.items.length; i++) {
      final _ParsedListItem item = parsed.items[i];
      final int itemPlainTextStart = plainTextStart;
      final int itemPlainTextLength = _inlineSelectionPlainTextLength(
        item.text,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
      final Widget itemRow = Padding(
        key: ValueKey<String>('list_item_${item.stableKey}'),
        padding: EdgeInsets.only(left: item.level * 18.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildListMarker(item, baseStyle),
              ),
            ),
            Expanded(
              child: _buildInlineMarkdown(
                context,
                item.body,
                tokenStartIndex: tokenStartIndex,
                plainTextStart: itemPlainTextStart,
                baseStyle: baseStyle,
                linkReferences: linkReferences,
                footnoteNumbers: footnoteNumbers,
              ),
            ),
          ],
        ),
      );
      children.add(
        _TokenLayoutGate(
          initialDelay: tokenScheduleOrigin == null
              ? resolvedTokenStep * tokenStartIndex
              : Duration.zero,
          scheduledStart: tokenScheduleOrigin?.add(
            resolvedTokenStep * tokenStartIndex,
          ),
          child: itemRow,
        ),
      );
      tokenStartIndex += _countAnimatedTokenUnits(
        item.text,
        linkReferences: linkReferences,
      );
      plainTextStart += itemPlainTextLength;
      if (i < parsed.items.length - 1) {
        children.add(const SizedBox(height: 4));
        plainTextStart += 1;
      }
    }

    final Widget visibleList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    return visibleList;
  }

  Widget _buildQuoteBlock(
    BuildContext context,
    _QuotePlan plan, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _CalloutData? callout = plan.callout;
    final Color calloutColor = _calloutColor(callout?.kind);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: calloutColor, width: 3)),
        color: markdownTheme.quoteBackgroundColor ?? const Color(0xFF161B22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (callout != null) ...[
            Row(
              children: [
                Icon(_calloutIcon(callout.kind), size: 16, color: calloutColor),
                const SizedBox(width: 6),
                Text(
                  callout.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: calloutColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _buildInlineMarkdown(
            context,
            plan.body,
            baseStyle: markdownTheme.paragraphTextStyle ??
                Theme.of(context).textTheme.bodyLarge,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, _CodePlan plan) {
    final String code = plan.body.text;
    final String language = plan.language?.text ?? '';
    final bool showHeader = plan.showHeader;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            markdownTheme.codeBlockBackgroundColor ?? const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: markdownTheme.codeBlockHeaderBackgroundColor ??
                    const Color(0xFF161B22),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: language.isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            language,
                            style: markdownTheme.codeBlockLanguageTextStyle ??
                                const TextStyle(
                                  color: Color(0xFF8B949E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                  ),
                  if (showCodeBlockCopyButton)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        tooltip: 'Copy code',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color:
                            markdownTheme.codeBlockLanguageTextStyle?.color ??
                                const Color(0xFF8B949E),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                        },
                        icon: const Icon(Icons.copy_all_outlined),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildAnimatedCodeText(context, code),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedCodeText(BuildContext context, String code) {
    final TextStyle style = markdownTheme.codeBlockTextStyle ??
        const TextStyle(
          color: Color(0xFFE6EDF3),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
        );
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;
    final bool compacted = _TokenCompactionScope.isCompacted(context);

    final List<InlineSpan> spans = <InlineSpan>[];
    _appendTokenizedTextSpans(
      spans: spans,
      text: code,
      style: style,
      startTokenIndex: 0,
      fadeDuration: tokenFadeDuration,
      fadeCurve: tokenFadeInCurve,
      tokenStaggerDelay: resolvedTokenStep,
      tokenScheduleOrigin: tokenScheduleOrigin,
      tokenAnimationBuilder: tokenAnimationBuilder,
      animatePerWord: !compacted,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: RichText(
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        selectionRegistrar:
            enableTextSelection ? SelectionContainer.maybeOf(context) : null,
        selectionColor: markdownTheme.selectionColor ?? const Color(0x6658A6FF),
        text: TextSpan(style: style, children: spans),
      ),
    );
  }
}
