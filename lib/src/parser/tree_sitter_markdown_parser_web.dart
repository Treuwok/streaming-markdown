import '../model/syntax_tree.dart';
import '../model/rope.dart';
import '../web/wasm_parser_web.dart';

/// Tree-sitter markdown parser facade for Flutter web.
///
/// Call `warmUpStreamingMarkdownParser()` before using this synchronous facade
/// so the package can load the generated WASM asset.
class TreeSitterMarkdownParser {
  /// Creates a tree-sitter Markdown parser facade.
  const TreeSitterMarkdownParser();

  /// Parses [markdown] using the tree-sitter Markdown block grammar.
  MarkdownSyntaxNode parseBlocks(String markdown) {
    return _parse(
      markdown,
      StreamingMarkdownWasmParser.parseBlocksJson,
      'block',
    );
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown block grammar.
  MarkdownSyntaxNode parseBlocksFromRope(RopeString rope) {
    return parseBlocks(rope.toString());
  }

  /// Parses [markdown] using the tree-sitter Markdown inline grammar.
  MarkdownSyntaxNode parseInlines(String markdown) {
    return _parse(
      markdown,
      StreamingMarkdownWasmParser.parseInlinesJson,
      'inline',
    );
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown inline grammar.
  MarkdownSyntaxNode parseInlinesFromRope(RopeString rope) {
    return parseInlines(rope.toString());
  }

  MarkdownSyntaxNode _parse(
    String markdown,
    String? Function(String markdown) parseJson,
    String grammar,
  ) {
    final String? json = parseJson(markdown);
    if (json == null || json.isEmpty) {
      throw StateError(
        'Tree-sitter WASM is not loaded for $grammar parsing. '
        'Run tool/build_wasm.sh, include the generated assets, and await '
        'warmUpStreamingMarkdownParser() before using this API on web.',
      );
    }
    return MarkdownSyntaxNode.fromJsonString(json);
  }
}
