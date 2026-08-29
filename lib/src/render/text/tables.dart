part of '../view.dart';

extension _StreamingMarkdownTableTextParsing on StreamingMarkdownRenderView {
  /// Parses [raw] into the grid the table widget paints.
  ///
  /// [raw] is a slice rather than a string so that every cell keeps the
  /// position it was cut from. Anything that needs to know where a painted
  /// cell came from reads it off the result; nothing searches for it.
  _ParsedTable? _parseMarkdownTable(
    _SourceSlice raw, {
    bool allowLooseWithoutDelimiter = false,
    int minLooseRowsWithoutDelimiter = 1,
  }) {
    final List<_SourceSlice> lines = _firstTableLineRun(raw);
    if (lines.length < 2 && !allowLooseWithoutDelimiter) {
      return null;
    }

    int delimiterIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (_isTableDelimiterRow(lines[i])) {
        delimiterIndex = i;
        break;
      }
    }
    if (delimiterIndex < 0) {
      if (!allowLooseWithoutDelimiter) {
        return null;
      }

      final List<List<_SourceSlice>> rows = lines
          .map(_splitTableRowSlices)
          .where((List<_SourceSlice> row) => row.isNotEmpty)
          .toList(growable: false);
      if (rows.length < minLooseRowsWithoutDelimiter || rows.isEmpty) {
        return null;
      }

      int width = 0;
      for (final List<_SourceSlice> row in rows) {
        if (row.length > width) {
          width = row.length;
        }
      }
      if (width <= 0) {
        return null;
      }

      return _ParsedTable(
        headerCells: _fitTableRowToWidth(rows.first, width),
        rowCells: rows
            .skip(1)
            .map((List<_SourceSlice> row) => _fitTableRowToWidth(row, width))
            .toList(growable: false),
      );
    }

    final List<_SourceSlice> rawHeaders = delimiterIndex > 0
        ? _splitTableRowSlices(lines[delimiterIndex - 1])
        : <_SourceSlice>[];
    final List<_SourceSlice> delimiterCells =
        _splitTableRowSlices(lines[delimiterIndex]);
    int width = rawHeaders.length > delimiterCells.length
        ? rawHeaders.length
        : delimiterCells.length;

    final List<List<_SourceSlice>> rawRows = <List<_SourceSlice>>[];
    for (int i = delimiterIndex + 1; i < lines.length; i++) {
      final _SourceSlice line = lines[i].trim();
      if (line.text.isEmpty || !line.text.contains('|')) {
        continue;
      }

      final List<_SourceSlice> row = _splitTableRowSlices(line);
      if (row.isEmpty) {
        continue;
      }
      rawRows.add(row);
      if (row.length > width) {
        width = row.length;
      }
    }

    if (width <= 0) {
      return null;
    }

    // Keep table stable during streaming even when header row is not ready yet.
    return _ParsedTable(
      headerCells: _fitTableRowToWidth(rawHeaders, width),
      rowCells: rawRows
          .map((List<_SourceSlice> row) => _fitTableRowToWidth(row, width))
          .toList(growable: false),
    );
  }

  List<_SourceSlice> _firstTableLineRun(_SourceSlice raw) {
    final List<_SourceSlice> out = <_SourceSlice>[];
    bool started = false;
    for (final _SourceSlice original in raw.splitLines()) {
      final _SourceSlice line = original.trimRight();
      if (line.text.trim().isEmpty) {
        if (started) {
          break;
        }
        continue;
      }
      if (!line.text.contains('|')) {
        if (started) {
          break;
        }
        continue;
      }
      started = true;
      out.add(line);
    }
    return out;
  }

  List<_SourceSlice> _fitTableRowToWidth(List<_SourceSlice> row, int width) {
    final List<_SourceSlice> out = row.toList(growable: true);
    // A padding cell is not in the source at all — it exists because the grid
    // is rectangular and this row was short.
    final int at = out.isEmpty ? 0 : out.last.sourceEnd;
    while (out.length < width) {
      out.add(_SourceSlice.generated('', at < 0 ? 0 : at));
    }
    if (out.length > width) {
      out.removeRange(width, out.length);
    }
    return out;
  }

  bool _isTableDelimiterRow(_SourceSlice line) {
    final List<_SourceSlice> cells = _splitTableRowSlices(line);
    if (cells.isEmpty) {
      return false;
    }

    for (final _SourceSlice cell in cells) {
      final String normalized = cell.text.replaceAll(' ', '');
      if (!RegExp(r'^:?-+:?$').hasMatch(normalized)) {
        return false;
      }
    }
    return true;
  }

  /// Cells with their origins. The `String` view above is this, flattened —
  /// one implementation, so a cell's text and a cell's position can never
  /// come from two different splits.
  List<_SourceSlice> _splitTableRowSlices(_SourceSlice line) {
    final _SourceSlice slice = line.trim();
    final String value = slice.text;
    if (!value.contains('|')) {
      return <_SourceSlice>[];
    }

    final List<_SourceSlice> cells = <_SourceSlice>[];
    final _SliceBuilder current = _SliceBuilder();
    int at(int index) => slice.offsets[index];
    int codeFenceLength = 0;
    String? latexEndDelimiter;
    bool escaped = false;

    for (int i = 0; i < value.length; i++) {
      final String ch = value[i];

      if (escaped) {
        current.writeFrom(ch, at(i));
        escaped = false;
        continue;
      }

      if (latexEndDelimiter != null) {
        if (value.startsWith(latexEndDelimiter, i)) {
          current.writeFrom(latexEndDelimiter, at(i));
          i += latexEndDelimiter.length - 1;
          latexEndDelimiter = null;
          continue;
        }
        current.writeFrom(ch, at(i));
        continue;
      }

      if (ch == '\\') {
        final String? endDelimiter = _latexEndDelimiterForBackslash(value, i);
        if (endDelimiter != null) {
          latexEndDelimiter = endDelimiter;
        }
        escaped = true;
        current.writeFrom(ch, at(i));
        continue;
      }

      if (ch == r'$') {
        if (value.startsWith(r'$$', i)) {
          latexEndDelimiter = r'$$';
          current.writeFrom(r'$$', at(i));
          i += 1;
          continue;
        }
        latexEndDelimiter = r'$';
        current.writeFrom(ch, at(i));
        continue;
      }

      if (ch == '`') {
        int runLength = 1;
        while (i + runLength < value.length && value[i + runLength] == '`') {
          runLength += 1;
        }

        if (codeFenceLength == 0) {
          codeFenceLength = runLength;
        } else if (runLength >= codeFenceLength) {
          codeFenceLength = 0;
        }

        current.writeFrom(value.substring(i, i + runLength), at(i));
        i += runLength - 1;
        continue;
      }

      if (ch == '|' && codeFenceLength == 0) {
        cells.add(current.build().trim());
        current.clear();
        continue;
      }

      current.writeFrom(ch, at(i));
    }
    cells.add(current.build().trim());

    if (value.startsWith('|') && cells.isNotEmpty && cells.first.isEmpty) {
      cells.removeAt(0);
    }
    if (value.endsWith('|') && cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }

    return cells
        .map((_SourceSlice cell) => cell.withoutPipeEscapes())
        .toList(growable: false);
  }

  String? _latexEndDelimiterForBackslash(String value, int index) {
    if (value.startsWith(r'\(', index)) {
      return r'\)';
    }
    if (value.startsWith(r'\[', index)) {
      return r'\]';
    }
    return null;
  }
}
