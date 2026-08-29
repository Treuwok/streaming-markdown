/// Never hand over half of a character.
library;

import 'dart:convert';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a pair split across two chunks is rejoined before it is sent', () {
    const String emoji = '\u{1F600}';
    final String high = emoji.substring(0, 1);
    final String low = emoji.substring(1);

    var step = splitOffPendingSurrogate('', 'a$high');
    expect(step.send, 'a', reason: 'the lone high surrogate waits');
    expect(step.carry, high);

    step = splitOffPendingSurrogate(step.carry, '${low}b');
    expect(step.send, '${emoji}b', reason: 'rejoined, then sent whole');
    expect(step.carry, isEmpty);
  });

  test('what was sent encodes to the same bytes as the joined document', () {
    // The property the caller needs: the accumulated Dart string and the bytes
    // the consumer received must agree, or every offset after the split point
    // translates against the wrong table.
    const String emoji = '\u{1F600}';
    final List<String> chunks = <String>['開始 ${emoji.substring(0, 1)}',
        '${emoji.substring(1)} 結束'];

    final StringBuffer accumulated = StringBuffer();
    final List<int> bytesSent = <int>[];
    String carry = '';
    for (final String chunk in chunks) {
      final ({String send, String carry}) step =
          splitOffPendingSurrogate(carry, chunk);
      carry = step.carry;
      accumulated.write(step.send);
      bytesSent.addAll(utf8.encode(step.send));
    }

    expect(utf8.encode(accumulated.toString()), bytesSent);
    expect(accumulated.toString(), '開始 $emoji 結束');
    expect(carry, isEmpty);
  });

  test('without it, the two disagree — which is the bug', () {
    // Encoding each half on its own yields two replacement characters, six
    // bytes, where the joined string is four. This is what the helper avoids.
    const String emoji = '\u{1F600}';
    final int halves = utf8.encode(emoji.substring(0, 1)).length +
        utf8.encode(emoji.substring(1)).length;
    expect(halves, isNot(utf8.encode(emoji).length));
  });

  test('ordinary chunks pass straight through', () {
    final step = splitOffPendingSurrogate('', '一般文字 abc');
    expect(step.send, '一般文字 abc');
    expect(step.carry, isEmpty);
  });
}
