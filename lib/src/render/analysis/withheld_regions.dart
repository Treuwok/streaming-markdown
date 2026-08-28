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

  /// Whether any raw HTML was found. The caller needs this to decide whether
  /// the painted text can be derived from the source at all.
  bool get hasHiddenRanges => hiddenCodeUnitRanges.isNotEmpty;
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
/// [withholdIncompleteDestinations] and [suppressRawHtml] mean exactly what
/// they mean on [StreamingMarkdownRenderView]; pass the same values the view
/// is configured with, or the two answers describe different renderings.
WithheldMarkdownRegions analyzeWithheldMarkdownRegions(
  String source, {
  bool withholdIncompleteDestinations = true,
  bool suppressRawHtml = true,
  bool sourceComplete = false,
}) {
  if (source.isEmpty) {
    return const WithheldMarkdownRegions(
      safeEndCodeUnits: 0,
      hiddenCodeUnitRanges: <(int, int)>[],
    );
  }

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
  int safeEnd = source.length;

  for (final MarkdownBlockNode block in document.blocks) {
    if (_blockHasNoInlineContent(block)) {
      continue;
    }
    if (suppressRawHtml && _isRawHtmlBlock(block)) {
      // A whole block of raw HTML paints nothing, so all of it is hidden —
      // and its coordinates matter for the same reason an inline tag's do.
      hidden.add((block.start, block.end));
      continue;
    }

    final _InlineParser parser = _InlineParser(
      references: references,
      withholdIncompleteDestinations: withholdIncompleteDestinations,
      suppressRawHtml: suppressRawHtml,
      sourceComplete: sourceComplete,
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

  hidden.removeWhere(((int, int) range) => range.$1 >= safeEnd);
  return WithheldMarkdownRegions(
    safeEndCodeUnits: safeEnd,
    hiddenCodeUnitRanges: List<(int, int)>.unmodifiable(hidden),
  );
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

bool _isRawHtmlBlock(MarkdownBlockNode block) =>
    block is GenericBlockNode && block.type == 'html_block';
