import 'clipboard_writer_interface.dart';

class AndroidClipboardWriter extends PlainTextClipboardWriter {
  const AndroidClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    throw UnsupportedError(
      'Android rich clipboard bridge is not registered yet',
    );
  }
}
