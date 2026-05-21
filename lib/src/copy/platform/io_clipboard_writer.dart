import 'dart:io';

import 'android_clipboard_writer.dart';
import 'clipboard_writer_interface.dart';
import 'clipboard_writer_stub.dart' as stub;
import 'ios_clipboard_writer.dart';
import 'linux_clipboard_writer.dart';
import 'macos_clipboard_writer.dart';
import 'windows_clipboard_writer.dart';

MarkdownClipboardWriter createClipboardWriter() {
  if (Platform.isAndroid) {
    return const AndroidClipboardWriter();
  }
  if (Platform.isIOS) {
    return const IosClipboardWriter();
  }
  if (Platform.isMacOS) {
    return const MacosClipboardWriter();
  }
  if (Platform.isWindows) {
    return const WindowsClipboardWriter();
  }
  if (Platform.isLinux) {
    return const LinuxClipboardWriter();
  }
  return stub.createClipboardWriter();
}
