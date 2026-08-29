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

  /// What this block puts on the screen, in pieces, with origins.
  ///
  /// The switch below paints; this one says WHAT text is painted. They carry
  /// the same case labels and sit next to each other on purpose: a block type
  /// added to one and not the other is a visible omission rather than a silent
  /// disagreement between the screen and everything that reads this.
  ///
  /// It used to live in the analysis file as a second, shorter switch — nine
  /// cases against the eighteen here — and the missing nine were found one
  /// review round at a time.
  _BlockProjection _projectBlock(MarkdownRenderNode node) {
    final _SourceSlice paragraph =
        _paragraphSlice(node.raw, 0, node.content).newlinesAsSpaces();

    switch (node.type) {
      case 'atx_heading':
      case 'setext_heading':
        return _BlockProjection(<_SourceSlice>[
          _headingSlice(node.raw, 0, node.type),
        ]);
      case 'paragraph':
        final String normalizedRaw = _normalizedRaw(node.raw);
        if (_parseFootnoteDefinitions(normalizedRaw).isNotEmpty) {
          return _definitionProjection(node);
        }
        final List<String>? cells = _tableCellsOrNull(normalizedRaw);
        if (cells != null) {
          return _BlockProjection(
              _orderedSlices(_normalizedSlice(node.raw, 0), cells));
        }
        return _BlockProjection(<_SourceSlice>[paragraph]);
      case 'list':
      case 'list_item':
        return _BlockProjection(_orderedSlices(
          _normalizedSlice(node.raw, 0),
          _parseListNode(node)
              .items
              .map((_ParsedListItem item) => item.text)
              .toList(growable: false),
        ));
      case 'block_quote':
        final _SourceSlice quote = _quoteSlice(node.raw, 0);
        final _CalloutData? callout = _parseCallout(quote.text);
        if (callout == null) {
          return _BlockProjection(<_SourceSlice>[quote]);
        }
        final int at = quote.offsets.isEmpty ? 0 : quote.offsets.first;
        return _BlockProjection(
          <_SourceSlice>[quote.locate(callout.body, 0, at)],
          // The title is drawn by a plain `Text`, so it is literal — a custom
          // title like `**Danger**` shows its asterisks.
          literalPrefix: _SourceSlice.generated(callout.title, at),
        );
      case 'fenced_code_block':
      case 'indented_code_block':
        return _BlockProjection(
          <_SourceSlice>[_codeSlice(node.raw, 0, node.type)],
          verbatim: true,
        );
      case 'thematic_break':
      case 'pipe_table_delimiter_row':
        return const _BlockProjection(<_SourceSlice>[]);
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
        final List<String> cells =
            _tableCellsOrNull(_normalizedRaw(node.raw), loose: true) ??
                const <String>[];
        return _BlockProjection(cells.isEmpty
            ? <_SourceSlice>[_contentOrRawSlice(node)]
            : _orderedSlices(_normalizedSlice(node.raw, 0), cells));
      case 'html_block':
        if (suppressRawHtml) {
          if (_isRawTextHtmlOpening(node.raw)) {
            return const _BlockProjection(<_SourceSlice>[]);
          }
          return _BlockProjection(<_SourceSlice>[paragraph]);
        }
        // Not suppressed: an `_HtmlBlockCard` parses the HTML and paints only
        // its DOM text. Projecting that is a third derivation of "what does
        // this HTML show", so it is deliberately not attempted here — the
        // configuration has no consumer today, and the report says so.
        return const _BlockProjection(<_SourceSlice>[], approximate: true);
      case 'front_matter':
        // A metadata block hands its normalized text straight to the inline
        // renderer, keeping the line breaks. No paragraph folding.
        return _BlockProjection(<_SourceSlice>[
          _normalizedSlice(node.raw, 0).trim(),
        ]);
      case 'link_reference_definition':
      case 'footnote_definition':
        return _definitionProjection(node);
      default:
        return _BlockProjection(<_SourceSlice>[paragraph]);
    }
  }

  /// `id: body` per definition, the way the definition block paints them.
  _BlockProjection _definitionProjection(MarkdownRenderNode node) {
    final _SourceSlice source = _normalizedSlice(node.raw, 0);
    final int at = source.offsets.isEmpty ? 0 : source.offsets.first;
    final List<_SourceSlice> pieces = <_SourceSlice>[];
    int cursor = 0;
    for (final _FootnoteDefinition definition
        in _parseFootnoteDefinitions(_normalizedRaw(node.raw))) {
      final _SourceSlice body = source.locate(definition.body, cursor, at);
      cursor = source.endOf(definition.body, cursor);
      pieces.add(_SourceSlice.generated('${definition.id}: ', at) + body);
    }
    if (pieces.isEmpty) {
      pieces.add(source.trim());
    }
    return _BlockProjection(pieces);
  }

  List<String>? _tableCellsOrNull(String normalizedRaw, {bool loose = false}) {
    _ParsedTable? table = _parseMarkdownTable(normalizedRaw);
    if (table == null && (loose || normalizedRaw.contains('\n'))) {
      table = _parseMarkdownTable(
        normalizedRaw,
        allowLooseWithoutDelimiter: true,
        minLooseRowsWithoutDelimiter: 2,
      );
    }
    if (table == null) {
      return null;
    }
    return <String>[
      ...table.headers,
      for (final List<String> row in table.rows) ...row,
    ];
  }

  Widget _buildRenderedBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    switch (node.type) {
      case 'atx_heading':
      case 'setext_heading':
        return _buildHeadingBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'paragraph':
        final String normalizedRaw = _normalizedRaw(node.raw);
        if (_parseFootnoteDefinitions(normalizedRaw).isNotEmpty) {
          return _buildFootnoteDefinitionBlock(
            context,
            node,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
        }
        _ParsedTable? paragraphTable = _parseMarkdownTable(normalizedRaw);
        if (paragraphTable == null && normalizedRaw.contains('\n')) {
          paragraphTable = _parseMarkdownTable(
            normalizedRaw,
            allowLooseWithoutDelimiter: true,
            minLooseRowsWithoutDelimiter: 2,
          );
        }
        if (paragraphTable != null) {
          return _buildTableWidget(
            context,
            paragraphTable,
            source: _normalizedSlice(node.raw, 0),
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
        }
        return _buildParagraphBlock(
          context,
          _paragraphSlice(node.raw, 0, node.content),
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'list':
      case 'list_item':
        return _buildListBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'block_quote':
        return _buildQuoteBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'fenced_code_block':
      case 'indented_code_block':
        return _buildCodeBlock(context, node);
      case 'thematic_break':
        return Divider(
          height: 1,
          thickness: 1,
          color: markdownTheme.thematicBreakColor ?? const Color(0xFF30363D),
        );
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
        return _buildTableBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'pipe_table_delimiter_row':
        return const SizedBox.shrink();
      case 'html_block':
        if (suppressRawHtml) {
          if (_isRawTextHtmlOpening(node.raw)) {
            // Raw data, not prose — painting it would show a stylesheet or a
            // script body where the answer should be.
            return const SizedBox.shrink();
          }
          // Otherwise the same rule as everywhere else: hide the tags, keep
          // the text. This is deliberately the ordinary paragraph path — the
          // inline scan it runs is the one the analysis runs, with the same
          // flag, so the two answers cannot disagree about what this paints.
          return _buildParagraphBlock(
            context,
            _paragraphSlice(node.raw, 0, node.content),
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
        }
        return _HtmlBlockCard(
          html: _normalizedRaw(node.raw),
          onLinkTap: (String url) => _onLinkPressed(context, url),
          paragraphTextStyle: markdownTheme.paragraphTextStyle ??
              Theme.of(context).textTheme.bodyLarge,
        );
      case 'front_matter':
        return _buildMetadataBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'link_reference_definition':
      case 'footnote_definition':
        return _buildFootnoteDefinitionBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      default:
        return _buildParagraphBlock(
          context,
          _paragraphSlice(node.raw, 0, node.content),
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
    }
  }

  Widget _buildHeadingBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final int level = _headingLevelForNode(node);
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
      _headingSlice(node.raw, 0, node.type),
      baseStyle: style,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }

  Widget _buildParagraphBlock(
    BuildContext context,
    _SourceSlice text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final _SourceSlice paragraph = text.newlinesAsSpaces();
    final String normalizedParagraph = paragraph.text;
    final TextStyle paragraphStyle = markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);

    final _LatexMatch? displayLatex =
        _matchSingleDisplayLatex(normalizedParagraph);
    if (displayLatex != null) {
      return _buildDisplayLatexBlock(context, displayLatex, paragraphStyle);
    }

    final _InlineImageMatch? image =
        _matchSingleInlineImage(normalizedParagraph);
    if (image != null) {
      return _buildImageBlock(context, image);
    }

    return _buildInlineMarkdown(
      context,
      paragraph,
      baseStyle: paragraphStyle,
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
