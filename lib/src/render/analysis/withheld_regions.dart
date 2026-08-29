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
/// [hideLinkReferenceDefinitions] says the caller suppresses the DRAWING of
/// those blocks while still handing them to the renderer — what the mobile
/// adapter does, so its references keep resolving while the definition itself
/// stays off the screen.
///
/// It therefore removes the block from the projection and NOT from the
/// reference map. The default renderer draws the block, so the analysis cannot
/// decide this on its own; a caller that hides it and does not say so gets a
/// report describing text that is not on its screen.
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
  final StreamingMarkdownRenderView projections =
      _projectionsView(suppressRawHtml: suppressRawHtml);

  // Same numbering the renderer assigns: definitions in document order. It is
  // derivable here after all — the earlier note that this scan cannot know it
  // was wrong, and a footnote reference paints a character either way (the
  // number, or the id when there is no definition).
  final Map<String, int> footnoteNumbers = <String, int>{};
  for (final MarkdownBlockNode block in document.blocks) {
    for (final _FootnoteDefinition definition in projections
        ._parseFootnoteDefinitions(source.substring(block.start, block.end))) {
      final String key = _normalizeFootnoteKey(definition.id);
      if (key.isEmpty || footnoteNumbers.containsKey(key)) {
        continue;
      }
      footnoteNumbers[key] = footnoteNumbers.length + 1;
    }
  }

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

  void keepVerbatimEdges() {
    // A code block's blank first line is content. `endBlock` strips leading and
    // trailing newlines because for every OTHER block they are the gap between
    // blocks; pinning the boundary here keeps it away from this one.
    blockStart = visibleUnits.length;
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
    final _BlockProjection projection =
        projections._projectBlock(_renderNodeFor(blockRaw, _blockTypeOf(block)));
    for (final _ProjectedPiece projected in projection.pieces) {
      final _SourceSlice inline = _rebase(projected.slice, block.start);
      void beginPiece() {
        if (!projected.continuesLine) {
          separateBlocks();
        }
      }

      if (projected.literal) {
        // Drawn by a plain widget, so it is never inline-parsed: its own
        // delimiters are on the screen.
        if (inline.text.isNotEmpty) {
          beginPiece();
          addSlice(inline);
        }
        continue;
      }
      if (inline.isEmpty) {
        continue;
      }

      if (projection.verbatim) {
        // Code. Shown as-is, so its edge whitespace is content rather than
        // block syntax — the generic trimming must not reach it.
        beginPiece();
        addSlice(inline);
        keepVerbatimEdges();
        continue;
      }

      final _InlineParseResult result = parser.scan(inline.text);

      // The renderer's own fallback: with no tokens but source left over, it
      // paints what survived suppression rather than nothing — `**<b></b>**`
      // shows its asterisks. Mirroring it here keeps the two answers the same.
      //
      // It must NOT skip the range reporting below. Doing that left a comment
      // block — every character of it suppressed, so no tokens — reporting no
      // hidden ranges at all.
      final bool emptyTokens = result.tokens.isEmpty;
      if (emptyTokens) {
        final _SourceSlice survivors =
            _survivingSlice(inline, result.hiddenRanges, result.withheldFrom);
        if (survivors.text.isNotEmpty) {
          beginPiece();
          addSlice(survivors);
        }
      }

      // Offsets are into `inline.text`; the slice says where each of those
      // characters lives in the document.
      int sourceAt(int indexInSlice) => indexInSlice < inline.offsets.length
          ? inline.offsets[indexInSlice]
          : inline.sourceEnd;

      // Each piece is its own line on screen — a list item, a table cell, a
      // callout title above its body — so each gets its own separator.
      if (!emptyTokens) {
        beginPiece();
      }
      for (final _InlineToken token in result.tokens) {
        final String painted = _paintedTextOf(token, footnoteNumbers);
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
        // Trustworthy exactly when this range's characters advance through
        // the source. Generated text — a joining space, a label — reports one
        // position for its whole run, so a range over it is not a range in
        // the source and is dropped rather than reported somewhere wrong: a
        // consumer that cuts at wrong coordinates corrupts the text, which is
        // worse than cutting at none.
        //
        // Derived from the offsets themselves, so it needs no second piece of
        // state to keep in step, and it is per-RANGE where a per-slice flag
        // threw away every range in a piece for one generated character in it.
        if (!_monotonic(inline.offsets, range.$1, range.$2)) {
          continue;
        }
        hidden.add((sourceAt(range.$1), sourceAt(range.$2 - 1) + 1));
      }
      final int? withheldFrom = result.withheldFrom;
      if (withheldFrom != null) {
        // The piece's own start, not the block's: a list whose SECOND item
        // holds the unfinished destination must not discard the first.
        final int boundary = withheldFrom == 0
            ? (inline.offsets.isEmpty ? block.start : inline.offsets.first)
            : sourceAt(withheldFrom - 1) + 1;
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
/// A footnote REFERENCE paints its number, or its id when nothing defines it —
/// the same two cases the renderer chooses between, from the same numbering.
///
/// An inline IMAGE paints the image once it loads, nothing while it is
/// loading, and a fallback line if it fails — three different screens for one
/// source, decided at runtime. Reporting its alt text unconditionally would
/// disagree with all three. This under-counts a failed image's fallback, and
/// that is the honest direction: the report says less than the screen shows
/// rather than claiming text that is usually not there.
String _paintedTextOf(_InlineToken token, Map<String, int> footnoteNumbers) {
  if (token.isImage) {
    return '';
  }
  if (token.isFootnoteReference) {
    final int? number =
        _footnoteNumberForId(footnoteNumbers, token.footnoteReferenceId!);
    return number?.toString() ?? token.footnoteReferenceId!;
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
StreamingMarkdownRenderView _projectionsView({required bool suppressRawHtml}) =>
    StreamingMarkdownRenderView(
      nodes: const <MarkdownRenderNode>[],
      // The projection branches on this exactly as the painting does, so the
      // view has to be configured the way the caller configured the renderer.
      suppressRawHtml: suppressRawHtml,
    );

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


/// The projection is computed against the block's own slice, so its offsets
/// start at zero. Shift them to where the block sits in the document.
_SourceSlice _rebase(_SourceSlice slice, int blockStart) => _SourceSlice(
      slice.text,
      slice.offsets.map((int at) => at + blockStart).toList(growable: false),
      located: slice.located,
    );

/// What survives suppression when the scan produced no tokens.
///
/// The same characters `_InlineParseResult.visibleSourceOf` gives the
/// renderer, kept as a slice so they still say where they came from.
_SourceSlice _survivingSlice(
  _SourceSlice piece,
  List<(int, int)> hiddenRanges,
  int? withheldFrom,
) {
  final int end = withheldFrom ?? piece.text.length;
  final StringBuffer text = StringBuffer();
  final List<int> offsets = <int>[];
  int cursor = 0;
  void take(int from, int to) {
    for (int i = from; i < to && i < piece.text.length; i++) {
      text.writeCharCode(piece.text.codeUnitAt(i));
      offsets.add(piece.offsets[i]);
    }
  }

  for (final (int start, int stop) range in hiddenRanges) {
    if (range.$1 >= end) {
      break;
    }
    if (range.$1 > cursor) {
      take(cursor, range.$1);
    }
    cursor = range.$2 > cursor ? range.$2 : cursor;
  }
  if (cursor < end) {
    take(cursor, end);
  }
  return _SourceSlice(text.toString(), offsets);
}

/// Whether `offsets[start..end)` advance through the source.
///
/// STRICTLY increasing, not "differ by exactly one". A deletion leaves a gap —
/// normalization drops the `\r` of a CRLF, and a tag spanning one is still a
/// single run of source — while GENERATED text repeats one position for its
/// whole run. Requiring +1 rejected the first along with the second, and the
/// suppressed tag's range went unreported.
bool _monotonic(List<int> offsets, int start, int end) {
  if (start < 0 || end > offsets.length || start >= end) {
    return false;
  }
  for (int i = start + 1; i < end; i++) {
    if (offsets[i] <= offsets[i - 1]) {
      return false;
    }
  }
  return true;
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


