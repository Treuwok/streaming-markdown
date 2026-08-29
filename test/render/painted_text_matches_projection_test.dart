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
    }
  });
}
