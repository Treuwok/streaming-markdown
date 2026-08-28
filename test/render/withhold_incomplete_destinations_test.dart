/// A destination that has not fully arrived must not reach the screen.
///
/// The scanner already knew: `[label](https://…` with no closing paren is a
/// link whose destination is still in flight, and it is a different fact from
/// "this is not a link". Both used to leave the scanner as `null`, so the
/// caller fell through to the plain-text path and wrote the source out
/// verbatim — URL included, for as long as the rest of it was in flight.
///
/// Streaming makes that routine rather than rare: every transport chunk can
/// land inside a URL.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownRenderNode _paragraph(String source) => MarkdownRenderNode(
      type: 'paragraph',
      depth: 0,
      startByte: 0,
      endByte: source.length,
      startRow: 0,
      endRow: 0,
      raw: source,
      content: source,
    );

Widget _host(String source, {required bool withhold}) => MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: [_paragraph(source)],
          withholdIncompleteDestinations: withhold,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
        ),
      ),
    );

String _painted(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final Element element in find.byType(RichText).evaluate()) {
    buffer.write((element.widget as RichText).text.toPlainText());
  }
  return buffer.toString();
}

void main() {
  group('withholdIncompleteDestinations', () {
    testWidgets('holds back an inline destination still in flight',
        (tester) async {
      await tester.pumpWidget(_host('see [help](https://secret.example',
          withhold: true));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, contains('see'),
          reason: 'text before the unresolved link is unaffected');
      expect(painted, isNot(contains('secret.example')),
          reason: 'the destination has not arrived; it must not be painted');
    });

    testWidgets('holds back an autolink still in flight', (tester) async {
      await tester.pumpWidget(
          _host('see <https://secret.example', withhold: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('paints a destination once it has arrived', (tester) async {
      await tester.pumpWidget(
          _host('see [help](https://ok.example)', withhold: true));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, contains('help'),
          reason: 'a resolved link renders normally — the label is the point');
      expect(painted, isNot(contains('ok.example')),
          reason: 'a resolved link shows its label, never its destination');
    });

    testWidgets('leaves prose that merely looks like a link alone',
        (tester) async {
      // `[]` with an empty label is not a link in any state, so withholding it
      // would hide text the author meant to show. The guard for over-hiding.
      await tester.pumpWidget(_host('see [] brackets', withhold: true));
      await tester.pump();
      expect(_painted(tester), contains('brackets'));
    });

    testWidgets('is off by default — upstream behaviour is unchanged',
        (tester) async {
      await tester.pumpWidget(_host('see [help](https://secret.example',
          withhold: false));
      await tester.pump();
      expect(_painted(tester), contains('secret.example'),
          reason:
              'this is the behaviour every existing caller depends on; the '
              'flag must be opt-in');
    });
  });
}
