/// Base type for parsed block-level Markdown nodes.
abstract class MarkdownBlockNode {
  /// Creates a block node covering `[start, end)` of the source string.
  const MarkdownBlockNode({required this.start, required this.end});

  /// Inclusive start offset of the node in the source string.
  ///
  /// UTF-16 code units, the unit `String` is indexed in — NOT bytes, despite
  /// what the mirrored `MarkdownRenderNode.startByte` is called. They differ
  /// the moment the source stops being ASCII.
  final int start;

  /// Exclusive end offset of the node in the source string, in the same units
  /// as [start].
  final int end;

  /// The renderer's name for this kind of block.
  ///
  /// Every node answers for itself. A caller that switched on the node's
  /// CLASS instead had to keep a list of the classes it knew, and a class
  /// missing from that list got the empty string — which routed silently to
  /// the fallback. `ParagraphNode` was missing from one such list, so no
  /// paragraph was ever recognised as the table or definition list it was.
  /// Making it abstract means a new node type cannot compile without saying
  /// what it is.
  String get type;
}

/// Immutable parse result for a full markdown document.
class MarkdownDocument {
  /// Creates a parsed document with [blocks] and full source [length].
  const MarkdownDocument({required this.blocks, required this.length});

  /// Top-level block nodes in source order.
  final List<MarkdownBlockNode> blocks;

  /// Total source length (in UTF-16 code units) used by the parser input.
  final int length;
}

/// ATX (`#`) or Setext (`===`/`---`) heading node.
class HeadingNode extends MarkdownBlockNode {
  /// Creates a heading node.
  const HeadingNode({
    required super.start,
    required super.end,
    required this.level,
    required this.text,
    this.type = 'atx_heading',
  });

  /// Heading level from `1` to `6`.
  final int level;

  /// Heading content with marker tokens removed.
  final String text;

  /// Renderer-compatible heading type.
  @override
  final String type;
}

/// Paragraph block node.
class ParagraphNode extends MarkdownBlockNode {
  /// Creates a paragraph node.
  const ParagraphNode({
    required super.start,
    required super.end,
    required this.text,
  });

  /// Paragraph text content.
  final String text;

  @override
  String get type => 'paragraph';
}

/// Generic block node for Markdown constructs parsed without a specialized
/// model type.
class GenericBlockNode extends MarkdownBlockNode {
  /// Creates a generic block node.
  const GenericBlockNode({
    required super.start,
    required super.end,
    required this.type,
    required this.content,
  });

  /// Renderer-compatible block type.
  @override
  final String type;

  /// Human-readable content extracted from the block.
  final String content;
}

/// Fenced code block node (triple backticks or tildes).
class CodeFenceNode extends MarkdownBlockNode {
  /// Creates a fenced code block node.
  const CodeFenceNode({
    required super.start,
    required super.end,
    required this.fence,
    required this.language,
    required this.code,
    required this.closed,
  });

  /// Fence marker text used to open the block (for example ```).
  final String fence;

  /// Parsed language identifier after opening fence, if any.
  final String language;

  /// Raw code content inside the fence.
  final String code;

  /// Whether a matching closing fence was present.
  final bool closed;

  @override
  String get type => 'fenced_code_block';
}

/// Ordered (`1.`) or unordered (`-`) list block node.
class ListNode extends MarkdownBlockNode {
  /// Creates a list node.
  const ListNode({
    required super.start,
    required super.end,
    required this.ordered,
    required this.items,
  });

  /// Whether this list is ordered.
  final bool ordered;

  /// Flattened list item nodes for this list block.
  final List<ListItemNode> items;

  @override
  String get type => 'list';
}

/// Single list item node.
class ListItemNode {
  /// Creates a list item node.
  const ListItemNode({
    required this.start,
    required this.end,
    required this.text,
  });

  /// Inclusive start byte offset of this item in source text.
  final int start;

  /// Exclusive end byte offset of this item in source text.
  final int end;

  /// Text content of the list item.
  final String text;
}
