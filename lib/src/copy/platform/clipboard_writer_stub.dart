import 'clipboard_writer_interface.dart';

MarkdownClipboardWriter createClipboardWriter() {
  return const _StubClipboardWriter();
}

class _StubClipboardWriter extends PlainTextClipboardWriter {
  const _StubClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    throw UnsupportedError('Rich clipboard is not available on this platform');
  }
}
