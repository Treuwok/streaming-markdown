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
  });

  /// Length of the longest prefix of the source that can be drawn without
  /// showing a destination that has not arrived yet.
  ///
  /// UTF-16 code units, the unit Dart's `String` is indexed in — not bytes.
  final int safeEndCodeUnits;

  /// Ranges inside that prefix which produce no painted text, ascending and
  /// non-overlapping. `[start, end)`, in the same code-unit coordinates.
  final List<(int start, int end)> hiddenCodeUnitRanges;

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
/// Every flag here means exactly what it means on
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
}) {
  if (source.isEmpty) {
    return const WithheldMarkdownRegions(
      safeEndCodeUnits: 0,
      hiddenCodeUnitRanges: <(int, int)>[],
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

  final List<(int, int)> hidden = <(int, int)>[];
  int safeEnd = loneCarriageReturn == -1 ? source.length : loneCarriageReturn;

  for (final MarkdownBlockNode block in document.blocks) {
    if (_blockHasNoInlineContent(block)) {
      continue;
    }
    // A block of raw HTML gets no rule of its own. Suppressing raw HTML means
    // hiding the TAGS, and the inline scan below already does exactly that —
    // wherever they appear. Treating a whole `html_block` as unpaintable was a
    // second, coarser copy of that same decision, and it dropped the prose
    // between the tags: `<div>\nanswer\n</div>` painted nothing at all.
    final _InlineParser parser = _InlineParser(
      references: references,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
      suppressRawHtml: suppressRawHtml,
      sourceComplete: sourceComplete,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    final _InlineParseResult result =
        parser.scan(source.substring(block.start, block.end));
    for (final (int start, int end) range in result.hiddenRanges) {
      hidden.add((block.start + range.$1, block.start + range.$2));
    }
    final int? withheldFrom = result.withheldFrom;
    if (withheldFrom != null) {
      final int boundary = block.start + withheldFrom;
      if (boundary < safeEnd) {
        safeEnd = boundary;
      }
    }
  }

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
          block.type == 'front_matter' ||
          block.type == 'link_reference_definition');
}
