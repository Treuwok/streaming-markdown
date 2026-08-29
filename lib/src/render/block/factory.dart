part of '../view.dart';

extension _StreamingMarkdownBlockFactory on StreamingMarkdownRenderView {
  Widget _buildRenderedBlockWithRefs(
    BuildContext context,
    MarkdownRenderNode node,
    Map<String, String> linkReferences,
    Map<String, int> footnoteNumbers,
  ) {
    final Widget defaultWidget = _buildRenderedBlock(
      context,
      node,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    final StreamingMarkdownBlockBuilder? builder = customBlockBuilder;
    if (builder == null) {
      return defaultWidget;
    }
    return builder(
          context,
          StreamingMarkdownBlockBuildContext(
            node: node,
            linkReferences: linkReferences,
            defaultWidget: defaultWidget,
          ),
        ) ??
        defaultWidget;
  }

  /// THE decision about a block — see [_BlockPlan].
  ///
  /// Both the widget and the projection come out of this one switch. Adding a
  /// block type here makes it render AND report; there is no second place that
  /// can be forgotten, and no second place that can answer differently.
  _BlockPlan _planBlock(MarkdownRenderNode node) {
    switch (node.type) {
      case 'atx_heading':
      case 'setext_heading':
        final _SourceSlice text = _headingSlice(node.raw, 0, node.type);
        return _HeadingPlan(text, _headingLevelForNode(node));
      case 'list':
      case 'list_item':
        final _ParsedList list = _parseListNode(node);
        if (list.items.isEmpty) {
          return _planParagraph(_contentOrRawSlice(node));
        }
        return _ListPlan(list);
      case 'block_quote':
        final _SourceSlice quote = _quoteSlice(node.raw, 0);
        if (quote.text.isEmpty) {
          return const _NothingPlan();
        }
        // The slice, not its text: parsing a bare string would reset every
        // offset to zero and pin the whole callout to the block's first
        // character.
        final _CalloutData? callout = _parseCalloutSlices(quote);
        return _QuotePlan(callout == null ? quote : callout.bodySlice, callout);
      case 'fenced_code_block':
      case 'indented_code_block':
        return _planCode(node);
      case 'thematic_break':
        return const _ThematicBreakPlan();
      case 'pipe_table_delimiter_row':
        return const _NothingPlan();
      case 'paragraph':
        return _planParagraphBlock(node);
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
        return _planTableBlock(node);
      case 'html_block':
        if (!suppressRawHtml) {
          return _HtmlCardPlan(_normalizedRaw(node.raw));
        }
        if (_isRawTextHtmlOpening(node.raw)) {
          // Raw data, not prose — painting it would show a stylesheet or a
          // script body where the answer should be.
          return const _NothingPlan();
        }
        // Otherwise the ordinary paragraph path: hide the tags, keep the text.
        return _planParagraph(_paragraphSlice(node.raw, 0, node.content));
      case 'front_matter':
        return _planMetadata(node);
      case 'link_reference_definition':
      case 'footnote_definition':
        return _planDefinitions(node);
      default:
        return _planParagraph(_paragraphSlice(node.raw, 0, node.content));
    }
  }

  /// A paragraph node, which may turn out to be a definition list or a table.
  _BlockPlan _planParagraphBlock(MarkdownRenderNode node) {
    final _SourceSlice normalized = _normalizedSlice(node.raw, 0);
    if (_parseFootnoteDefinitionSlices(normalized).isNotEmpty) {
      return _planDefinitions(node);
    }
    _ParsedTable? table = _parseMarkdownTable(normalized);
    if (table == null && normalized.text.contains('\n')) {
      table = _parseMarkdownTable(
        normalized,
        allowLooseWithoutDelimiter: true,
        minLooseRowsWithoutDelimiter: 2,
      );
    }
    if (table != null) {
      return _planTable(table, normalized);
    }
    return _planParagraph(_paragraphSlice(node.raw, 0, node.content));
  }

  /// Ordinary prose, or the two things a lone paragraph can turn into.
  _BlockPlan _planParagraph(_SourceSlice text) {
    if (text.isEmpty) {
      return const _NothingPlan();
    }
    final _SourceSlice folded = text.newlinesAsSpaces();
    final _LatexMatch? latex = _matchSingleDisplayLatex(folded.text);
    if (latex != null) {
      return _DisplayLatexPlan(latex);
    }
    final _InlineImageMatch? image = _matchSingleInlineImage(folded.text);
    if (image != null) {
      return _ImagePlan(image);
    }
    return _ParagraphPlan(folded);
  }

  _BlockPlan _planCode(MarkdownRenderNode node) {
    final _SourceSlice body = _codeSlice(node.raw, 0, node.type);
    if (body.text.isEmpty) {
      // The code widget returns early on an empty body, before its header.
      return const _NothingPlan();
    }
    final bool indented = node.type == 'indented_code_block';
    final _SourceSlice? language = indented
        // Not in the source at all — the word the header shows for a block
        // that never named a language.
        ? _SourceSlice.generated('code', body.sourceStart)
        : _codeLanguageSlice(_normalizedSlice(node.raw, 0));
    return _CodePlan(
      body: body,
      language: language != null && language.text.isNotEmpty ? language : null,
      showCopyButton: showCodeBlockCopyButton,
    );
  }

  _BlockPlan _planTableBlock(MarkdownRenderNode node) {
    final _SourceSlice normalized = _normalizedSlice(node.raw, 0);
    final _ParsedTable? parsed = _parseMarkdownTable(
      normalized,
      allowLooseWithoutDelimiter: true,
      minLooseRowsWithoutDelimiter: 2,
    );
    if (parsed != null) {
      // Deliberately NOT remembered here. Planning is also what the analysis
      // does, on nodes it synthesises for the purpose — letting it write to
      // the renderer's snapshot cache would hand a real block someone else's
      // table. The renderer remembers what it painted, below.
      return _planTable(parsed, normalized);
    }
    final _ParsedTable? snapshot = _readTableSnapshot(node);
    if (snapshot != null) {
      return _planTable(snapshot, normalized);
    }
    return _planParagraph(_contentOrRawSlice(node));
  }

  _BlockPlan _planTable(_ParsedTable table, _SourceSlice source) => _TablePlan(
        table,
        source,
        hasRenderableCell: _tableHasRenderableCell(table),
      );

  _BlockPlan _planMetadata(MarkdownRenderNode node) {
    final _SourceSlice fromRaw = _normalizedSlice(node.raw, 0).trim();
    final _SourceSlice text =
        fromRaw.text.isNotEmpty ? fromRaw : _contentOrRawSlice(node);
    return text.text.isEmpty ? const _NothingPlan() : _MetadataPlan(text);
  }

  _BlockPlan _planDefinitions(MarkdownRenderNode node) {
    final List<_FootnoteDefinition> definitions =
        _parseFootnoteDefinitionSlices(_normalizedSlice(node.raw, 0));
    if (definitions.isEmpty) {
      return _planMetadata(node);
    }
    return _DefinitionPlan(definitions);
  }

  /// Paints [node]. Every character it draws comes out of the plan, so the
  /// screen and [_BlockPlan.projection] cannot disagree about what is on it.
  Widget _buildRenderedBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _BlockPlan plan = _planBlock(node);
    switch (plan) {
      case _NothingPlan():
        return const SizedBox.shrink();
      case _ThematicBreakPlan():
        return Divider(
          height: 1,
          thickness: 1,
          color: markdownTheme.thematicBreakColor ?? const Color(0xFF30363D),
        );
      case _HeadingPlan():
        return _buildHeadingBlock(
          context,
          plan,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _ParagraphPlan():
        return _buildInlineMarkdown(
          context,
          plan.text,
          baseStyle: _paragraphStyle(context),
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _DisplayLatexPlan():
        return _buildDisplayLatexBlock(
            context, plan.latex, _paragraphStyle(context));
      case _ImagePlan():
        return _buildImageBlock(context, plan.image);
      case _ListPlan():
        return _buildListBlock(
          context,
          plan,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _QuotePlan():
        return _buildQuoteBlock(
          context,
          plan,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _CodePlan():
        return _buildCodeBlock(context, plan);
      case _TablePlan():
        // Keeps the last good grid so a mid-stream row that stops parsing does
        // not collapse the table.
        _rememberTableSnapshot(node, plan.table);
        return _buildTableWidget(
          context,
          plan.table,
          source: plan.source,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _MetadataPlan():
        return _buildMetadataBlock(
          context,
          plan.text,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _DefinitionPlan():
        return _buildFootnoteDefinitionBlock(
          context,
          plan,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case _HtmlCardPlan():
        return _HtmlBlockCard(
          html: plan.html,
          onLinkTap: (String url) => _onLinkPressed(context, url),
          paragraphTextStyle: markdownTheme.paragraphTextStyle ??
              Theme.of(context).textTheme.bodyLarge,
        );
    }
  }

  TextStyle _paragraphStyle(BuildContext context) =>
      markdownTheme.paragraphTextStyle ??
      Theme.of(context).textTheme.bodyLarge ??
      const TextStyle(fontSize: 16);

  Widget _buildHeadingBlock(
    BuildContext context,
    _HeadingPlan plan, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final int level = plan.level;
    final TextTheme textTheme = Theme.of(context).textTheme;
    TextStyle style;
    switch (level) {
      case 1:
        style = markdownTheme.heading1TextStyle ??
            textTheme.headlineMedium ??
            const TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
        break;
      case 2:
        style = markdownTheme.heading2TextStyle ??
            textTheme.headlineSmall ??
            const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
        break;
      case 3:
        style = markdownTheme.heading3TextStyle ??
            textTheme.titleLarge ??
            const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
        break;
      case 4:
        style = markdownTheme.heading4TextStyle ??
            textTheme.titleMedium ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
        break;
      case 5:
        style = markdownTheme.heading5TextStyle ??
            textTheme.titleSmall ??
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
        break;
      default:
        style = markdownTheme.heading6TextStyle ??
            textTheme.bodyLarge ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
        break;
    }

    return _buildInlineMarkdown(
      context,
      plan.text,
      baseStyle: style,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }

  _LatexMatch? _matchSingleDisplayLatex(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final _LatexMatch? dollars = _matchLatexAt(trimmed, 0);
    if (dollars != null && dollars.display && dollars.end == trimmed.length) {
      return dollars;
    }
    return null;
  }
}
