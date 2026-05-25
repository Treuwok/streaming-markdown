import 'package:flutter/foundation.dart';
import 'platform/clipboard_writer_interface.dart';
import 'platform/clipboard_writer_stub.dart'
    if (dart.library.html) 'platform/web_clipboard_writer.dart'
    if (dart.library.io) 'platform/io_clipboard_writer.dart';
import 'selection_strategy.dart';

@immutable
class MarkdownClipboardPayload {
  const MarkdownClipboardPayload({
    required this.plainText,
    required this.rawMarkdown,
    this.htmlText,
  });

  final String plainText;
  final String rawMarkdown;
  final String? htmlText;
}

class MarkdownClipboardHandler {
  MarkdownClipboardHandler({MarkdownClipboardWriter? writer})
      : _writer = writer ?? (debugWriterFactory?.call() ?? createClipboardWriter());

  final MarkdownClipboardWriter _writer;

  static MarkdownClipboardWriter Function()? debugWriterFactory;

  Future<void> copySelection({
    required SelectionStrategy strategy,
    required MarkdownClipboardPayload payload,
  }) async {
    final String plainText = payload.plainText;
    final String rawMarkdown = payload.rawMarkdown;
    if (plainText.isEmpty && rawMarkdown.isEmpty) {
      return;
    }

    switch (strategy) {
      case SelectionStrategy.plain:
        await _writer.writePlainText(plainText);
        return;
      case SelectionStrategy.raw:
        await _writer.writePlainText(rawMarkdown.isEmpty ? plainText : rawMarkdown);
        return;
      case SelectionStrategy.rich:
        final String? htmlText = payload.htmlText;
        if (htmlText == null || htmlText.isEmpty) {
          await _writer.writePlainText(plainText);
          return;
        }
        try {
          await _writer.writeRichText(plainText: plainText, htmlText: htmlText);
        } catch (_) {
          await _writer.writePlainText(plainText);
        }
        return;
    }
  }
}
