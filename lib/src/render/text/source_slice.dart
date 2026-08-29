part of '../view.dart';

/// A string derived from the source by DELETION, and where each surviving
/// character came from.
///
/// Every per-block text the renderer paints is built this way: carriage
/// returns dropped, fences and quote markers and heading hashes stripped,
/// whitespace trimmed. Nothing is invented — each character of the result is a
/// character of the source. That is what makes provenance derivable instead of
/// searched for: do the same deletions, and carry the origin along.
///
/// Before this, the derivation existed only as `String`-returning helpers, so
/// the origins were discarded at the moment they were still known. Anything
/// needing them afterwards had to guess by searching the source for the text —
/// which is ambiguous exactly when the text also occurs somewhere it did not
/// come from.
final class _SourceSlice {
  const _SourceSlice(this.text, this.offsets, {this.located = true});

  /// The whole of [text] starting at [start] in the source.
  factory _SourceSlice.whole(String text, int start) => _SourceSlice(
        text,
        List<int>.generate(text.length, (int i) => start + i, growable: false),
      );

  static const _SourceSlice empty = _SourceSlice('', <int>[]);

  final String text;

  /// Source offset of each code unit of [text]. Same length as [text].
  final List<int> offsets;

  /// False when [offsets] are a fallback rather than real positions.
  ///
  /// A projection that REWRITES rather than deletes — a table cell whose
  /// `\\|` became `|` — has no character-for-character origin, so the whole
  /// run points at one place. Reporting hidden RANGES from such a piece would
  /// hand a consumer coordinates that are wrong, and a consumer that cuts text
  /// at wrong coordinates corrupts it. Callers check this instead.
  final bool located;

  bool get isEmpty => text.isEmpty;

  /// Source offset just past the last surviving character, or -1 when empty.
  int get sourceEnd => offsets.isEmpty ? -1 : offsets.last + 1;

  _SourceSlice _range(int start, int end) => _SourceSlice(
        text.substring(start, end),
        offsets.sublist(start, end),
        located: located,
      );

  _SourceSlice withoutCarriageReturns() {
    if (!text.contains('\r')) {
      return this;
    }
    final StringBuffer kept = StringBuffer();
    final List<int> keptOffsets = <int>[];
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 13 /* \r */) {
        continue;
      }
      kept.writeCharCode(text.codeUnitAt(i));
      keptOffsets.add(offsets[i]);
    }
    return _SourceSlice(kept.toString(), keptOffsets);
  }

  // Both delegate to Dart's own `String` methods to decide HOW MUCH to remove,
  // so the definition of whitespace is identical to the methods these replaced
  // — Unicode, not just ASCII. Hand-rolling the predicate silently started
  // painting non-breaking spaces the renderer had always trimmed.
  _SourceSlice trimRight() {
    final int end = text.trimRight().length;
    return end == text.length ? this : _range(0, end);
  }

  _SourceSlice trim() {
    final int start = text.length - text.trimLeft().length;
    final int end = start + text.trim().length;
    return (start == 0 && end == text.length) ? this : _range(start, end);
  }

  List<_SourceSlice> splitLines() {
    final List<_SourceSlice> lines = <_SourceSlice>[];
    int lineStart = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10 /* \n */) {
        lines.add(_range(lineStart, i));
        lineStart = i + 1;
      }
    }
    lines.add(_range(lineStart, text.length));
    return lines;
  }

  /// Drops the leading characters [pattern] matches at the start of [text].
  _SourceSlice stripLeading(RegExp pattern) {
    final RegExpMatch? match = pattern.firstMatch(text);
    if (match == null || match.start != 0) {
      return this;
    }
    return _range(match.end, text.length);
  }

  /// Substitutes each newline with a space, keeping its origin.
  ///
  /// A substitution, not a deletion: the character on screen is a space and it
  /// came from that newline, so the ledger still points at a real position.
  _SourceSlice newlinesAsSpaces() {
    if (!text.contains('\n')) {
      return this;
    }
    return _SourceSlice(text.replaceAll('\n', ' '), offsets, located: located);
  }

  /// This slice followed by [other].
  _SourceSlice operator +(_SourceSlice other) => _SourceSlice(
        text + other.text,
        <int>[...offsets, ...other.offsets],
        located: located && other.located,
      );

  /// Literal text with no source of its own, pinned to [at].
  ///
  /// For characters the renderer GENERATES — a callout's `Note`, the `: `
  /// between a footnote's id and its body. They are on the screen, so they
  /// must be counted, and they point at the construct that produced them
  /// because there is nothing truer to point at.
  static _SourceSlice generated(String text, int at) =>
      _SourceSlice(text, List<int>.filled(text.length, at), located: false);

  /// Drops the trailing characters [pattern] matches at the end of [text].
  _SourceSlice stripTrailing(RegExp pattern) {
    final Iterable<RegExpMatch> matches = pattern.allMatches(text);
    if (matches.isEmpty || matches.last.end != text.length) {
      return this;
    }
    return _range(0, matches.last.start);
  }

  /// The sub-slice of this one holding [needle], searched from [from].
  ///
  /// For projections that produce a contiguous substring of their input — a
  /// list item after its marker, a table cell between its pipes, a callout
  /// body after its tag — this recovers the origins without threading them
  /// through the parser that produced the substring.
  ///
  /// The search is confined to THIS slice and the caller advances [from] in
  /// order, which is what keeps it exact: a repeated cell matches its own
  /// occurrence, and a fence's first code line cannot match the info string
  /// on the opening line because that line is not in this slice.
  ///
  /// Returns a slice pinned to [fallbackOffset] when the text is not a
  /// substring — a projection that rewrote rather than deleted. Coarse, and
  /// deliberately not a guess at a better position.
  _SourceSlice locate(String needle, int from, int fallbackOffset) {
    if (needle.isEmpty) {
      return _SourceSlice.empty;
    }
    final int at = text.indexOf(needle, from.clamp(0, text.length));
    if (at == -1) {
      return _SourceSlice(
        needle,
        List<int>.filled(needle.length, fallbackOffset),
        located: false,
      );
    }
    return _range(at, at + needle.length);
  }

  /// Index just past [needle] when found from [from], else [from].
  int endOf(String needle, int from) {
    final int at = text.indexOf(needle, from.clamp(0, text.length));
    return at == -1 ? from : at + needle.length;
  }

}

/// Rejoins lines with `\n`, each separator reporting the end of the line it
/// follows — a real source position, so the ledger never points past the text.
_SourceSlice _joinSliceLines(List<_SourceSlice> lines) {
  if (lines.isEmpty) {
    return _SourceSlice.empty;
  }
  final StringBuffer text = StringBuffer();
  final List<int> offsets = <int>[];
  for (int i = 0; i < lines.length; i++) {
    if (i > 0) {
      text.write('\n');
      final int previousEnd = lines[i - 1].sourceEnd;
      offsets.add(previousEnd == -1
          ? (lines[i].offsets.isEmpty ? 0 : lines[i].offsets.first)
          : previousEnd);
    }
    text.write(lines[i].text);
    offsets.addAll(lines[i].offsets);
  }
  return _SourceSlice(text.toString(), offsets);
}

// ── Per-block extraction, shared by the renderer and the analysis ──
//
// These used to be `String`-returning methods on the render view, so the
// analysis could not reach them and scanned the raw block slice instead. That
// is why its answer contained `#` markers, fence lines and quote arrows that
// the screen does not show.


/// The paragraph's painted text, and where each character came from.
///
/// [rawStart] is where [raw] begins in the document, so the origins are in
/// document coordinates rather than the block's own.
_SourceSlice _paragraphSlice(String raw, int rawStart, String content) {
  final _SourceSlice slice =
      _normalizedSlice(raw, rawStart).trim();
  if (slice.text.isNotEmpty) {
    return slice;
  }
  // The fallback path exists for blocks whose raw is not the text. It has no
  // recoverable origins, so it reports the block start throughout — coarse,
  // and marked as such rather than guessed.
  final String trimmed = content.trim();
  return _SourceSlice(
    trimmed,
    List<int>.filled(trimmed.length, rawStart),
  );
}


/// The heading's painted text — the `#` markers are syntax, not content.
///
/// Derived from the raw slice rather than the parser's assembled `content`,
/// because that string is built with a buffer and no longer knows where its
/// characters came from. The two agree on the text; only one of them can
/// also say where it is.
_SourceSlice _headingSlice(String raw, int rawStart, String type) {
  final _SourceSlice source = _normalizedSlice(raw, rawStart).trim();
  if (type == 'setext_heading') {
    return _stripSetextDelimiterSlice(source);
  }
  // The closing run is optional syntax, not content: CommonMark lets
  // `# Title #` close the way it opened, and the parser's own content had it
  // removed. Leaving it in put a `#` on the screen that was not there before.
  return source
      .stripLeading(RegExp(r'^\s{0,3}#{1,6}\s*'))
      .stripTrailing(RegExp(r'\s+#+\s*$'))
      .trim();
}


_SourceSlice _stripSetextDelimiterSlice(_SourceSlice text) {
  final List<_SourceSlice> lines =
      text.withoutCarriageReturns().trimRight().splitLines();
  if (lines.length < 2 || !_isSetextDelimiterLine(lines.last.text)) {
    return text.trim();
  }
  return _joinSliceLines(lines.sublist(0, lines.length - 1)).trim();
}


/// [_normalizedRaw] with origins kept.
_SourceSlice _normalizedSlice(String raw, int rawStart) =>
    _SourceSlice.whole(raw, rawStart).withoutCarriageReturns().trimRight();


/// The quote's painted text — the `>` markers are syntax, not content.
_SourceSlice _quoteSlice(String raw, int rawStart) => _joinSliceLines(
      _normalizedSlice(raw, rawStart)
          .splitLines()
          .map((_SourceSlice line) =>
              line.stripLeading(RegExp(r'^\s*>\s?')))
          .toList(growable: false),
    ).trim();


/// The code block's painted text — fences and indentation are syntax.
_SourceSlice _codeSlice(String raw, int rawStart, String type) {
  final _SourceSlice normalized = _normalizedSlice(raw, rawStart);
  if (type == 'fenced_code_block') {
    final List<_SourceSlice> lines = normalized.splitLines();
    if (lines.isNotEmpty &&
        RegExp(r'^\s*(```+|~~~+)').hasMatch(lines.first.text)) {
      lines.removeAt(0);
    }
    if (lines.isNotEmpty &&
        RegExp(r'^\s*(```+|~~~+)\s*$').hasMatch(lines.last.text)) {
      lines.removeLast();
    }
    return _joinSliceLines(lines).trimRight();
  }
  if (type == 'indented_code_block') {
    return _joinSliceLines(
      normalized
          .splitLines()
          .map((_SourceSlice line) =>
              line.stripLeading(RegExp(r'^(?: {4}|\t)')))
          .toList(growable: false),
    ).trimRight();
  }
  return normalized;
}

bool _isSetextDelimiterLine(String line) {
  return RegExp(r'^\s{0,3}(=+|-+)\s*$').hasMatch(line);
}

/// Walks [texts] through [parent] in order, one slice each.
///
/// The renderer runs a separate inline scan per list item and per table cell,
/// so the analysis has to see the same pieces — not one string with the
/// markers and pipes still in it.
List<_SourceSlice> _orderedSlices(_SourceSlice parent, List<String> texts) {
  final List<_SourceSlice> slices = <_SourceSlice>[];
  int cursor = 0;
  for (final String text in texts) {
    if (text.isEmpty) {
      continue;
    }
    slices.add(parent.locate(
        text, cursor, parent.offsets.isEmpty ? 0 : parent.offsets.first));
    cursor = parent.endOf(text, cursor);
  }
  return slices;
}

/// The slice for the next list item body, advancing [readCursor] past it.
///
/// Items are taken in render order, so a repeated body matches its own line
/// rather than an earlier identical one.
_SourceSlice _nextItemSlice(
  _SourceSlice parent,
  String itemText,
  int Function() readCursor,
  void Function(int) writeCursor,
) {
  final int from = readCursor();
  final _SourceSlice found = parent.locate(
    itemText,
    from,
    parent.offsets.isEmpty ? 0 : parent.offsets.first,
  );
  writeCursor(parent.endOf(itemText, from));
  return found;
}

/// [_contentOrRaw] with origins kept. The parser's assembled `content` has
/// none, so that branch reports the block start throughout.
_SourceSlice _contentOrRawSliceOf(String raw, int rawStart, String content) {
  final String trimmedContent = content.trim();
  if (trimmedContent.isNotEmpty) {
    final _SourceSlice fromRaw = _normalizedSlice(raw, rawStart).trim();
    if (fromRaw.text == trimmedContent) {
      return fromRaw;
    }
    return _SourceSlice(
      trimmedContent,
      List<int>.filled(trimmedContent.length, rawStart),
    );
  }
  return _normalizedSlice(raw, rawStart).trim();
}
