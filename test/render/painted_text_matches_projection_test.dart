/// The projection says what is on the screen. This asks the screen.
///
/// Every other test here states an expected string, which means the
/// expectation is written by whoever wrote the code — so a projection and an
/// assertion can be wrong together and still be green. This one takes the
/// answer from the rendered widget tree, so there is nothing to get wrong:
/// if the report and the pixels disagree, it fails.
///
/// What it can and cannot see, stated plainly, because the difference is not
/// obvious from the assertions: the renderer now takes its text FROM the plan,
/// so for anything it reads there the two literally cannot disagree — break
/// the plan and the screen breaks with it, and this stays green. That is the
/// architecture doing the work, not this test. What is left for a test is the
/// residue: the projection getters, which summarise the plan a second time for
/// a reader who is not the renderer. Reintroducing the old table bug — a
/// projection that scans for its own cells — does turn this red.
///
/// Not covered, and deliberately: `suppressRawHtml: false`. That renders raw
/// HTML as a card which paints its own DOM text, and the report omits it — a
/// known, silent gap documented on `_HtmlCardPlan`. Every caller in this repo
/// passes `true`, which is what these fixtures use.
///
/// It exists because they disagreed on almost every block type. The analysis
/// used to run its own switch over block types, written to mirror the
/// renderer's and sitting right beside it. Reviewers found the drift one case
/// at a time — a fence header reported as `dart linenums` while `dart` was
/// painted, a loose table reporting rows the renderer had already discarded,
/// an empty fence reporting a language for a block that draws nothing. Every
/// fixture below is one of those. The two switches are now one, and this is
/// what keeps them one.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every non-whitespace character the widget tree draws, sorted.
///
/// Sorted, because order is the other test's job: the report separates its
/// pieces with newlines, the screen separates them with layout, and a widget
/// span puts its own child after the run it sits inside. What this compares is
/// WHICH characters reach the screen — which is what every one of these
/// findings was about, in both directions (a header reported but not painted,
/// a footnote number painted but not reported).
///
/// Left out deliberately, because the projection leaves them out too and both
/// are decisions rather than oversights: anything under a disabled selection
/// container (a list bullet, an ordered marker, a task checkbox — chrome, not
/// the answer), icons (a callout's symbol is a glyph in a `RichText` as well),
/// and the placeholder a widget span leaves behind (the widget it stands for
/// draws its own text).
List<String> _paintedChars(WidgetTester tester) {
  final StringBuffer painted = StringBuffer();
  void visit(Element element) {
    final Widget widget = element.widget;
    if (widget is SelectionContainer && widget.registrar == null) {
      return;
    }
    if (widget is Icon) {
      // An icon is a glyph in a `RichText` too — a callout's symbol, not text.
      return;
    }
    // `Text` builds a `RichText`, so collecting only `RichText` counts every
    // painted glyph exactly once.
    if (widget is RichText) {
      painted.write(widget.text.toPlainText().replaceAll('\uFFFC', ''));
    }
    element.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return _chars(painted.toString());
}

List<String> _chars(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').split('')..sort();

Widget _host(List<MarkdownRenderNode> blocks) => MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: blocks,
          withholdIncompleteDestinations: true,
          suppressRawHtml: true,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
        ),
      ),
    );

void main() {
  const List<(String, String)> fixtures = <(String, String)>[
    // ---- code fences: the header shows the language token, nothing else ----
    ('info string carries more than the language',
        '```dart linenums\nprint(1);\n```'),
    ('a fence with no info string', '```\nlet x = 1\n```'),
    ('a fence whose body is empty paints nothing at all', '```dart\n```'),
    ('an indented block gets a generated header', '    indented code\n'),

    // ---- tables: the run and the delimiter test are the renderer's ----
    ('a loose delimiter row of colons is painted', '| a | b |\n| : | : |'),
    ('a proper delimiter row is not', '| a | b |\n| --- | --- |\n| c | d |'),
    ('the table run ends where the renderer ends it',
        'a|b\nc|d\nplain\ne|f'),

    // ---- callouts ----
    ('a custom callout title is source text', '> [!NOTE] same\n> same'),
    ('a default callout title is generated', '> [!WARNING]\n> body'),
    ('a plain quote is not a callout', '> just quoted'),

    // ---- footnote definitions ----
    ('a definition label is painted literally', '[^a]: body'),
    ('an id containing delimiters keeps them', '[^*note*]: body'),
    ('a body that also occurs in its id', '[^note]: note'),
    ('a definition body with no surviving tokens', '[^a]: **<b></b>**'),
    ('a footnote reference paints its number', 'note[^a]\n\n[^a]: body'),

    // ---- lists ----
    ('an ordered marker that repeats its body', '1. 1'),
    ('a task checkbox that repeats its body', '- [x] x'),
    ('a continuation line joins the item', '- first\n  second'),
    ('a continuation after an empty item', '- \n  continuation'),

    // ---- front matter keeps its own shape ----
    ('front matter is not folded into a paragraph',
        '---\ntitle: value\n---\n\nbody'),

    // ---- suppression leaves surviving syntax ----
    ('an inline tag suppressed to nothing', '**<b></b>**'),
    ('prose wrapped in a block tag', '<div>\nImportant answer\n</div>'),

    // ---- a standalone formula stands in for its rendered glyphs ----
    (r'a display formula on its own', r'$$x + 1$$'),
    (r'a formula inside a sentence', r'see $x + 1$ there'),

    // ---- constructs that until now only had a hand-written expectation ----
    // Moved here after three such expectations turned out to assert a bug:
    // they were written next to the code that produced them, so both were
    // wrong together and green together.
    ('a thematic break paints no text', '***'),
    ('a multi-line quote', '> line one\n> line two'),
    ('ATX closing hashes are syntax', '# Title #'),
    ('an ordered list', '1. first\n2. second'),
    ('a link reference definition is drawn', '[ref]: https://example.test'),
    ('a textless block between two paragraphs',
        'first\n\n<div></div>\n\nlast'),
    ('non-breaking space is whitespace', '\u00a0text\u00a0'),
    ('an inline image contributes no characters',
        'before ![cat](https://example.test/c.png) after'),
    ('an escaped pipe survives in a cell',
        '| a \\| b |\n| --- | --- |\n| c | d |'),

    // ---- ordinary prose, as the control ----
    ('headings and paragraphs', '# Title\n\nsome **bold** prose'),
    ('a paragraph folds its line breaks', 'first line\nsecond line'),
  ];

  for (final (String name, String source) in fixtures) {
    testWidgets('the report matches the screen: $name', (tester) async {
      final List<MarkdownRenderNode> blocks =
          MarkdownSyncParser.parseMarkdown(source).blocks;
      await tester.pumpWidget(_host(blocks));
      await tester.pump();

      final WithheldMarkdownRegions report = analyzeWithheldMarkdownRegions(
        source,
        suppressRawHtml: true,
        sourceComplete: true,
      );

      expect(_chars(report.visibleText), _paintedChars(tester),
          reason: 'source: ${source.split('\n').join(r'\n')}');
    });
  }

  test('a lone CR stops the ledger, not just the boundary', () {
    // The two block parsers read a lone CR differently, so the analysis
    // refuses to guess and stops there. The code block spanning that CR went
    // on projecting its whole remainder anyway, and the destination after it
    // reached `visibleText` with offsets 33 past `safeEndCodeUnits`.
    const String source = '```md\ncode\r```\r[help](https://secret.example';
    final WithheldMarkdownRegions report =
        analyzeWithheldMarkdownRegions(source, suppressRawHtml: true);

    expect(report.safeEndCodeUnits, source.indexOf('\r'));
    expect(report.visibleText, isNot(contains('secret.example')));
    for (final int offset in report.visibleSourceOffsets) {
      expect(offset, lessThan(report.safeEndCodeUnits));
    }
  });

  test('a hidden range that straddles the boundary is cut at it', () {
    // Not in the fixtures above on purpose: the analysis stops at the lone CR
    // and the renderer paints straight past it, so comparing them is
    // meaningless here. What is being checked is the report's own promise —
    // every range lies inside the prefix it declares safe. Without the cut
    // this range ends at 16, and a caller applying it to a 12-character
    // prefix cuts off the end of a string that is not there.
    const String source = 'x <a href="y\rz">t</a>';
    final WithheldMarkdownRegions report =
        analyzeWithheldMarkdownRegions(source, suppressRawHtml: true);

    expect(report.safeEndCodeUnits, source.indexOf('\r'));
    expect(report.hiddenCodeUnitRanges, isNotEmpty);
    for (final (int start, int end) in report.hiddenCodeUnitRanges) {
      expect(start, lessThan(report.safeEndCodeUnits));
      expect(end, lessThanOrEqualTo(report.safeEndCodeUnits));
    }
  });

  testWidgets('every reported character still points at itself', (
    tester,
  ) async {
    // The companion property. Matching text with wrong offsets would let a
    // reveal cursor cut in the wrong place, and the comparison above cannot
    // see that.
    for (final (String _, String source) in fixtures) {
      final WithheldMarkdownRegions report = analyzeWithheldMarkdownRegions(
        source,
        suppressRawHtml: true,
        sourceComplete: true,
      );
      expect(report.visibleSourceOffsets.length, report.visibleText.length,
          reason: source);
      for (final int offset in report.visibleSourceOffsets) {
        expect(offset, inInclusiveRange(0, source.length - 1), reason: source);
      }
      // Ascending, non-overlapping, inside the boundary — which is what the
      // field's own doc promises and nothing checked. A consumer cuts text at
      // these coordinates, so a pair out of order or overlapping corrupts the
      // result the same way a range past the boundary leaks it.
      int previousEnd = 0;
      for (final (int start, int end) in report.hiddenCodeUnitRanges) {
        expect(start, greaterThanOrEqualTo(previousEnd), reason: source);
        expect(end, greaterThanOrEqualTo(start), reason: source);
        expect(end, lessThanOrEqualTo(report.safeEndCodeUnits), reason: source);
        previousEnd = end;
      }

      // Never past the safety boundary. The report answers "how far is it safe
      // to draw" in one field and "here is the text" in another; a caller that
      // trusts the second has no way to learn the first was smaller. A lone CR
      // made them disagree by 34 characters, and the tail it handed over was
      // an unresolved link destination — the exact thing the boundary exists
      // to hold back.
      for (final int offset in report.visibleSourceOffsets) {
        expect(offset, lessThan(report.safeEndCodeUnits),
            reason: 'reported text past the boundary in $source');
      }
      // Never backwards. A reveal cursor walks this ledger forward and cannot
      // survive a step back — it would re-hide text it had already shown. The
      // way it happens is not obvious: a generated run (a header, a label)
      // reports ONE position for all of its characters, so a block separator
      // computed as "one past the last" can land beyond the real start of the
      // piece that follows.
      for (int i = 1; i < report.visibleSourceOffsets.length; i++) {
        expect(
          report.visibleSourceOffsets[i],
          greaterThanOrEqualTo(report.visibleSourceOffsets[i - 1]),
          reason: 'offset $i went backwards in $source',
        );
      }
    }
  });
}
