part of '../view.dart';

extension _StreamingMarkdownSelectionProjectionBuilder
    on StreamingMarkdownRenderView {
  _MarkdownSelectionProjection _buildSelectionProjection(
    List<MarkdownRenderNode> blocks, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final List<_MarkdownSelectionSegment> segments =
        <_MarkdownSelectionSegment>[];
    for (final MarkdownRenderNode block in blocks) {
      final String raw = _selectionRaw(block.raw);
      switch (block.type) {
        case 'atx_heading':
        case 'setext_heading':
          // Through the safety-aware helper, like paragraphs. Building the
          // segment from raw source handed back a destination the renderer had
          // refused to draw the moment anyone copied across the heading — the
          // flag was enforced in paint and not in the projection built from
          // the same scan.
          segments.add(
            _inlineSelectionSegment(
              _headingText(block),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'paragraph':
          segments.add(
            _inlineSelectionSegment(
              _selectionParagraphText(block),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
        case 'list':
          segments.add(
            _listSelectionSegment(
              block,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
        case 'block_quote':
          segments.add(_quoteSelectionSegment(
            block,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          ));
          break;
        case 'fenced_code_block':
        case 'indented_code_block':
          segments.add(_codeBlockSelectionSegment(block));
          break;
        case 'footnote_definition':
        case 'link_reference_definition':
          // Through the scan, like paragraphs and headings: a footnote body is
          // streamed too, so it can end mid-destination.
          final List<_FootnoteDefinition> definitions =
              _parseFootnoteDefinitions(raw);
          segments.add(
            _inlineSelectionSegment(
              definitions.isEmpty
                  ? raw
                  : definitions
                      .map(
                        (_FootnoteDefinition definition) =>
                            '${definition.id}: ${definition.body}',
                      )
                      .join('\n'),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'html_block':
          if (suppressRawHtml) {
            // Selectable is decided by the same scan that decides painted:
            // this is the ordinary inline path, so whatever survives tag
            // suppression can be selected and copied, and whatever does not
            // contributes nothing. Returning empty here regardless was right
            // only while the block painted nothing at all.
            segments.add(
              _inlineSelectionSegment(
                raw,
                markdownText: raw,
                linkReferences: linkReferences,
                footnoteNumbers: footnoteNumbers,
              ),
            );
            break;
          }
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: _htmlBlockSelectionText(raw),
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'thematic_break':
        case 'pipe_table_delimiter_row':
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: '',
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'pipe_table':
        case 'table':
          segments.add(_tableSelectionSegment(
            raw,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          ));
          break;
        default:
          // Any block type not named above still carries inline text, so it
          // goes through the scan as well. Leaving this on raw source is what
          // made the named cases keep turning up one at a time.
          segments.add(
            _inlineSelectionSegment(
              _contentOrRaw(block),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
      }
    }
    return _MarkdownSelectionProjection(segments);
  }

  String _selectionParagraphText(MarkdownRenderNode node) {
    final String raw = _selectionRaw(node.raw);
    if (raw.trim().isNotEmpty) {
      return raw.replaceAll('\n', ' ');
    }
    return node.content;
  }

  String _selectionRaw(String raw) {
    return raw.replaceAll('\r', '').replaceFirst(RegExp(r'\n+$'), '');
  }

  _MarkdownSelectionSegment _tableSelectionSegment(
    String raw, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedTable? table = _parseMarkdownTable(
      raw,
      allowLooseWithoutDelimiter: true,
      minLooseRowsWithoutDelimiter: 2,
    );
    if (table == null) {
      return _MarkdownSelectionSegment.plain(
        plainText: raw,
        markdownText: raw,
        preserveBlockMarkdownOnPartial: true,
      );
    }

    final List<_TableSelectionCell> cells = <_TableSelectionCell>[];
    int cursor = 0;
    void appendCell({
      required int rowIndex,
      required int columnIndex,
      required String markdown,
    }) {
      final _MarkdownSelectionSegment segment = _inlineSelectionSegment(
        markdown,
        markdownText: markdown,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
      final int start = cursor;
      cursor += segment.plainText.length;
      cells.add(
        _TableSelectionCell(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
          segment: segment,
          start: start,
          end: cursor,
        ),
      );
    }

    void appendRow({
      required int rowIndex,
      required List<String> row,
    }) {
      for (int columnIndex = 0;
          columnIndex < table.headers.length;
          columnIndex++) {
        if (columnIndex >= row.length) {
          continue;
        }
        appendCell(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
          markdown: row[columnIndex],
        );
      }
    }

    appendRow(rowIndex: 0, row: table.headers);
    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      appendRow(rowIndex: rowIndex + 1, row: table.rows[rowIndex]);
    }

    final String plainText =
        cells.map((_TableSelectionCell cell) => cell.segment.plainText).join();
    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(plainText: plainText, markdownText: raw),
      ],
      fallbackMarkdownText: raw,
      rangeMarkdownBuilder: (int selectionStart, int selectionEnd) {
        return _markdownTableForPlainRange(
          table: table,
          cells: cells,
          selectionStart: selectionStart,
          selectionEnd: selectionEnd,
        );
      },
    );
  }
}
