/// A closer that the author escaped is not where the construct ends.
///
/// #2356 taught the scanner that `\*` does not OPEN emphasis. The other half —
/// that it does not CLOSE it either — was left out, because opening is decided
/// by the main loop while closing is decided by look-ahead inside each
/// scanner, and those are different code. The result altered the reader's own
/// words: `a *foo \* bar* b` painted `a foo \ bar* b`, with a backslash that
/// was never written and an asterisk in the wrong place (#2438).
///
/// ## Where this list comes from
///
/// Not from the cases somebody noticed. Every construct below is one whose
/// END is located by a look-ahead search, enumerated from the call sites of
/// `_matchDelimited` / `_scanInlineLinkAt` / `_matchInlineImageAt`, plus the
/// spec's own answer for each about whether backslash escapes apply:
///
///   > Backslash escapes do not work in code blocks, code spans, autolinks,
///   > or raw HTML.
///
/// So the code span belongs in the second group, not the first, and putting it
/// in the first would be a spec violation wearing the shape of a fix.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownRenderNode _node(String raw) => MarkdownRenderNode(
      type: 'paragraph',
      depth: 0,
      startCodeUnit: 0,
      endCodeUnit: raw.length,
      startRow: 0,
      endRow: 0,
      raw: raw,
      content: raw,
    );

String _visible(String source, {String? andThen}) =>
    analyzeWithheldMarkdownRegionsOfSource(
      andThen == null ? source : '$source\n\n$andThen\n',
      suppressRawHtml: true,
      sourceComplete: true,
      hideLinkReferenceDefinitions: true,
    ).visibleText;

void main() {
  group('an escaped closer does not end the construct', () {
    const Map<String, (String, String)> cases = <String, (String, String)>{
      'italic with *': (r'a *foo \* bar* b', 'a foo * bar b'),
      'italic with _': (r'a _foo \_ bar_ b', 'a foo _ bar b'),
      // ⚠️ These four were already correct before the fix and stay green with
      // it removed — a multi-character run cannot collide with the single
      // `\*` inside. They are here because they are members of the class, not
      // because they guard it: removing the fix turns the OTHER seven red and
      // leaves these four alone. Do not read them as protection.
      'bold with **': (r'a **foo \* bar** b', 'a foo * bar b'),
      'bold with __': (r'a __foo \_ bar__ b', 'a foo _ bar b'),
      'bold-italic with ***': (r'a ***foo \* bar*** b', 'a foo * bar b'),
      'bold-italic with ___': (r'a ___foo \_ bar___ b', 'a foo _ bar b'),
      'strikethrough': (r'a ~~foo \~~ bar~~ b', 'a foo ~~ bar b'),
      'link label': (r'[foo \] bar](https://x/y)', 'foo ] bar'),
      'link destination': (r'[t](https://x/a\)b)', 't'),
      'image alt': (r'before ![alt \] x](https://i/x.png) after',
          'before  after'),
    };

    cases.forEach((String name, (String, String) io) {
      test(name, () => expect(_visible(io.$1), io.$2));
    });

    test('a multi-character closer that OVERLAPS the escaped one still closes',
        () {
      // `~~x \~~~ y`: the `~~` the search lands on starts at the escaped
      // tilde, but the one starting a character later is a real closer.
      // Stepping over the whole delimiter width missed it, so the construct
      // never closed and its markers were painted. Single-character
      // delimiters cannot show this, which is why it only ever appeared on
      // `~~` and on the LaTeX `$$`.
      expect(_visible(r'a ~~x \~~~ y b'), 'a x ~ y b');
    });

    test('reference link label', () {
      expect(
        _visible(r'[foo \] bar][ref]', andThen: '[ref]: https://x/y'),
        'foo ] bar',
      );
    });
  });

  group('the constructs the spec exempts keep ending at the escape', () {
    // Not an oversight — these are the second half of the same contract. A
    // change that "fixes" them has broken the parser, not improved it.
    test('code span', () {
      expect(_visible('a `code \\` more` b'), 'a code \\ more` b');
    });

    test('the spec\'s own code-span example', () {
      // ``` `` \[\` `` ``` renders as <code>\[\`</code>: both escapes literal.
      expect(_visible(r'`` \[\` ``').contains(r'\['), isTrue);
    });
  });

  group('the fix does not swallow closers that really do close', () {
    // The adjacent legal cases. A rule that skips escaped closers can skip one
    // that was never escaped — and over-hiding is the failure that wears the
    // safety flag's clothes, because nothing on screen looks wrong.
    const Map<String, (String, String)> cases = <String, (String, String)>{
      'nothing escaped at all': ('a *foo bar* b', 'a foo bar b'),
      'an escaped BACKSLASH still lets the next * close':
          (r'a *foo \\* bar b', r'a foo \ bar b'),
      'escaped OPENER stays literal (#2356)':
          (r'a \*not emphasis\* b', 'a *not emphasis* b'),
      'a plain link is unaffected': ('[foo bar](https://x/y)', 'foo bar'),
      'a backslash before a letter is literal': (r'a \z b', r'a \z b'),
    };

    cases.forEach((String name, (String, String) io) {
      test(name, () => expect(_visible(io.$1), io.$2));
    });
  });

  group('the escape is removed from the values, not just stepped over', () {
    // Finding the right closer decides where a construct ENDS; it does not
    // decide what its text IS. A label's inner text is scanned again and the
    // escape disappears there, but a destination and an image's alt are cut
    // straight out of the source. Visible-text assertions cannot see either of
    // these, which is why they are widget tests: before this, locating the
    // real `)` produced a tappable link to a URL that does not exist — worse
    // than the unparsed text it replaced.
    testWidgets('a link destination loses the backslash', (
      WidgetTester tester,
    ) async {
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _node(r'go [here](https://x/a\)b) now'),
              ],
              padding: EdgeInsets.zero,
              onLinkTap: (String url) => tapped = url,
            ),
          ),
        ),
      );
      await tester.tap(find.text('here'));
      await tester.pump();
      expect(tapped, 'https://x/a)b');
    });

    testWidgets('an image alt loses the backslash', (
      WidgetTester tester,
    ) async {
      // Asserted on what the reader actually gets. A network image cannot load
      // in a widget test, so the renderer falls back to painting the alt — the
      // same string it hands to selection and to screen readers. The earlier
      // version of this test asked the visible-text projection instead and was
      // GREEN with the fix removed, because a parsed image is hidden from that
      // projection either way.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _node(r'see ![alt \] x](https://i/x.png) here'),
              ],
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      );
      // Two pumps: the network load fails asynchronously, and the alt is only
      // painted once it has.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('image: alt ] x'), findsOneWidget);
    });
  });
}
