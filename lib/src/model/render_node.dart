/// Normalized markdown block passed from the parser to the renderer.
///
/// A render node keeps both the original source slice ([raw]) and parser
/// metadata such as source offsets and row numbers. Most applications do
/// not create these manually; use [StreamingMarkdownParseWorker] and render the
/// returned `result.blocks` with `AnimatedStreamingMarkdown`.
class MarkdownRenderNode {
  /// Creates an immutable render node.
  const MarkdownRenderNode({
    required this.type,
    required this.depth,
    required this.startCodeUnit,
    required this.endCodeUnit,
    required this.startRow,
    required this.endRow,
    required this.raw,
    required this.content,
  });

  /// Creates a render node from a JSON-like map returned by the native parser.
  factory MarkdownRenderNode.fromDynamicMap(Map<dynamic, dynamic> map) {
    int readInt(String key) {
      final Object? value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    // A map still speaking the old key is a producer that never had its
    // offsets converted, and its numbers are UTF-8 bytes. Reading them as code
    // units would be wrong by a factor of three on this product's content and
    // would say nothing at all — so it stops here instead.
    if (map.containsKey('startByte') || map.containsKey('endByte')) {
      throw ArgumentError(
        'render node map carries startByte/endByte: those were UTF-8 bytes on '
        'the native path and code units on the pure-Dart one. Convert at the '
        'producer and emit startCodeUnit/endCodeUnit.',
      );
    }

    return MarkdownRenderNode(
      type: (map['type'] as String?) ?? 'unknown',
      depth: readInt('depth'),
      startCodeUnit: readInt('startCodeUnit'),
      endCodeUnit: readInt('endCodeUnit'),
      startRow: readInt('startRow'),
      endRow: readInt('endRow'),
      raw: (map['raw'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
    );
  }

  /// Tree-sitter or normalized block type, for example `paragraph`,
  /// `atx_heading`, `fenced_code_block`, or `pipe_table`.
  final String type;

  /// Nesting depth in the source syntax tree.
  final int depth;

  /// Inclusive offset where this block starts, in UTF-16 code units — the
  /// unit a Dart `String` is indexed in, so `source.substring(startCodeUnit,
  /// endCodeUnit)` is this block.
  ///
  /// These were called `startByte` / `endByte`, and on the native path they
  /// really were bytes while on the pure-Dart path they were code units. The
  /// two numbers are equal for ASCII, so the field carried both units for as
  /// long as nobody wrote a non-Latin character — and this product's content
  /// is Chinese. The conversion now happens once, where each parser's output
  /// is turned into a node, and every consumer gets one unit.
  final int startCodeUnit;

  /// Exclusive end of this block, in the same unit as [startCodeUnit].
  final int endCodeUnit;

  /// Zero-based source row where this block starts.
  final int startRow;

  /// Zero-based source row where this block ends.
  final int endRow;

  /// Original markdown source slice for this block.
  final String raw;

  /// Human-readable content extracted from [raw] when available.
  final String content;
}

/// Preferred public name for a block ready to render.
///
/// [MarkdownRenderNode] remains available for compatibility with `0.2.x`, but
/// new APIs and documentation use [MarkdownBlock] because the value represents
/// a normalized block of markdown content.
typedef MarkdownBlock = MarkdownRenderNode;
