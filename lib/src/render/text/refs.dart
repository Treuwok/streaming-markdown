part of '../view.dart';

extension _StreamingMarkdownReferenceParsing on StreamingMarkdownRenderView {
  Map<String, String> _extractLinkReferences(List<MarkdownRenderNode> nodes) {
    final Map<String, String> references = <String, String>{};
    for (final MarkdownRenderNode node in nodes) {
      if (node.type != 'link_reference_definition') {
        continue;
      }
      _addLinkReferencesFromRaw(node.raw, references);
    }
    return references;
  }

  Map<String, int> _extractFootnoteNumbers(List<MarkdownRenderNode> nodes) {
    final Map<String, int> numbers = <String, int>{};
    for (final MarkdownRenderNode node in nodes) {
      for (final _FootnoteDefinition definition
          in _parseFootnoteDefinitions(node.raw)) {
        final String key = _normalizeFootnoteKey(definition.id);
        if (key.isEmpty || numbers.containsKey(key)) {
          continue;
        }
        numbers[key] = numbers.length + 1;
      }
    }
    return numbers;
  }
}

/// Reads `[name]: url` definitions out of one block's raw text.
///
/// Shared so the renderer and the withheld-region analysis resolve reference
/// links against the same definitions; a reference whose definition has not
/// arrived is an unresolved destination, and both have to agree on that.
void _addLinkReferencesFromRaw(String raw, Map<String, String> into) {
  final String normalized = raw.replaceAll('\r', '').trimRight();
  for (final RegExpMatch match in RegExp(
    r'^\s*\[([^\]]+)\]:\s*(\S+)',
    multiLine: true,
  ).allMatches(normalized)) {
    final String name = _normalizeReferenceKey(match.group(1)!);
    final String url = _stripEnclosingAngles(match.group(2)!);
    if (name.isNotEmpty && url.isNotEmpty) {
      into[name] = url;
    }
  }
}
