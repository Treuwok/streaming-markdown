// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'clipboard_writer_interface.dart';

MarkdownClipboardWriter createClipboardWriter() {
  return const WebClipboardWriter();
}

class WebClipboardWriter extends PlainTextClipboardWriter {
  const WebClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) async {
    final html.BodyElement? body = html.document.body;
    if (body == null) {
      throw UnsupportedError('Web document body is unavailable');
    }

    final html.DivElement host = html.DivElement()
      ..setAttribute('contenteditable', 'true')
      ..style.position = 'fixed'
      ..style.left = '-10000px'
      ..style.top = '0'
      ..style.opacity = '0'
      ..style.pointerEvents = 'none'
      ..style.whiteSpace = 'pre-wrap'
      ..innerHtml = htmlText;

    body.append(host);
    final html.Selection? selection = html.window.getSelection();
    final List<html.Range> previousRanges = <html.Range>[];
    if (selection != null) {
      final int rangeCount = selection.rangeCount ?? 0;
      for (int i = 0; i < rangeCount; i++) {
        final html.Range range = selection.getRangeAt(i);
        previousRanges.add(range.cloneRange());
      }
      selection.removeAllRanges();
      final html.Range range = html.Range();
      range.selectNodeContents(host);
      selection.addRange(range);
    }

    final bool copied = html.document.execCommand('copy');
    selection?.removeAllRanges();
    for (final html.Range range in previousRanges) {
      selection?.addRange(range);
    }
    host.remove();

    if (!copied) {
      throw UnsupportedError('Browser rejected rich clipboard copy');
    }
  }
}
