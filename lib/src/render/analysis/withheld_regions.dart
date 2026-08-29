part of '../view.dart';

/// What a renderer configured to hide unresolved destinations would not draw.
///
/// Rendering answers "what goes on screen". Anything that maps painted text
/// back onto its source — a reveal cursor, an audio-sync ledger, a caption
/// timeline — needs the complement of that answer, in source coordinates. It
/// is the same scan, so it must not be a second implementation of the grammar:
/// that is exactly the copy #2343 exists to remove.
final class WithheldMarkdownRegions {
  /// Creates a report. Prefer [analyzeWithheldMarkdownRegions].
  const WithheldMarkdownRegions({
    required this.safeEndCodeUnits,
    required this.hiddenCodeUnitRanges,
    required this.visibleText,
    required this.visibleSourceOffsets,
  });

  /// Length of the longest prefix of the source that can be drawn without
  /// showing a destination that has not arrived yet.
  ///
  /// UTF-16 code units, the unit Dart's `String` is indexed in — not bytes.
  final int safeEndCodeUnits;

  /// Ranges inside that prefix which produce no painted text, ascending and
  /// non-overlapping. `[start, end)`, in the same code-unit coordinates.
  final List<(int start, int end)> hiddenCodeUnitRanges;

  /// The text a reader actually sees, with the syntax that produced it gone.
  ///
  /// `**bold**` contributes `bold`; a link contributes its label; a suppressed
  /// tag contributes nothing. Blocks are separated by a single newline.
  ///
  /// This is not the source with ranges cut out of it. Cutting joins whatever
  /// sat either side of a removed range, and the join can read as syntax the
  /// scan never saw — `Hi [a]<i></i>(https://x)` becomes `Hi [a](https://x)`,
  /// a link that exists in no version of the input. Anything that re-parses
  /// such a string then disagrees with the screen.
  final String visibleText;

  /// For each code unit of [visibleText], where it came from in the source.
  ///
  /// Same length as [visibleText]. This is the half that cannot be recovered
  /// afterwards: given only the visible text, a caller has to align it back to
  /// the source by guessing, and a guess that fails is indistinguishable from
  /// one that succeeds.
  ///
  /// Characters with no verbatim source — an image's alt text, a footnote
  /// marker — all report the start of the construct that produced them.
  final List<int> visibleSourceOffsets;
}

/// Report which parts of [source] a renderer would refuse to draw.
///
/// Takes the source and nothing else on purpose. The block offsets carried by
/// [MarkdownRenderNode] are named `startByte` but hold UTF-16 code-unit
/// indices on the pure-Dart path and real byte offsets on the native one, so
/// accepting caller-supplied blocks would make the unit of the returned
/// coordinates depend on which parser the caller happened to use. Everything
/// here is measured in one unit against one string.
///
/// [hideLinkReferenceDefinitions] is for callers that drop those blocks before
/// handing them to the renderer, as the mobile adapter does. The block IS
/// painted by the default renderer, so the analysis cannot decide this on its
/// own — a caller that removes it and does not say so gets a report describing
/// text that is not on its screen.
///
/// Every other flag here means exactly what it means on
/// [StreamingMarkdownRenderView] — including
/// [allowUnclosedInlineDelimiters], which changes where emphasis ends and so
/// changes where a nested scan reports from. Pass the same values the view is
/// configured with, or the two answers describe different renderings, and
/// nothing observes the difference.
WithheldMarkdownRegions analyzeWithheldMarkdownRegions(
  String source, {
  bool withholdIncompleteDestinations = true,
  bool suppressRawHtml = true,
  bool sourceComplete = false,
  bool allowUnclosedInlineDelimiters = false,
  bool hideLinkReferenceDefinitions = false,
}) {
  if (source.isEmpty) {
    return const WithheldMarkdownRegions(
      safeEndCodeUnits: 0,
      hiddenCodeUnitRanges: <(int, int)>[],
      visibleText: '',
      visibleSourceOffsets: <int>[],
    );
  }

  // A lone CR is a line ending in CommonMark and is not one to the block
  // parser, which splits on LF alone. Rewriting it to `\n` before parsing was
  // tried and is worse: the analysis then splits blocks differently from
  // whichever parser produced the blocks being rendered, so a reported range
  // can point at text that IS on screen — and the caller excises it, which
  // desynchronises everything downstream that counts characters.
  //
  // There is no reading of a lone CR that both parsers agree on, so the
  // analysis stops at the first one instead of guessing. It over-hides the
  // remainder of such a message; a lone CR does not occur in the content this
  // is built for, and over-hiding is the direction that cannot leak.
  final int loneCarriageReturn = _firstLoneCarriageReturn(source);
  final RopeString rope = RopeString()..append(source);
  final MarkdownDocument document = const RopeMarkdownParser().parse(rope);

  // Definitions first: a reference link whose definition has not arrived is an
  // unresolved destination, and that is decided by the whole document, not by
  // the block the reference sits in.
  final Map<String, String> references = <String, String>{};
  for (final MarkdownBlockNode block in document.blocks) {
    if (block is GenericBlockNode &&
        block.type == 'link_reference_definition') {
      _addLinkReferencesFromRaw(
        source.substring(block.start, block.end),
        references,
      );
    }
  }

  final StreamingMarkdownRenderView projections = _projectionsView();
  final List<(int, int)> hidden = <(int, int)>[];
  final List<int> visibleUnits = <int>[];
  final List<int> visibleOffsets = <int>[];
  int safeEnd = loneCarriageReturn == -1 ? source.length : loneCarriageReturn;

  // Blocks are separated by one newline in the visible text. It comes from no
  // single source character, so it reports the end of the block it follows —
  // monotonic, and never inside anything.
  // Block spacing is decided HERE and nowhere else. A block's own slice ends
  // with the newline that terminated it, and the renderer draws that as part
  // of the block, not as a gap — so trailing newlines are dropped and this is
  // the single place a gap comes from. Otherwise the two sources of newline
  // add up and the visible text has gaps the screen does not.
  int blockStart = 0;

  void endBlock() {
    // Trailing first, then leading: a block whose tags were suppressed can
    // start with the line break that followed the opening tag, and that is a
    // gap for the same reason the trailing one is.
    while (visibleUnits.length > blockStart &&
        visibleUnits.last == 10 /* \n */) {
      visibleUnits.removeLast();
      visibleOffsets.removeLast();
    }
    while (visibleUnits.length > blockStart &&
        visibleUnits[blockStart] == 10) {
      visibleUnits.removeAt(blockStart);
      visibleOffsets.removeAt(blockStart);
    }
  }

  // Deferred: a block that turns out to paint nothing must not leave a gap
  // behind it. Emitting the separator up front gave a tag-only HTML block one
  // newline and the block after it another, which shifted every later offset.
  bool separatorPending = false;

  void flushSeparator() {
    if (!separatorPending) {
      return;
    }
    separatorPending = false;
    if (visibleUnits.isNotEmpty) {
      visibleUnits.add(10);
      // The end of the block it follows, not the start of the next one: a
      // cursor reading this must not jump across the blank source between
      // them before it has accounted for the separator itself.
      visibleOffsets.add(visibleOffsets.last + 1);
    }
    blockStart = visibleUnits.length;
  }

  void separateBlocks() {
    endBlock();
    separatorPending = true;
  }

  void addUnit(int unit, int sourceOffset) {
    flushSeparator();
    visibleUnits.add(unit);
    visibleOffsets.add(sourceOffset);
  }

  void addSlice(_SourceSlice slice) {
    for (int k = 0; k < slice.text.length; k++) {
      addUnit(slice.text.codeUnitAt(k), slice.offsets[k]);
    }
  }

  for (final MarkdownBlockNode block in document.blocks) {
    final String blockRaw = source.substring(block.start, block.end);

    if (hideLinkReferenceDefinitions &&
        block is GenericBlockNode &&
        block.type == 'link_reference_definition') {
      continue;
    }

    if (_blockHasNoInlineContent(block)) {
      // Not inline-parsed, but a code block is still text on the screen, and
      // anything counting painted characters has to count those too. It comes
      // from the renderer's own extraction — fences and indentation removed
      // exactly as the renderer removes them, rather than found by searching
      // the source for the content, which matches the info string first when
      // a fence's first code line repeats it.
      if (_isCodeBlock(block)) {
        final _SourceSlice code =
            _codeSlice(blockRaw, block.start, _blockTypeOf(block));
        if (code.text.isNotEmpty) {
          separateBlocks();
          addSlice(code);
        }
      }
      continue;
    }
    if (suppressRawHtml && _isRawTextHtmlBlock(block, source)) {
      // Nothing inside these is prose, so the block parser's extent IS the
      // hidden range — no second scan for where the element ends.
      hidden.add((block.start, block.end));
      continue;
    }

    // Every OTHER block of raw HTML gets no rule of its own. Suppressing raw
    // HTML means hiding the TAGS, and the inline scan below already does that
    // wherever they appear. Treating every `html_block` as unpaintable was a
    // coarser second copy of the same decision, and it dropped the prose
    // between the tags: `<div>\nanswer\n</div>` painted nothing at all.
    final _InlineParser parser = _InlineParser(
      references: references,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
      suppressRawHtml: suppressRawHtml,
      sourceComplete: sourceComplete,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    // THE string the renderer inline-parses for this block — not the raw
    // slice. Scanning the raw slice was why headings kept their `#`, quotes
    // kept their `>` and paragraphs kept hard line breaks the screen folds
    // into spaces: the analysis was answering about a different string.
    for (final _SourceSlice inline
        in _inlineSlicesForBlock(block, blockRaw, projections)) {
      if (inline.isEmpty) {
        continue;
      }

      final _InlineParseResult result = parser.scan(inline.text);

      // Offsets are into `inline.text`; the slice says where each of those
      // characters lives in the document.
      int sourceAt(int indexInSlice) => indexInSlice < inline.offsets.length
          ? inline.offsets[indexInSlice]
          : inline.sourceEnd;

      // Each piece is its own line on screen — a list item, a table cell, a
      // callout title above its body — so each gets its own separator.
      separateBlocks();
      for (final _InlineToken token in result.tokens) {
        final String painted = _paintedTextOf(token);
        if (painted.isEmpty) {
          continue;
        }
        // A token whose text is not a verbatim slice has no per-character
        // origin, so all of it reports the construct that produced it.
        final bool verbatim = token.isVerbatimSlice;
        for (int k = 0; k < painted.length; k++) {
          addUnit(painted.codeUnitAt(k),
              sourceAt(token.visibleSourceStart + (verbatim ? k : 0)));
        }
      }
      for (final (int start, int end) range in result.hiddenRanges) {
        hidden.add((sourceAt(range.$1), sourceAt(range.$2 - 1) + 1));
      }
      final int? withheldFrom = result.withheldFrom;
      if (withheldFrom != null) {
        final int boundary =
            withheldFrom == 0 ? block.start : sourceAt(withheldFrom - 1) + 1;
        if (boundary < safeEnd) {
          safeEnd = boundary;
        }
      }
    }
  }

  endBlock();

  // Clip to the boundary rather than filtering on the start alone: a range
  // that straddles it would otherwise reach the caller with an end past the
  // string it is about to be applied to.
  final List<(int, int)> clipped = <(int, int)>[];
  for (final (int start, int end) range in hidden) {
    if (range.$1 >= safeEnd) {
      continue;
    }
    clipped.add((range.$1, range.$2 > safeEnd ? safeEnd : range.$2));
  }
  return WithheldMarkdownRegions(
    safeEndCodeUnits: safeEnd,
    hiddenCodeUnitRanges: List<(int, int)>.unmodifiable(clipped),
    visibleText: String.fromCharCodes(visibleUnits),
    visibleSourceOffsets: List<int>.unmodifiable(visibleOffsets),
  );
}

/// Index of the first CR that is not part of a CRLF, or -1.
int _firstLoneCarriageReturn(String source) {
  for (int i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 13 &&
        (i + 1 >= source.length || source.codeUnitAt(i + 1) != 10)) {
      return i;
    }
  }
  return -1;
}

/// Whether this block's CONTENT is raw data rather than prose.
///
/// CommonMark gives `script`, `style`, `pre` and `textarea` raw-text content,
/// and a comment is raw throughout. Hiding only their tags would paint a
/// stylesheet or a script body as if it were the answer.
///
/// The test is the block's opening only. Where such an element ENDS — closing
/// tag, blank line, or end of input — was already decided by the block parser
/// that produced this node, and re-deriving it here was a hand-written second
/// answer that disagreed with the first (an unclosed `<script>` at end of
/// input is the case that separates them).
bool _isRawTextHtmlBlock(MarkdownBlockNode block, String source) {
  if (block is! GenericBlockNode || block.type != 'html_block') {
    return false;
  }
  return _isRawTextHtmlOpening(source.substring(block.start, block.end));
}

/// The same test on a block's raw text, for the two render-side callers.
bool _isRawTextHtmlOpening(String raw) {
  final String opening = raw.trimLeft().toLowerCase();
  if (opening.startsWith('<!--')) {
    return true;
  }
  for (final String name in const <String>['script', 'style', 'pre', 'textarea']) {
    // `<pre>` and `<pre class=…>` are the element; `<prefix>` is not.
    final int after = 1 + name.length;
    if (!opening.startsWith('<$name')) {
      continue;
    }
    if (after >= opening.length ||
        !_isHtmlTagNameChar(opening.codeUnitAt(after))) {
      return true;
    }
  }
  return false;
}

/// What this token puts on the screen.
///
/// A LaTeX span shows its expression rendered, and those glyphs correspond to
/// the expression, so it contributes that.
///
/// Two kinds deliberately contribute nothing, for the same reason: what they
/// paint is not knowable from the source.
///
/// A footnote REFERENCE paints a number, and the numbering is assigned by the
/// renderer from the whole document, which this scan does not have.
///
/// An inline IMAGE paints the image once it loads, nothing while it is
/// loading, and a fallback line if it fails — three different screens for one
/// source, decided at runtime. Reporting its alt text unconditionally would
/// disagree with all three. This under-counts a failed image's fallback, and
/// that is the honest direction: the report says less than the screen shows
/// rather than claiming text that is usually not there.
String _paintedTextOf(_InlineToken token) {
  if (token.isImage || token.isFootnoteReference) {
    return '';
  }
  if (token.isLatex) {
    return token.latexExpression ?? '';
  }
  return token.text;
}

/// A configuration-only view, used to reach the renderer's own projections.
///
/// They are extension methods on the view, and the analysis has to call the
/// SAME ones — a second copy of "how a list splits into items" is the thing
/// this file exists to stop. Constructing one costs nothing; nothing is built.
/// `debugMarkdownForSelectedPlainText` reaches them the same way.
StreamingMarkdownRenderView _projectionsView() =>
    const StreamingMarkdownRenderView(nodes: <MarkdownRenderNode>[]);

MarkdownRenderNode _renderNodeFor(String raw, String type) =>
    MarkdownRenderNode(
      type: type,
      depth: 0,
      startByte: 0,
      endByte: raw.length,
      startRow: 0,
      endRow: 0,
      raw: raw,
      content: raw,
    );

List<String> _tableCellTexts(
    StreamingMarkdownRenderView view, String blockRaw) {
  final _ParsedTable? table = view._parseMarkdownTable(
    view._normalizedRaw(blockRaw),
    allowLooseWithoutDelimiter: true,
    minLooseRowsWithoutDelimiter: 2,
  );
  if (table == null) {
    return const <String>[];
  }
  return <String>[
    ...table.headers,
    for (final List<String> row in table.rows) ...row,
  ];
}

String _blockTypeOf(MarkdownBlockNode block) {
  if (block is CodeFenceNode) {
    return 'fenced_code_block';
  }
  if (block is HeadingNode) {
    return block.type;
  }
  if (block is ListNode) {
    return 'list';
  }
  return block is GenericBlockNode ? block.type : '';
}

bool _isCodeBlock(MarkdownBlockNode block) =>
    block is CodeFenceNode ||
    (block is GenericBlockNode && block.type == 'indented_code_block');

/// The string this block's inline content is parsed from, with origins.
///
/// One function, and the renderer's own extraction behind every branch — so
/// "which part of this block is inline text" has one answer instead of one per
/// consumer.
List<_SourceSlice> _inlineSlicesForBlock(
  MarkdownBlockNode block,
  String blockRaw,
  StreamingMarkdownRenderView projections,
) {
  final String type = _blockTypeOf(block);
  switch (type) {
    case 'atx_heading':
    case 'setext_heading':
      return <_SourceSlice>[_headingSlice(blockRaw, block.start, type)];
    case 'block_quote':
      final _SourceSlice quote = _quoteSlice(blockRaw, block.start);
      final _CalloutData? callout = projections._parseCallout(quote.text);
      if (callout == null) {
        return <_SourceSlice>[quote];
      }
      // The title is generated (`[!NOTE]` becomes `Note`), so it reports the
      // marker it replaced rather than pretending to be a slice of it.
      final int at = quote.offsets.isEmpty ? block.start : quote.offsets.first;
      return <_SourceSlice>[
        _SourceSlice(callout.title, List<int>.filled(callout.title.length, at)),
        quote.locate(callout.body, 0, at),
      ];
    case 'list':
    case 'list_item':
      return _orderedSlices(
        _normalizedSlice(blockRaw, block.start),
        projections
            ._parseListNode(_renderNodeFor(blockRaw, type))
            .items
            .map((_ParsedListItem item) => item.text)
            .toList(growable: false),
      );
    case 'pipe_table':
    case 'table':
    case 'pipe_table_header':
    case 'pipe_table_row':
      return _orderedSlices(
        _normalizedSlice(blockRaw, block.start),
        _tableCellTexts(projections, blockRaw),
      );
    default:
      return <_SourceSlice>[
        _paragraphSlice(
          blockRaw,
          block.start,
          block is GenericBlockNode ? block.content : '',
        ).newlinesAsSpaces(),
      ];
  }
}

/// Blocks whose text is never inline-parsed, so nothing in them can leak.
///
/// Hiding a URL that a code fence is deliberately showing would be the
/// over-hiding failure — the one that looks like success in a leak test.
bool _blockHasNoInlineContent(MarkdownBlockNode block) {
  if (block is CodeFenceNode) {
    return true;
  }
  return block is GenericBlockNode &&
      (block.type == 'indented_code_block' ||
          // Paints a rule and a nothing respectively — no text either way, so
          // treating their source as inline content credited `***` and a
          // table's `|---|` as characters a reader could see.
          block.type == 'thematic_break' ||
          block.type == 'pipe_table_delimiter_row');
}
