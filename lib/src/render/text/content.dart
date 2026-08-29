part of '../view.dart';

extension _StreamingMarkdownContentParsing on StreamingMarkdownRenderView {
  _SourceSlice _contentOrRawSlice(MarkdownRenderNode node) =>
      _contentOrRawSliceOf(node.raw, 0, node.content);

  String _contentOrRaw(MarkdownRenderNode node) {
    if (node.content.trim().isNotEmpty) {
      return node.content.trim();
    }
    return _normalizedRaw(node.raw).trim();
  }

  String _htmlBlockSelectionText(String raw) {
    final html_dom.DocumentFragment fragment = html_parser.parseFragment(raw);
    return _firstHtmlSelectionText(fragment.nodes).trim();
  }

  String _firstHtmlSelectionText(List<html_dom.Node> nodes) {
    for (final html_dom.Node node in nodes) {
      final String text = _htmlSelectionTextForNode(node);
      if (text.trim().isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _htmlSelectionTextForNode(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (node is! html_dom.Element) {
      return '';
    }

    final String tag = (node.localName ?? '').toLowerCase();
    if (tag == 'img') {
      return (node.attributes['alt'] ?? node.attributes['src'] ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    if (tag == 'br') {
      return '\n';
    }

    final String text = _firstHtmlSelectionText(node.nodes);
    if (text.trim().isNotEmpty) {
      return text;
    }
    return node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _headingText(MarkdownRenderNode node) =>
      _headingSlice(node.raw, 0, node.type).text;


  int _headingLevelForNode(MarkdownRenderNode node) {
    if (node.type == 'atx_heading') {
      final RegExpMatch? match = RegExp(
        r'^\s{0,3}(#{1,6})\s',
      ).firstMatch(node.raw);
      if (match != null) {
        return match.group(1)!.length;
      }
      return 1;
    }

    if (node.type == 'setext_heading') {
      final List<String> lines = _normalizedRaw(node.raw).split('\n');
      if (lines.length >= 2 && RegExp(r'^\s*=+\s*$').hasMatch(lines.last)) {
        return 1;
      }
      return 2;
    }

    return 1;
  }

  String _paragraphText(MarkdownRenderNode node) =>
      _paragraphSlice(node.raw, 0, node.content).text;


  String _normalizedRaw(String raw) {
    return raw.replaceAll('\r', '').trimRight();
  }




}
