import 'clipboard_writer_interface.dart';

class MacosClipboardWriter extends PlainTextClipboardWriter {
  const MacosClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    throw UnsupportedError(
      'macOS rich clipboard bridge is not registered yet',
    );
  }
}
