part of '../view.dart';

extension _StreamingMarkdownBlockPipeline on StreamingMarkdownRenderView {
  List<MarkdownRenderNode> _collectRenderableBlocks(
    List<MarkdownRenderNode> nodes,
  ) {
    if (nodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> blockNodes = nodes
        .where((MarkdownRenderNode node) => _isRenderableBlockNode(node.type))
        .toList(growable: false);
    if (blockNodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> sorted = blockNodes.toList(growable: false)
      ..sort((MarkdownRenderNode a, MarkdownRenderNode b) {
        final int byStart = a.startCodeUnit.compareTo(b.startCodeUnit);
        if (byStart != 0) {
          return byStart;
        }
        final int byEnd = b.endCodeUnit.compareTo(a.endCodeUnit);
        if (byEnd != 0) {
          return byEnd;
        }
        return a.depth.compareTo(b.depth);
      });
    final List<MarkdownRenderNode> normalized = _mergeOrphanTableFragments(
      sorted,
    );

    final Set<String> seenSpans = <String>{};
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    MarkdownRenderNode? lastContainer;

    for (final MarkdownRenderNode node in normalized) {
      final String spanKey =
          '${node.startCodeUnit}:${node.endCodeUnit}:${node.type}';
      if (!seenSpans.add(spanKey)) {
        continue;
      }

      if (lastContainer != null &&
          node.startCodeUnit >= lastContainer.startCodeUnit &&
          node.endCodeUnit <= lastContainer.endCodeUnit &&
          node.depth > lastContainer.depth) {
        continue;
      }

      out.add(node);
      if (_containerConsumesChildren(node.type)) {
        lastContainer = node;
      } else if (lastContainer != null &&
          node.endCodeUnit > lastContainer.endCodeUnit) {
        lastContainer = null;
      }
    }

    return out;
  }

  List<MarkdownRenderNode> _mergeOrphanTableFragments(
    List<MarkdownRenderNode> sorted,
  ) {
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    int i = 0;
    while (i < sorted.length) {
      final MarkdownRenderNode node = sorted[i];
      if (!_isTableFragmentNode(node.type)) {
        out.add(node);
        i += 1;
        continue;
      }
      if (_isTableFragmentCoveredByContainer(node, sorted)) {
        i += 1;
        continue;
      }

      final List<MarkdownRenderNode> fragments = <MarkdownRenderNode>[node];
      int j = i + 1;
      while (j < sorted.length) {
        final MarkdownRenderNode candidate = sorted[j];
        if (!_isTableFragmentNode(candidate.type) ||
            _isTableFragmentCoveredByContainer(candidate, sorted)) {
          break;
        }
        final MarkdownRenderNode previous = fragments.last;
        if (candidate.startRow > previous.endRow + 1) {
          break;
        }
        fragments.add(candidate);
        j += 1;
      }

      final _SynthesizedTableNode synthesized =
          _synthesizeTableNodeFromFragments(fragments);
      final _ParsedTable? parsed = _parseMarkdownTable(
        _blockSlice(synthesized),
        allowLooseWithoutDelimiter: true,
        minLooseRowsWithoutDelimiter: 2,
      );
      if (parsed == null) {
        out.add(node);
        i += 1;
        continue;
      }

      out.add(synthesized);
      i = j;
    }
    return out;
  }

  _SynthesizedTableNode _synthesizeTableNodeFromFragments(
    List<MarkdownRenderNode> fragments,
  ) {
    int startByte = fragments.first.startCodeUnit;
    int endByte = fragments.first.endCodeUnit;
    int startRow = fragments.first.startRow;
    int endRow = fragments.first.endRow;
    int depth = fragments.first.depth;
    for (final MarkdownRenderNode fragment in fragments) {
      if (fragment.startCodeUnit < startByte) {
        startByte = fragment.startCodeUnit;
      }
      if (fragment.endCodeUnit > endByte) {
        endByte = fragment.endCodeUnit;
      }
      if (fragment.startRow < startRow) {
        startRow = fragment.startRow;
      }
      if (fragment.endRow > endRow) {
        endRow = fragment.endRow;
      }
      if (fragment.depth < depth) {
        depth = fragment.depth;
      }
    }

    // The rows are still in hand, and each one knows where it starts. Trimming
    // them into a `String` here and re-deriving positions from that string
    // later is what lost them: `_normalizedSlice(raw, 0)` can only assume the
    // text begins at the node's first character, and every space this trim
    // removes moves everything after it.
    //
    // So the trim happens on slices instead. Same deletions, same resulting
    // text — the origins simply come along, relative to [startByte] because
    // that is the base every other block's projection is rebased from.
    final List<_SourceSlice> lines = <_SourceSlice>[];
    for (final MarkdownRenderNode fragment in fragments) {
      final _SourceSlice line =
          _normalizedSlice(fragment.raw, fragment.startCodeUnit - startByte)
              .trim();
      if (line.text.isNotEmpty) {
        lines.add(line);
      }
    }
    final _SourceSlice rawSlice = _joinSliceLines(lines);

    return _SynthesizedTableNode(
      depth: depth,
      startCodeUnit: startByte,
      endCodeUnit: endByte,
      startRow: startRow,
      endRow: endRow,
      rawSlice: rawSlice,
    );
  }

  bool _isTableFragmentCoveredByContainer(
    MarkdownRenderNode node,
    List<MarkdownRenderNode> all,
  ) {
    for (final MarkdownRenderNode candidate in all) {
      if (!_isTableContainerNode(candidate.type)) {
        continue;
      }
      if (candidate.startCodeUnit <= node.startCodeUnit &&
          candidate.endCodeUnit >= node.endCodeUnit &&
          candidate.depth <= node.depth) {
        return true;
      }
    }
    return false;
  }

  bool _isTableContainerNode(String type) {
    return type == 'pipe_table' || type == 'table';
  }

  bool _isTableFragmentNode(String type) {
    return type == 'pipe_table_header' ||
        type == 'pipe_table_row' ||
        type == 'pipe_table_delimiter_row';
  }

  bool _isRenderableBlockNode(String type) {
    switch (type) {
      case 'atx_heading':
      case 'setext_heading':
      case 'paragraph':
      case 'fenced_code_block':
      case 'indented_code_block':
      case 'block_quote':
      case 'list':
      case 'thematic_break':
      case 'html_block':
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
      case 'pipe_table_delimiter_row':
      case 'footnote_definition':
      case 'link_reference_definition':
      case 'front_matter':
        return true;
      default:
        return type.endsWith('_block') || type.endsWith('_heading');
    }
  }

  bool _containerConsumesChildren(String type) {
    return type == 'block_quote' ||
        type == 'list' ||
        type == 'fenced_code_block' ||
        type == 'indented_code_block' ||
        type == 'pipe_table' ||
        type == 'table' ||
        type == 'html_block' ||
        type == 'front_matter';
  }
}

/// A table the renderer assembled out of loose rows the parser emitted
/// separately — the one block on screen that no parser produced.
///
/// Every node a parser emits satisfies `raw == source[startCodeUnit ..
/// endCodeUnit)`. This one cannot: the rows it joins are indented, and the
/// indentation is not part of the table. Its text is therefore SHORTER than
/// its span, and a consumer that rebases that text on `startCodeUnit` puts
/// every cell after the first removed space in the wrong place.
///
/// The fix is not to reconstruct the mapping afterwards — there is nothing
/// left to reconstruct it from. It is to keep it: [rawSlice] is built while
/// the rows that carry their own positions are still in hand, which is the
/// same move [_SourceSlice] exists to make, one level up.
///
/// A distinct type rather than a flag, so that the two places that must treat
/// it differently ([_blockSlice] and `_hasUsableCoordinates`) cannot be
/// written as if it were an ordinary node.
class _SynthesizedTableNode extends MarkdownRenderNode {
  _SynthesizedTableNode({
    required super.depth,
    required super.startCodeUnit,
    required super.endCodeUnit,
    required super.startRow,
    required super.endRow,
    required this.rawSlice,
  }) : super(
          type: 'pipe_table',
          raw: rawSlice.text,
          content: rawSlice.text,
        );

  /// [MarkdownRenderNode.raw] with each code unit's offset **within the
  /// block** — the same base `_normalizedSlice(raw, 0)` produces for an
  /// ordinary node, so callers rebase it exactly the same way.
  final _SourceSlice rawSlice;
}

/// The block's normalized text, and where each character of it came from.
///
/// One function so that the ordinary case and the synthesized one cannot drift
/// apart: for a parser node the mapping is derivable from `raw` because `raw`
/// IS the slice; for a synthesized table it is carried, because it is not.
_SourceSlice _blockSlice(MarkdownRenderNode node) =>
    node is _SynthesizedTableNode
        ? node.rawSlice
        : _normalizedSlice(node.raw, 0);
