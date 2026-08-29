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
      startCodeUnit: 0,
      endCodeUnit: source.length,
      startRow: 0,
      endRow: 2,
      raw: source,
      content: source,
    );

MarkdownRenderNode _paragraphNode(String source, int start) =>
    MarkdownRenderNode(
      type: 'paragraph',
      depth: 0,
      startCodeUnit: start,
      endCodeUnit: start + source.length,
      startRow: 0,
      endRow: 0,
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
    final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegionsOfSource(
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

  test('the text the tags wrapped survives a selection across blocks', () {
    // Painted but not copyable is its own bug: the block used to contribute an
    // empty range to the selection projection, correct only while it painted
    // nothing.
    //
    // It has to be a MULTI-block selection. Selecting this block alone cannot
    // see the difference — the helper echoes the requested plain text when no
    // segment claims it, so the broken and the fixed version return the same
    // string. That version of this test passed with the fix deleted.
    final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _paragraphNode('Before', 0),
      _htmlBlock(_source),
      _paragraphNode('After', 100),
    ];

    final String copied =
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
      nodes: nodes,
      selectedPlainText: 'Before\nImportant answer\nAfter',
      suppressRawHtml: true,
    );

    expect(copied, contains('Important answer'),
        reason: 'what is on screen has to be copyable with its neighbours');
  });
}
