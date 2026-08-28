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

Widget _host(
  String source, {
  required bool withhold,
  bool suppressHtml = false,
  bool complete = false,
}) =>
    MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: [_paragraph(source)],
          withholdIncompleteDestinations: withhold,
          suppressRawHtml: suppressHtml,
          sourceComplete: complete,
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

    testWidgets('does NOT hold back an autolink still in flight',
        (tester) async {
      // An autolink's destination is its visible text — nothing is hidden
      // behind a label, so there is nothing to protect. The spike held this
      // back; the cross-platform parity contract records it as url-visible
      // because the other renderer shows it, and hiding it here would be the
      // over-hiding failure wearing the safety flag's clothes.
      await tester.pumpWidget(
          _host('see <https://visible.example', withhold: true));
      await tester.pump();
      expect(_painted(tester), contains('visible.example'));
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

  group('when the withheld construct is the first thing in the block', () {
    // The scan returns an EMPTY token list here, and three separate consumers
    // read an empty list as "nothing to render, draw the source instead" —
    // which draws the destination the scan had just refused to draw. Every
    // fixture in this file used to begin with `see `, so none of them reached
    // it.
    testWidgets('an in-flight link paints nothing at all', (tester) async {
      await tester.pumpWidget(
          _host('[help](https://secret.example', withhold: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('an in-flight tag paints nothing at all', (tester) async {
      await tester.pumpWidget(_host('<a href="https://secret.example',
          withhold: true, suppressHtml: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });
  });

  testWidgets('a footnote-shaped label followed by `(` is a link candidate',
      (tester) async {
    // `[^note](https://…` — the footnote arm consumed `[^note]` before the
    // link scan ever ran, and the rest fell through to plain text with the
    // destination in it.
    await tester.pumpWidget(
        _host('see [^note](https://secret.example', withhold: true));
    await tester.pump();
    expect(_painted(tester), isNot(contains('secret.example')));
  });

  group('a label whose whole content is suppressed', () {
    testWidgets('is not rebuilt as raw text', (tester) async {
      // The nested scan suppressed the entire label, so it produced no tokens
      // — and "no tokens" was read as "no markup here", which rebuilt the
      // label from source and painted the href that had just been suppressed.
      await tester.pumpWidget(_host(
          '[<a href="https://secret.example">](https://ok.example)',
          withhold: true,
          suppressHtml: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });
  });

  group('a nested scan holding back stops the outer one too', () {
    testWidgets('nothing after the boundary is painted', (tester) async {
      // The guard used to sit halfway down the loop, so the branches above it
      // ran anyway: emphasis recursion withheld at offset 1, the outer loop
      // jumped past it, matched the SECOND link and painted that — text before
      // the boundary dropped, text after it shown, reply out of order.
      await tester.pumpWidget(_host(
          '*[x](http://sec1*[y](http://sec2)',
          withhold: true));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, isNot(contains('y')));
      expect(painted, isNot(contains('sec')));
    });
  });

  group('the end of the source releases prose, never a destination', () {
    testWidgets('an unterminated angle is the prose it turned out to be',
        (tester) async {
      // Both of these used to hinge on whether the text contained an `=`,
      // which is a guess about an open set — and it was wrong both ways in
      // one round. Once the source is final nothing is still arriving, so
      // what is on the page is what the author wrote.
      for (final String source in <String>[
        'when n <m the value is fine',
        'Use T<U where x=1 and it is fine',
      ]) {
        await tester.pumpWidget(_host(source,
            withhold: true, suppressHtml: true, complete: true));
        await tester.pump();
        expect(_painted(tester), contains('fine'), reason: source);
      }
    });

    testWidgets('an unterminated comment stays hidden even when final',
        (tester) async {
      // The one construct where the author said "do not show this". A stream
      // that stopped a chunk before `-->` did not withdraw that.
      await tester.pumpWidget(_host(
          'note <!-- confidential https://secret.example',
          withhold: true,
          suppressHtml: true,
          complete: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('an image with empty alt still holds back its destination',
        (tester) async {
      await tester.pumpWidget(_host('see ![](https://secret.example',
          withhold: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('a backtick inside brackets does not truncate a finished reply',
        (tester) async {
      await tester.pumpWidget(_host('the bracket [x`y] is fine',
          withhold: true, complete: true));
      await tester.pump();
      expect(_painted(tester), contains('is fine'));
    });
  });

  group('suppressRawHtml', () {
    testWidgets('holds back a tag whose attribute is still arriving',
        (tester) async {
      // The same leak in a third costume: the scanner recognised exactly one
      // `<…>` shape (an http autolink) and let a raw tag fall through to the
      // plain-text path, `href` and all.
      await tester.pumpWidget(
          _host('see <a href="https://secret.example', withhold: true,
              suppressHtml: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('does not draw a completed tag', (tester) async {
      await tester.pumpWidget(_host(
          'see <a href="https://ok.example">label</a> done',
          withhold: true,
          suppressHtml: true));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, isNot(contains('ok.example')));
      expect(painted, contains('label'),
          reason: 'the tag goes, the text it wrapped stays');
      expect(painted, contains('done'),
          reason: 'a closed tag must not swallow what follows it');
    });

    testWidgets('a greater-than inside an attribute does not close the tag',
        (tester) async {
      await tester.pumpWidget(_host(
          'see <a title="a > b" href="https://secret.example',
          withhold: true,
          suppressHtml: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')),
          reason: 'quote-aware scanning; the naive `indexOf(">")` leaks here');
    });

    testWidgets('a greater-than inside a comment body does not close it',
        (tester) async {
      await tester.pumpWidget(_host('see <!-- a > b https://secret.example',
          withhold: true, suppressHtml: true));
      await tester.pump();
      expect(_painted(tester), isNot(contains('secret.example')));
    });

    testWidgets('leaves angle text that cannot start a tag alone',
        (tester) async {
      // `<mailto:` and `x < 5` are not tags. Hiding them would be the
      // over-hiding failure, which is the one nobody notices in a smoke test.
      await tester.pumpWidget(_host('use x < 5 and <mailto:a@b> today',
          withhold: true, suppressHtml: true));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, contains('x < 5'));
      expect(painted, contains('mailto:a@b'));
    });

    testWidgets('is off by default — a tag still renders as literal source',
        (tester) async {
      await tester.pumpWidget(_host('see <a href="https://secret.example">x</a>',
          withhold: true));
      await tester.pump();
      expect(_painted(tester), contains('secret.example'),
          reason: 'upstream draws unsupported HTML verbatim; that is the '
              'behaviour existing callers get unless they opt out');
    });
  });
}
