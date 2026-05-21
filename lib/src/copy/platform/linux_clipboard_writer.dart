import 'clipboard_writer_interface.dart';

class LinuxClipboardWriter extends PlainTextClipboardWriter {
  const LinuxClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    throw UnsupportedError(
      'Linux rich clipboard bridge is not registered yet',
    );
  }
}
