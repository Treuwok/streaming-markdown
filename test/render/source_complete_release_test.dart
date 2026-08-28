library;
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
MarkdownRenderNode _p(String s) => MarkdownRenderNode(type: 'paragraph', depth: 0,
    startByte: 0, endByte: s.length, startRow: 0, endRow: 0, raw: s, content: s);
Widget _h(String s, {required bool complete}) => MaterialApp(home: Scaffold(
    body: AnimatedStreamingMarkdown(blocks: [_p(s)],
      withholdIncompleteDestinations: true, suppressRawHtml: true, sourceComplete: complete,
      tokenStaggerDelay: Duration.zero, tokenAnimationDuration: Duration.zero)));
String _paint(WidgetTester t) { final b = StringBuffer();
  for (final e in find.byType(RichText).evaluate()) { b.write((e.widget as RichText).text.toPlainText()); }
  return b.toString(); }
void main() {
  testWidgets('the held-back tail appears when the source completes', (t) async {
    // The block cache did not include the flags that change what the scan
    // produces, so flipping `sourceComplete` reused the cached blocks and the
    // end of the reply stayed hidden for good.
    const src = 'see [foo';
    await t.pumpWidget(_h(src, complete: false)); await t.pump();
    expect(_paint(t), isNot(contains('[foo')));
    await t.pumpWidget(_h(src, complete: true)); await t.pump();
    expect(_paint(t), contains('[foo'));
  });
}
