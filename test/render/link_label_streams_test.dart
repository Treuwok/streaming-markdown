/// A link's label is the author's text; its destination is not.
///
/// While a link streams, the label is painted as it arrives and only the
/// destination is held back. This used to be one decision — the whole
/// candidate was held back from its `[` — so a label appeared in one jump once
/// its URL finished, and a label whose `]` happened to end a chunk was painted
/// with its brackets and then taken away when the `(` arrived.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownRenderNode _p(String s) => MarkdownRenderNode(
    type: 'paragraph',
    depth: 0,
    startCodeUnit: 0,
    endCodeUnit: s.length,
    startRow: 0,
    endRow: 0,
    raw: s,
    content: s);

// How a streaming host calls it: unclosed emphasis is allowed mid-stream.
WithheldMarkdownRegions _streamed(String source) =>
    analyzeWithheldMarkdownRegionsOfSource(source,
        allowUnclosedInlineDelimiters: true);

void main() {
  group('every prefix of a streamed link', () {
    // (source, destination text that must never be visible)
    const List<(String, String)> links = <(String, String)>[
      ('看[資料來源](https://ex.com/a)後面', 'ex.com'),
      ('Read [the guide](<https://ex.com/a b>) now', 'ex.com'),
      ('Read [the guide](https://ex.com/a "Title") now', 'Title'),
    ];

    for (final (String source, String destination) in links) {
      test(
          'only grows apart from brackets, never shows the destination: '
          '$source', () {
        // Brackets may come and go: a chunk that ends right on a `]` cannot
        // know yet whether a `(` follows, and the end of the text a scan is
        // handed is not the end of the stream (a paragraph can end in `[1]`),
        // so it is read as prose until the `(` arrives. Everything else only
        // ever grows — the label in particular is never taken back.
        String words(String s) => s.replaceAll(RegExp(r'[\[\]]'), '');
        final String settled =
            analyzeWithheldMarkdownRegionsOfSource(source, sourceComplete: true)
                .visibleText;
        for (int n = 1; n <= source.length; n++) {
          final String prefix = source.substring(0, n);
          final String visible = _streamed(prefix).visibleText;
          expect(visible, isNot(contains(destination)),
              reason: 'prefix $n: "$prefix"');
          expect(settled.startsWith(words(visible)), isTrue,
              reason: 'prefix $n: "$prefix" painted "$visible", which is '
                  'not the start of "$settled" — something already on screen '
                  'was taken back');
        }
      });
    }

    test('a pending label paints what the same text paints as prose', () {
      // Markup inside the label behaves as it does anywhere else — including
      // a lone `*` that shows until its pair arrives, which is ordinary
      // emphasis streaming and not something a label should do differently.
      const String source = 'Read [**bold** part](https://ex.com/z) end';
      // From the first label character: with nothing after the `[` yet, prose
      // would trim the trailing space before it, a difference of whitespace.
      for (int n = source.indexOf('[') + 2; n < source.indexOf(']'); n++) {
        final String prefix = source.substring(0, n);
        expect(_streamed(prefix).visibleText,
            _streamed(prefix.replaceFirst('[', '')).visibleText,
            reason: 'prefix $n: "$prefix"');
      }
      for (int n = source.indexOf(']'); n <= source.length; n++) {
        expect(_streamed(source.substring(0, n)).visibleText,
            isNot(contains('ex.com')));
      }
    });

    test('paints the label as soon as it arrives', () {
      expect(_streamed('看[資料').visibleText, '看資料');
      expect(_streamed('看[資料來源](https://ex').visibleText, '看資料來源');
    });
  });

  test('a closed label ending a paragraph does not hold back what follows', () {
    // The text a scan is handed ends where its block ends, not where the
    // stream does. A citation like `[1]` ends many paragraphs; reading it as a
    // pending link there held back every block after it until the reply
    // finished.
    for (final String source in <String>[
      '如下[1]\n\n下一段文字',
      '- 第一項[1]\n- 第二項',
      '## Step [1]\n\nbody',
    ]) {
      final WithheldMarkdownRegions regions = _streamed(source);
      expect(regions.safeEndCodeUnits, source.length, reason: source);
      expect(regions.visibleText, contains('[1]'), reason: source);
    }
  });

  group('a destination split across scans never shows any part of itself', () {
    // An emphasis closer or a table pipe inside a URL ends the text one scan
    // is handed while the destination goes on in the next. Only a boundary
    // keeps that remainder off the screen, finished source included.
    const List<(String, String)> cases = <(String, String)>[
      ('_Source: [docs](https://ex.com/some_path)_ end', 'path'),
      ('_see [docs](https://ex.com/user_secret_token', 'secret'),
      ('*see [x](https://secret*.example/path', 'example'),
      ('| a |\n| --- |\n| [x](https://ex.com/a|secret_tail) |', 'secret'),
    ];
    for (final (String source, String forbidden) in cases) {
      test(source, () {
        for (final bool complete in <bool>[false, true]) {
          for (int n = 1; n <= source.length; n++) {
            final String prefix = source.substring(0, n);
            final WithheldMarkdownRegions regions =
                analyzeWithheldMarkdownRegionsOfSource(prefix,
                    sourceComplete: complete,
                    allowUnclosedInlineDelimiters: !complete);
            expect(regions.visibleText, isNot(contains(forbidden)),
                reason: 'complete=$complete prefix $n: "$prefix"');
          }
        }
      });
    }
  });

  group('labels that the finished construct does not paint as text', () {
    test('an image alt stays held back', () {
      const String source = 'See ![alt text](https://ex.com/p';
      expect(_streamed(source).visibleText, isNot(contains('alt text')));
    });

    test('a footnote-shaped label stays held back', () {
      expect(_streamed('See [^note](https://ex.com/p').visibleText,
          isNot(contains('note')));
      expect(_streamed('See [^not').visibleText, isNot(contains('not')));
    });

    test('a label whose `]` sits in a code span stays held back', () {
      const String source = 'See [a `]` b](https://ex.com/p';
      expect(_streamed(source).safeEndCodeUnits, source.indexOf('['));
    });
  });

  test('a pending label nested past the depth limit is held back', () {
    // Each pending label is parsed one level deeper, and so is markup inside
    // one. Past the limit nothing is tokenised, so nothing is screened.
    for (final String source in <String>[
      '${'[' * 9}<a href="https://secret.example',
      '${'[' * 10}x](https://secret.example',
      '${'[' * 8}**<a href="https://secret.example**',
    ]) {
      expect(_streamed(source).visibleText, isNot(contains('secret')),
          reason: source);
    }
  });

  test('a candidate inside a label keeps the earlier boundary', () {
    const String source = 'See [a [b](https://secret.example';
    final WithheldMarkdownRegions regions = _streamed(source);
    expect(regions.visibleText, isNot(contains('secret')));
    for (final int offset in regions.visibleSourceOffsets) {
      expect(offset, lessThan(regions.safeEndCodeUnits));
    }
  });

  testWidgets('a label still waiting for its `]` wraps like prose',
      (WidgetTester t) async {
    // Before the `]` there is no sign yet that it is a link at all — a stray
    // `[` is ordinary text — so it breaks across lines like the prose it may
    // turn out to be, rather than as one unbreakable box.
    Widget host(String s) => MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: 100,
                    child: AnimatedStreamingMarkdown(
                        blocks: <MarkdownRenderNode>[_p(s)],
                        sourceComplete: false,
                        withholdIncompleteDestinations: true,
                        tokenStaggerDelay: Duration.zero,
                        tokenAnimationDuration: Duration.zero)))));
    await t.pumpWidget(host('看看看看看[資料來源還在寫'));
    await t.pump();
    expect(find.text('資料來源還在寫'), findsNothing,
        reason: 'the open label must stay inside the paragraph\'s own text');
  });

  testWidgets('a pending label is laid out the way its link will be',
      (WidgetTester t) async {
    // A link run is one widget (a single tap target), so the line breaker
    // cannot split it. A pending label painted as ordinary text could: it sat
    // across the line end while streaming and jumped to the next line the
    // moment its `)` arrived. Painted in the link's shape from the start, it
    // moves once, while it is still growing — the way a word wraps as it is
    // typed — and never after.
    //
    // 14-pixel square glyphs in a 100-pixel line: the five leading characters
    // take 70, so a four-character label fits only if it may break.
    Widget host(String s) => MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: 100,
                    child: AnimatedStreamingMarkdown(
                        blocks: <MarkdownRenderNode>[_p(s)],
                        sourceComplete: false,
                        withholdIncompleteDestinations: true,
                        tokenStaggerDelay: Duration.zero,
                        tokenAnimationDuration: Duration.zero)))));

    await t.pumpWidget(host('看看看看看[資料來源](https://ex.com/a'));
    await t.pump();
    final Finder label = find.text('資料來源');
    expect(label, findsOneWidget,
        reason: 'the pending label must be one piece, like the link');
    final Offset whileStreaming = t.getTopLeft(label);

    await t.pumpWidget(host('看看看看看[資料來源](https://ex.com/a)'));
    await t.pump();
    expect(find.text('資料來源'), findsOneWidget);
    expect(t.getTopLeft(find.text('資料來源')), whileStreaming);
  });

  testWidgets('becoming a link does not restart the label\'s fade',
      (WidgetTester t) async {
    // The label is tokenised exactly as the finished link will tokenise it, so
    // the widget that faded it in is the one that keeps showing it.
    Widget host(String s) => MaterialApp(
        home: Scaffold(
            body: AnimatedStreamingMarkdown(
                blocks: <MarkdownRenderNode>[_p(s)],
                sourceComplete: false,
                withholdIncompleteDestinations: true,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                tokenStaggerDelay: Duration.zero,
                tokenAnimationDuration: const Duration(milliseconds: 200))));
    State<StatefulWidget> hostOf(String text) => t.state(find
        .ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate(
                (Widget w) => w.runtimeType.toString() == '_FadeInTokenHost'))
        .first);

    await t.pumpWidget(host('see [docs](https://ex.com/a'));
    await t.pump(const Duration(seconds: 1));
    final State<StatefulWidget> before = hostOf('docs');

    await t.pumpWidget(host('see [docs](https://ex.com/a)'));
    await t.pump();
    expect(identical(hostOf('docs'), before), isTrue);
  });
}
