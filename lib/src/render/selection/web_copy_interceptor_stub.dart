import 'package:flutter/widgets.dart';

class BrowserCopyData {
  const BrowserCopyData({
    required this.plainText,
    this.htmlText,
  });

  final String plainText;
  final String? htmlText;
}

typedef BrowserCopyDataProvider = BrowserCopyData? Function();

class WebCopyInterceptor {
  const WebCopyInterceptor._();

  static void attach({
    required FocusNode focusNode,
    required BrowserCopyDataProvider onCopy,
  }) {}

  static void detach({
    required FocusNode focusNode,
  }) {}
}
