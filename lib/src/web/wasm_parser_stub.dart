import '../model/render_node.dart';

class StreamingMarkdownWasmParser {
  static bool get isReady => false;

  static Object? get loadError => null;

  static Future<bool> ensureInitialized() async => false;

  static String? parseBlocksJson(String markdown) => null;

  static String? parseInlinesJson(String markdown) => null;

  static List<MarkdownRenderNode>? parseRenderNodes(String markdown) => null;
}
