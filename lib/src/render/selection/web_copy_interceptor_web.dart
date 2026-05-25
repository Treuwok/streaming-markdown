// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

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

  static final Map<FocusNode, StreamSubscription<html.Event>> _subscriptions =
      <FocusNode, StreamSubscription<html.Event>>{};

  static void attach({
    required FocusNode focusNode,
    required BrowserCopyDataProvider onCopy,
  }) {
    if (_subscriptions.containsKey(focusNode)) {
      return;
    }
    _subscriptions[focusNode] = html.document.onCopy.listen((html.Event event) {
      if (!focusNode.hasFocus) {
        return;
      }
      final BrowserCopyData? data = onCopy();
      if (data == null) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      final html.ClipboardEvent? clipboardEvent =
          event is html.ClipboardEvent ? event : null;
      clipboardEvent?.clipboardData?.setData('text/plain', data.plainText);
      final String? htmlText = data.htmlText;
      if (htmlText != null && htmlText.isNotEmpty) {
        clipboardEvent?.clipboardData?.setData('text/html', htmlText);
      }
    });
  }

  static void detach({
    required FocusNode focusNode,
  }) {
    _subscriptions.remove(focusNode)?.cancel();
  }
}
