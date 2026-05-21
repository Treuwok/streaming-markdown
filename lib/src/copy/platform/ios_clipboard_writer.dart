import 'clipboard_writer_interface.dart';

class IosClipboardWriter extends PlainTextClipboardWriter {
  const IosClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    throw UnsupportedError('iOS rich clipboard bridge is not registered yet');
  }
}
