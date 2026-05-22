part of '../view.dart';

class _MarkdownSelectionProjection {
  const _MarkdownSelectionProjection(this.segments);

  final List<_MarkdownSelectionSegment> segments;

  String get fullPlainText {
    final StringBuffer plain = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write('\n\n');
      }
      plain.write(segments[i].plainText);
    }
    return plain.toString();
  }

  _MarkdownSelectionRange? findRangeForSelectedPlainText(
    String selectedPlainText, {
    int? preferredStart,
  }) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      return null;
    }
    final String document = fullPlainText;
    if (document.isEmpty || selected.length > document.length) {
      return null;
    }

    int bestStart = -1;
    int searchFrom = 0;
    while (searchFrom <= document.length) {
      final int hit = document.indexOf(selected, searchFrom);
      if (hit < 0) {
        break;
      }
      if (preferredStart == null) {
        bestStart = hit;
        break;
      }
      if (bestStart < 0 ||
          (hit - preferredStart).abs() < (bestStart - preferredStart).abs()) {
        bestStart = hit;
      }
      searchFrom = hit + 1;
    }
    if (bestStart < 0) {
      return null;
    }
    return _MarkdownSelectionRange(
      start: bestStart,
      end: bestStart + selected.length,
    );
  }

  String plainTextForRange(_MarkdownSelectionRange range) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write('\n\n');
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final int selectionStart = range.start.clamp(0, plain.length);
    final int selectionEnd = range.end.clamp(selectionStart, plain.length);
    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange segmentRange in ranges) {
      final _MarkdownSelectionSegment segment = segmentRange.segment;
      final bool isEmptySegment = segmentRange.start == segmentRange.end;
      final bool intersects = isEmptySegment
          ? selectionStart < segmentRange.start &&
              selectionEnd > segmentRange.start
          : selectionStart < segmentRange.end &&
              selectionEnd > segmentRange.start;
      if (!intersects) {
        continue;
      }
      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (selectionStart - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
              (selectionEnd - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }
    return out.toString();
  }

  String markdownForRange(_MarkdownSelectionRange range) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write('\n\n');
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final int selectionStart = range.start.clamp(0, plain.length);
    final int selectionEnd = range.end.clamp(selectionStart, plain.length);
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange segmentRange in ranges) {
      final _MarkdownSelectionSegment segment = segmentRange.segment;
      final bool isEmptySegment = segmentRange.start == segmentRange.end;
      final bool intersects = isEmptySegment
          ? selectionStart < segmentRange.start &&
              selectionEnd > segmentRange.start
          : selectionStart < segmentRange.end &&
              selectionEnd > segmentRange.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (selectionStart - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
              (selectionEnd - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }

    return out.toString();
  }

  String plainTextForSelectedPlainText(String selectedPlainText) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      return '';
    }

    for (final _MarkdownSelectionSegment segment in segments) {
      if (segment.plainText == selected) {
        return selected;
      }
    }

    final String withDisplaySeparators = _plainTextForDocumentSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (withDisplaySeparators.isNotEmpty) {
      return withDisplaySeparators;
    }

    final String compact = _plainTextForDocumentSelection(
      selected,
      plainSeparator: '',
    );
    if (compact.isNotEmpty) {
      return compact;
    }

    final String whitespaceNormalized = _plainTextForWhitespaceNormalizedSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (whitespaceNormalized.isNotEmpty) {
      return whitespaceNormalized;
    }

    final String containedSegments = _plainTextForContainedSegments(selected);
    if (containedSegments.isNotEmpty) {
      return containedSegments;
    }

    return selected;
  }

  String markdownForSelectedPlainText(String selectedPlainText) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      if (segments.length == 1 &&
          segments.first.plainText.isEmpty &&
          segments.first.markdownText.isNotEmpty) {
        return segments.first.markdownText;
      }
      return '';
    }

    for (final _MarkdownSelectionSegment segment in segments) {
      final String exact = segment.markdownForPlainText(selected);
      if (exact.isNotEmpty) {
        return exact;
      }
    }

    final String withDisplaySeparators = _markdownForDocumentSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (withDisplaySeparators.isNotEmpty) {
      return withDisplaySeparators;
    }

    final String compact = _markdownForDocumentSelection(
      selected,
      plainSeparator: '',
    );
    if (compact.isNotEmpty) {
      return compact;
    }

    final String whitespaceNormalized =
        _markdownForWhitespaceNormalizedSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (whitespaceNormalized.isNotEmpty) {
      return whitespaceNormalized;
    }

    final String containedSegments = _markdownForContainedSegments(selected);
    if (containedSegments.isNotEmpty) {
      return containedSegments;
    }

    return selected;
  }

  String _plainTextForWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final _NormalizedDocumentSelectionMatch? match =
        _matchWhitespaceNormalizedSelection(
      selectedPlainText,
      plainSeparator: plainSeparator,
    );
    if (match == null) {
      return '';
    }

    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange range in match.ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? match.selectionStart < range.start &&
              match.selectionEnd > range.start
          : match.selectionStart < range.end &&
              match.selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (match.selectionStart - range.start)
                  .clamp(0, segment.plainText.length),
              (match.selectionEnd - range.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }
    return out.toString();
  }

  String _markdownForWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final _NormalizedDocumentSelectionMatch? match =
        _matchWhitespaceNormalizedSelection(
      selectedPlainText,
      plainSeparator: plainSeparator,
    );
    if (match == null) {
      return '';
    }

    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange range in match.ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? match.selectionStart < range.start &&
              match.selectionEnd > range.start
          : match.selectionStart < range.end &&
              match.selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (match.selectionStart - range.start)
                  .clamp(0, segment.plainText.length),
              (match.selectionEnd - range.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }
    return out.toString();
  }

  _NormalizedDocumentSelectionMatch? _matchWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final _NormalizedSelectionText normalizedDocument =
        _NormalizedSelectionText.from(plain.toString());
    final _NormalizedSelectionText normalizedSelected =
        _NormalizedSelectionText.from(selectedPlainText);
    if (normalizedDocument.value.isEmpty || normalizedSelected.value.isEmpty) {
      return null;
    }

    final int normalizedStart = normalizedDocument.value.indexOf(
      normalizedSelected.value,
    );
    if (normalizedStart < 0) {
      return null;
    }
    final int normalizedEnd =
        normalizedStart + normalizedSelected.value.length;
    final int selectionStart =
        normalizedDocument.originalIndexAt(normalizedStart);
    final int selectionEnd =
        normalizedDocument.originalEndIndexAt(normalizedEnd - 1);
    return _NormalizedDocumentSelectionMatch(
      ranges: ranges,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
    );
  }

  String _plainTextForContainedSegments(String selectedPlainText) {
    final List<int> selectedIndexes = <int>[];
    for (int i = 0; i < segments.length; i++) {
      final String plainText = segments[i].plainText;
      if (plainText.isNotEmpty && selectedPlainText.contains(plainText)) {
        selectedIndexes.add(i);
      }
    }
    if (selectedIndexes.length <= 1) {
      return '';
    }

    final int first = selectedIndexes.first;
    final int last = selectedIndexes.last;
    final StringBuffer out = StringBuffer();
    for (int i = first; i <= last; i++) {
      final _MarkdownSelectionSegment segment = segments[i];
      if (segment.plainText.isEmpty && segment.markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(segment.plainText);
    }
    return out.toString();
  }

  String _markdownForContainedSegments(String selectedPlainText) {
    final List<int> selectedIndexes = <int>[];
    for (int i = 0; i < segments.length; i++) {
      final String plainText = segments[i].plainText;
      if (plainText.isNotEmpty && selectedPlainText.contains(plainText)) {
        selectedIndexes.add(i);
      }
    }
    if (selectedIndexes.length <= 1) {
      return '';
    }

    final int first = selectedIndexes.first;
    final int last = selectedIndexes.last;
    final StringBuffer out = StringBuffer();
    for (int i = first; i <= last; i++) {
      final _MarkdownSelectionSegment segment = segments[i];
      if (segment.plainText.isEmpty && segment.markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(segment.markdownText);
    }
    return out.toString();
  }

  String _plainTextForDocumentSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final String plainText = plain.toString();
    final int selectionStart = plainText.indexOf(selectedPlainText);
    if (selectionStart < 0) {
      return '';
    }
    final int selectionEnd = selectionStart + selectedPlainText.length;
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange range in ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? selectionStart < range.start && selectionEnd > range.start
          : selectionStart < range.end && selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (selectionStart - range.start).clamp(0, segment.plainText.length),
              (selectionEnd - range.start).clamp(0, segment.plainText.length),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }

    return out.toString();
  }

  String _markdownForDocumentSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final String plainText = plain.toString();
    final int selectionStart = plainText.indexOf(selectedPlainText);
    if (selectionStart < 0) {
      return '';
    }
    final int selectionEnd = selectionStart + selectedPlainText.length;
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange range in ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? selectionStart < range.start && selectionEnd > range.start
          : selectionStart < range.end && selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (selectionStart - range.start).clamp(0, segment.plainText.length),
              (selectionEnd - range.start).clamp(0, segment.plainText.length),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }

    return out.toString();
  }
}

class _MarkdownSelectionRange {
  const _MarkdownSelectionRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _NormalizedDocumentSelectionMatch {
  const _NormalizedDocumentSelectionMatch({
    required this.ranges,
    required this.selectionStart,
    required this.selectionEnd,
  });

  final List<_MarkdownSelectionSegmentRange> ranges;
  final int selectionStart;
  final int selectionEnd;
}

class _NormalizedSelectionText {
  _NormalizedSelectionText._(this.value, this._indexMap);

  final String value;
  final List<int> _indexMap;

  factory _NormalizedSelectionText.from(String source) {
    final StringBuffer normalized = StringBuffer();
    final List<int> indexMap = <int>[];
    for (int i = 0; i < source.length; i++) {
      final String char = source[i];
      if (_isWhitespace(char)) {
        continue;
      }
      normalized.write(char);
      indexMap.add(i);
    }
    return _NormalizedSelectionText._(normalized.toString(), indexMap);
  }

  int originalIndexAt(int normalizedIndex) {
    return _indexMap[normalizedIndex];
  }

  int originalEndIndexAt(int normalizedIndex) {
    return _indexMap[normalizedIndex] + 1;
  }

  static bool _isWhitespace(String char) {
    switch (char) {
      case ' ':
      case '\n':
      case '\r':
      case '\t':
      case '\f':
      case '\v':
        return true;
      default:
        return false;
    }
  }
}
