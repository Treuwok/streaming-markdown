/// Suppressing raw HTML means hiding the TAGS, not the prose between them.
///
/// A block-level tag (`<div>` at the start of a line) used to be answered by a
/// rule of its own — "an html_block paints nothing" — in both halves of the
/// scan. That rule was a coarser second copy of the tag-hiding decision the
/// inline scan already makes, and it threw away the answer text with the tags.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _source = '<div>\nImportant answer\n</div>';

MarkdownRenderNode _htmlBlock(String source) => MarkdownRenderNode(
      type: 'html_block',
      depth: 0,
      startByte: 0,
      endByte: source.length,
      startRow: 0,
      endRow: 2,
      raw: source,
      content: source,
    );

String _painted(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final Element element in find.byType(RichText).evaluate()) {
    buffer.write((element.widget as RichText).text.toPlainText());
  }
  return buffer.toString();
}

void main() {
  test('the analysis hides the tags and nothing else', () {
    final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
      _source,
      suppressRawHtml: true,
      sourceComplete: true,
    );

    expect(regions.safeEndCodeUnits, _source.length,
        reason: 'nothing here is an unresolved destination');

    final StringBuffer hidden = StringBuffer();
    for (final (int start, int end) range in regions.hiddenCodeUnitRanges) {
      hidden.write(_source.substring(range.$1, range.$2));
    }
    // Exact, not `isNot(contains(...))`: over-hiding is the failure that looks
    // like success, so assert on what IS hidden rather than what is not.
    expect(hidden.toString(), '<div></div>');
  });

  testWidgets('the renderer paints the text between the tags', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: [_htmlBlock(_source)],
          suppressRawHtml: true,
          sourceComplete: true,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
        ),
      ),
    ));
    await tester.pump();

    final String painted = _painted(tester);
    expect(painted, contains('Important answer'),
        reason: 'the tag goes, the text it wrapped stays');
    expect(painted, isNot(contains('<div>')));
    expect(painted, isNot(contains('</div>')));
  });

  test('the text the tags wrapped can be selected and copied', () {
    // Painted but not selectable is its own bug: the block used to contribute
    // an empty range to the selection projection, which was right only while
    // it painted nothing. Now that the prose is on screen, a selection that
    // spans it must carry it.
    final String copied =
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
      nodes: <MarkdownRenderNode>[_htmlBlock(_source)],
      selectedPlainText: 'Important answer',
      suppressRawHtml: true,
    );
    expect(copied, contains('Important answer'));
  });
}
