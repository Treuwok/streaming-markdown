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
/// Takes the SAME [blocks] handed to [AnimatedStreamingMarkdown], because the
/// question is about that rendering and no other.
///
/// Deriving the blocks here from the source was the previous shape, and it
/// made this a second answer to "how does this document split into blocks":
/// one that ran the pure-Dart parser while a device runs the native one,
/// walked top-level nodes while the renderer walks a flattened tree, and read
/// a lone CR differently from whichever parser produced what was on screen.
/// Six rounds of review landed in this one file, each on a different
/// consequence of that one thing. There is nothing to derive now.
///
/// [source] is the string those blocks were parsed from — the coordinate space
/// the whole report is expressed in. Handing over a different string is the
/// one new way to get this wrong, so a debug assertion checks the pair.
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
///
/// ## The one thing it still cannot see
///
/// A `blockBuilder` that replaces text. The builder can return any widget for
/// any block, and it is not passed here. One that wraps or decorates the
/// default widget is fine, and so is one that adds chrome — a typing cursor is
/// not part of the answer's text. One that HIDES a block or paints different
/// words makes this report wrong for that block, and the caller has to say so.
/// [hideLinkReferenceDefinitions] is that channel for the one case in this
/// repo; there is no general one.
WithheldMarkdownRegions analyzeWithheldMarkdownRegions(
  String source, {
  required List<MarkdownRenderNode> blocks,
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
  assert(
    blocks.every((MarkdownRenderNode node) =>
        node.startCodeUnit >= 0 &&
        node.endCodeUnit <= source.length &&
        node.startCodeUnit <= node.endCodeUnit &&
        source.substring(node.startCodeUnit, node.endCodeUnit) == node.raw),
    'blocks must be the parse of this exact source',
  );

  final StreamingMarkdownRenderView projections =
      _projectionsView(suppressRawHtml: suppressRawHtml);

  // Definitions first: a reference link whose definition has not arrived is an
  // unresolved destination, and that is decided by the whole document, not by
  // the block the reference sits in.
  //
  // Both scans are the renderer's own, over the renderer's own nodes. They
  // used to be hand-written here over a locally parsed document, which is how
  // a footnote definition inside a quote came to be numbered by the renderer
  // and not by this: the renderer reads every node, this read the top level.
  final Map<String, int> footnoteNumbers =
      projections._extractFootnoteNumbers(blocks);
  final Map<String, String> references =
      projections._extractLinkReferences(blocks);

  final List<(int, int)> hidden = <(int, int)>[];
  final List<int> visibleUnits = <int>[];
  final List<int> visibleOffsets = <int>[];

  // The boundary is DERIVED from these two, once, after the scan, rather than
  // being one variable that several places lower for several reasons. That
  // earlier shape was broken in both directions across the reviews that led
  // here — sometimes claiming safety over text nobody had read, sometimes
  // hiding text that had been read — because the rule was never written down:
  //
  //     the boundary may be P only if the scan read the blocks covering
  //     [0, P).
  //
  // "Covering" is the honest word. Source that no block covers is not read by
  // anyone, and it is treated as safe here because the renderer paints nothing
  // there either. That holds as long as the blocks handed in are the renderer's
  // own; a caller who filters them first gets a boundary over its own gaps.
  //
  // Two quantities because there are two questions, and answering both with
  // one number is what kept going wrong. "Nobody read this" is not "a rule hid
  // this": the first is about the scan, the second about the content, and the
  // safe direction for one is the unsafe direction for the other.

  // How far the scan actually got. Nothing has stopped it yet, so it starts at
  // the end; the only thing that lowers it is a block the scan cannot read, at
  // which point the scan stops. Everything from that block's start onwards is
  // then unread — the blocks arrive in source order (`block/pipeline.dart`
  // sorts by start), so there is nothing further along that was read earlier.
  int scannedUpTo = source.length;

  // The lowest boundary an explicit withholding rule produced — one past the
  // last character that rule still vouches for, which is NOT the position the
  // rule fired at (see where this is assigned).
  int withheldAt = source.length;

  // Whether any withholding rule could fire at all. Both flags, not just the
  // destination one: an unfinished `href` inside an HTML tag is withheld by
  // `suppressRawHtml` alone — `_InlineParser`'s `incompleteHtml` case in
  // `text/inline.dart` (named, not line-numbered: a line number here goes
  // stale on an unrelated edit above it, silently and with nothing to catch
  // it).
  final bool anythingCouldBeWithheld =
      withholdIncompleteDestinations || suppressRawHtml;

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

  /// [nextOffset] is where the character about to be appended came from.
  ///
  /// The separator wants to sit just after the block it follows rather than at
  /// the start of the next one, so that a cursor reading it does not jump the
  /// blank source between them before accounting for the separator itself.
  /// But "just after" was computed as `last + 1` and nothing checked it
  /// against where the next character actually is — and the caller knows,
  /// because it is appending that character. When the preceding piece is
  /// generated text (a header, a label: one position repeated for its whole
  /// run) and the next piece begins at that same position, `last + 1` steps
  /// PAST it and the ledger goes backwards, which is the one thing a reveal
  /// cursor cannot survive.
  ///
  /// So it is told, instead of guessing.
  void flushSeparator(int nextOffset) {
    if (!separatorPending) {
      return;
    }
    separatorPending = false;
    if (visibleUnits.isNotEmpty) {
      visibleUnits.add(10);
      final int after = visibleOffsets.last + 1;
      visibleOffsets.add(after < nextOffset ? after : nextOffset);
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
    flushSeparator(sourceOffset);
    visibleUnits.add(unit);
    visibleOffsets.add(sourceOffset);
  }

  void addSlice(_SourceSlice slice) {
    for (int k = 0; k < slice.text.length; k++) {
      addUnit(slice.text.codeUnitAt(k), slice.offsets[k]);
    }
  }

  // Which of the parser's nodes become blocks on screen is the renderer's
  // decision — flattened tree, container children, orphan table fragments. It
  // is one function, and this calls it rather than owning a second opinion.
  for (final MarkdownRenderNode block
      in projections._collectRenderableBlocks(blocks)) {
    // Coordinates that do not slice back out are a LEDGER fault: nobody knows
    // where this block's characters live, so it contributes none of them. That
    // is true whatever the withholding flags say, and gating it on them (which
    // the single predicate here used to do) left a caller with both rules off
    // holding a table's worth of offsets pointing at the wrong characters.
    //
    // Whether it also moves the BOUNDARY is a separate question with a
    // separate answer, and conflating the two is the whole subject of this
    // function: the boundary only has to retreat if something in the
    // unexamined block COULD have been withheld. With every rule off, nothing
    // could, and retreating would cost a table and everything after it for
    // nothing.
    if (!_hasUsableCoordinates(source, block)) {
      if (!anythingCouldBeWithheld) {
        continue;
      }
      // The scan stops here, and saying so is the whole mechanism: the loop
      // ends, so nothing past this point can raise the water mark, and the
      // boundary below can only land at or before this block's start.
      //
      // Not a clamp on a shared variable. The earlier shape let this site
      // choose a POSITION, and the tempting one — the exact code unit the
      // trouble starts at — was wrong every time, because the part BEFORE it
      // was not read either: this block is skipped in one piece.
      // `[x](https://secret.example\rmore` handed the destination straight to
      // the caller that way.
      //
      // Stopping is also what keeps the ledger clean, and it is worth being
      // exact about why, because the obvious reason is false: NOT every
      // character the loop would still have produced lives past this point.
      // The block separator does not — `flushSeparator` gives it an offset
      // derived from the block BEFORE it, just under the boundary, so the clip
      // at the end of this function keeps it and `visibleText` ends in a `\n`
      // separating the last block from nothing. Ending the loop is what stops
      // that separator from ever being asked for.
      scannedUpTo = block.startCodeUnit;
      break;
    }

    // A grammar the parser and the spec disagree about is a WITHHOLDING fault,
    // not a ledger one: this block's coordinates are fine and the renderer read
    // it exactly the same way, so the ledger can speak for it. What it cannot
    // do is promise that a half-arrived destination further on was seen.
    if (anythingCouldBeWithheld &&
        !_readsUnderTheSameGrammar(source, block,
            sourceComplete: sourceComplete)) {
      scannedUpTo = block.startCodeUnit;
      break;
    }

    if (hideLinkReferenceDefinitions &&
        block.type == 'link_reference_definition') {
      continue;
    }

    if (suppressRawHtml && _isRawTextHtmlBlock(block)) {
      // Nothing inside these is prose, so the block parser's extent IS the
      // hidden range — no second scan for where the element ends.
      hidden.add((block.startCodeUnit, block.endCodeUnit));
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
    final _BlockProjection projection = projections._planBlock(block).projection;
    for (final _ProjectedPiece projected in projection.pieces) {
      final _SourceSlice inline =
          _rebase(projected.slice, block.startCodeUnit);
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
      if (emptyTokens && projected.emptyTokenFallback) {
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
            ? (inline.offsets.isEmpty
                ? block.startCodeUnit
                : inline.offsets.first)
            : sourceAt(withheldFrom - 1) + 1;
        if (boundary < withheldAt) {
          withheldAt = boundary;
        }
      }
    }
  }

  endBlock();

  // The one place the boundary is decided, from the two quantities above.
  // Whichever stopped earlier wins: a rule that hid something, or the scan
  // running out of source it had read.
  final int safeEnd = scannedUpTo < withheldAt ? scannedUpTo : withheldAt;

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
  // The ledger stops where the boundary stops. It is the same report, and one
  // that says "safe up to here" in one field while handing over text from past
  // there in another is worse than no boundary at all — the caller that trusts
  // the text has no way to learn the boundary was smaller.
  //
  // Not hypothetical. A block can span the boundary — the boundary is set by
  // an unfinished destination inside one piece, and the other pieces of that
  // block go on projecting — so text from past it reached `visibleText` with
  // offsets 33 beyond `safeEndCodeUnits`.
  //
  // Clipped here, at the one place the report is built, rather than in each
  // projection — a projection added later cannot get this wrong, because it
  // does not get to decide it.
  int ledgerEnd = visibleUnits.length;
  for (int i = 0; i < visibleOffsets.length; i++) {
    if (visibleOffsets[i] >= safeEnd) {
      ledgerEnd = i;
      break;
    }
  }

  return WithheldMarkdownRegions(
    safeEndCodeUnits: safeEnd,
    hiddenCodeUnitRanges: List<(int, int)>.unmodifiable(clipped),
    visibleText: String.fromCharCodes(visibleUnits.take(ledgerEnd)),
    visibleSourceOffsets:
        List<int>.unmodifiable(visibleOffsets.take(ledgerEnd)),
  );
}

/// The same report for a caller that holds only the source.
///
/// Parses with [MarkdownSyncParser] — the parser
/// `AnimatedStreamingMarkdown.fromMarkdown` uses to turn a string into the
/// blocks it renders — so this reaches the answer by the renderer's own route
/// rather than a parallel one.
///
/// Prefer the form above wherever the blocks are already in hand: one parse
/// instead of two, and the blocks that are actually on the screen rather than
/// a list that ought to equal them.
WithheldMarkdownRegions analyzeWithheldMarkdownRegionsOfSource(
  String source, {
  // The same default `AnimatedStreamingMarkdown.fromMarkdown` uses, and for
  // the same reason it exists: this is that constructor's counterpart, so a
  // caller who takes both string-only entry points gets one parser. `auto`
  // here would let this run native while the widget beside it runs Dart —
  // which is the divergence the whole change removes, reintroduced in a
  // default value.
  MarkdownSyncParserBackend backend = MarkdownSyncParserBackend.dart,
  bool withholdIncompleteDestinations = true,
  bool suppressRawHtml = true,
  bool sourceComplete = false,
  bool allowUnclosedInlineDelimiters = false,
  bool hideLinkReferenceDefinitions = false,
}) =>
    analyzeWithheldMarkdownRegions(
      source,
      blocks: MarkdownSyncParser.parseMarkdown(source, backend: backend).blocks,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
      suppressRawHtml: suppressRawHtml,
      sourceComplete: sourceComplete,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
      hideLinkReferenceDefinitions: hideLinkReferenceDefinitions,
    );

/// Whether [block]'s span really is where its text lives in [source].
///
/// `_collectRenderableBlocks` synthesizes one kind of node — a table the
/// parser only emitted loose rows for — and it trims each row before joining
/// them, so the node spans the original rows while its text is shorter. The
/// renderer is fine with that; it only paints the text. This report is
/// coordinates, and a projection rebased on that node's start puts every cell
/// after the first removed space in the wrong place.
///
/// Length, not content: every way a node stops slicing back out makes its text
/// SHORTER, and the exact comparison is a substring of the whole document per
/// block per parse on a streaming path. The exact one runs in debug, on the
/// caller's blocks, at the top of the scan.
bool _hasUsableCoordinates(String source, MarkdownRenderNode block) =>
    block.startCodeUnit >= 0 &&
    block.endCodeUnit <= source.length &&
    block.endCodeUnit - block.startCodeUnit == block.raw.length;

/// Whether [block] was parsed under the line-ending rules CommonMark uses.
///
/// A lone CR — one not followed by LF — is a line ending to the spec and is
/// not one to a parser that splits on LF alone. Everything after it in that
/// block was read under a grammar the spec disagrees with: an unclosed fence
/// swallows the rest and paints it verbatim, URL included. This is a product
/// contract on the consuming app, not a nicety — `SMD-W-05 unsupported link
/// grammar stays fail-closed` says a half-arrived destination must not be
/// painted at all. It was deleted once, in #5, on the strength of a comment
/// beside it that explained a DIFFERENT reason (the analysis and the renderer
/// disagreeing about CR) which really had gone away. The URL went on screen.
///
/// Derived from the block, not from the source string, and that is the whole
/// point: a parser that DOES treat the CR as a line ending ends the block
/// there, no block spans it, and nothing stops. Scanning the source instead
/// penalised the native backend for something it gets right.
///
/// A bool, deliberately — as is [_hasUsableCoordinates]. The predicate these
/// two replaced returned a POSITION, and every attempt to use that position as
/// the boundary leaked: a block that fails either test is skipped WHOLE, so
/// the part before the trouble was never read either. The caller derives the
/// boundary from where the scan stopped; there is no position to get wrong.
///
/// Reading [source] here is safe only because [_hasUsableCoordinates] is
/// checked first — the span has to be real before it can be indexed.
bool _readsUnderTheSameGrammar(
  String source,
  MarkdownRenderNode block, {
  required bool sourceComplete,
}) {
  for (int i = block.startCodeUnit; i < block.endCodeUnit; i++) {
    if (source.codeUnitAt(i) != 13) {
      continue;
    }
    if (i + 1 < source.length) {
      if (source.codeUnitAt(i + 1) != 10) {
        return false;
      }
      continue;
    }
    // The last code unit received. It is a lone CR only if nothing follows it
    // ever — mid-stream it is half of a CRLF that has not finished arriving,
    // and calling it lone blanks the block being typed for exactly one frame.
    // Same shape as the surrogate half the caller's parser already holds back.
    if (sourceComplete) {
      return false;
    }
  }
  return true;
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
bool _isRawTextHtmlBlock(MarkdownRenderNode block) =>
    block.type == 'html_block' && _isRawTextHtmlOpening(block.raw);

/// The same test on a block's raw text, for the two render-side callers.
bool _isRawTextHtmlOpening(String raw) {
  final String opening = raw.trimLeft().toLowerCase();
  if (opening.startsWith('<!--')) {
    return true;
  }
  return rawTextHtmlElementAt(opening) != null;
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



