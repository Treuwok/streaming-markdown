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
  const _SourceSlice(this.text, this.offsets);

  /// The whole of [text] starting at [start] in the source.
  factory _SourceSlice.whole(String text, int start) => _SourceSlice(
        text,
        List<int>.generate(text.length, (int i) => start + i, growable: false),
      );

  static const _SourceSlice empty = _SourceSlice('', <int>[]);

  final String text;

  /// Source offset of each code unit of [text]. Same length as [text].
  final List<int> offsets;

  bool get isEmpty => text.isEmpty;

  /// Source offset just past the last surviving character, or -1 when empty.
  int get sourceEnd => offsets.isEmpty ? -1 : offsets.last + 1;

  _SourceSlice _range(int start, int end) => _SourceSlice(
        text.substring(start, end),
        offsets.sublist(start, end),
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

  _SourceSlice trimRight() {
    int end = text.length;
    while (end > 0 && _isTrimmable(text.codeUnitAt(end - 1))) {
      end--;
    }
    return end == text.length ? this : _range(0, end);
  }

  _SourceSlice trim() {
    int start = 0;
    int end = text.length;
    while (start < end && _isTrimmable(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isTrimmable(text.codeUnitAt(end - 1))) {
      end--;
    }
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
    return _SourceSlice(text.replaceAll('\n', ' '), offsets);
  }

  static bool _isTrimmable(int unit) =>
      unit == 32 || unit == 9 || unit == 10 || unit == 13;
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
  return source.stripLeading(RegExp(r'^\s{0,3}#{1,6}\s*')).trim();
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
