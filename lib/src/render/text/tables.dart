part of '../view.dart';

extension _StreamingMarkdownTableTextParsing on StreamingMarkdownRenderView {
  _ParsedTable? _parseMarkdownTable(
    String raw, {
    bool allowLooseWithoutDelimiter = false,
    int minLooseRowsWithoutDelimiter = 1,
  }) {
    final List<String> lines = _firstTableLineRun(raw);
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

      final List<List<String>> rows = lines
          .map(_splitTableRow)
          .where((List<String> row) => row.isNotEmpty)
          .toList(growable: false);
      if (rows.length < minLooseRowsWithoutDelimiter || rows.isEmpty) {
        return null;
      }

      int width = 0;
      for (final List<String> row in rows) {
        if (row.length > width) {
          width = row.length;
        }
      }
      if (width <= 0) {
        return null;
      }

      final List<String> headers = _fitTableRowToWidth(rows.first, width);
      final List<List<String>> bodyRows = rows
          .skip(1)
          .map((List<String> row) => _fitTableRowToWidth(row, width))
          .toList(growable: false);

      return _ParsedTable(headers: headers, rows: bodyRows);
    }

    final List<String> rawHeaders = delimiterIndex > 0
        ? _splitTableRow(lines[delimiterIndex - 1])
        : <String>[];
    final List<String> delimiterCells = _splitTableRow(lines[delimiterIndex]);
    int width = rawHeaders.length > delimiterCells.length
        ? rawHeaders.length
        : delimiterCells.length;

    final List<List<String>> rawRows = <List<String>>[];
    for (int i = delimiterIndex + 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || !line.contains('|')) {
        continue;
      }

      final List<String> row = _splitTableRow(line);
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
    final List<String> headers = _fitTableRowToWidth(rawHeaders, width);
    final List<List<String>> rows = rawRows
        .map((List<String> row) => _fitTableRowToWidth(row, width))
        .toList(growable: false);

    return _ParsedTable(headers: headers, rows: rows);
  }

  List<String> _firstTableLineRun(String raw) {
    final List<String> out = <String>[];
    bool started = false;
    for (final String original in raw.split('\n')) {
      final String line = original.trimRight();
      if (line.trim().isEmpty) {
        if (started) {
          break;
        }
        continue;
      }
      if (!line.contains('|')) {
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

  List<String> _fitTableRowToWidth(List<String> row, int width) {
    final List<String> out = row.toList(growable: true);
    while (out.length < width) {
      out.add('');
    }
    if (out.length > width) {
      out.removeRange(width, out.length);
    }
    return out;
  }

  bool _isTableDelimiterRow(String line) {
    final List<String> cells = _splitTableRow(line);
    if (cells.isEmpty) {
      return false;
    }

    for (final String cell in cells) {
      final String normalized = cell.replaceAll(' ', '');
      if (!RegExp(r'^:?-+:?$').hasMatch(normalized)) {
        return false;
      }
    }
    return true;
  }

  List<String> _splitTableRow(String line) => _splitTableRowSlices(
        _SourceSlice.whole(line, 0),
      ).map((_SourceSlice cell) => cell.text).toList(growable: false);

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
