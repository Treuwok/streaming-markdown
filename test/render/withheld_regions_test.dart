/// The analysis half of one scan.
///
/// `analyzeWithheldMarkdownRegions` answers, in source coordinates, what the
/// renderer would refuse to draw. Anything that maps painted text back onto
/// the source needs that answer; before #2343 it had to be re-derived by a
/// second hand-written copy of the grammar.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownRenderNode _paragraph(String source) => MarkdownRenderNode(
      type: 'paragraph',
      depth: 0,
      startCodeUnit: 0,
      endCodeUnit: source.length,
      startRow: 0,
      endRow: 0,
      raw: source,
      content: source,
    );

MarkdownRenderNode _htmlBlock(String source) => MarkdownRenderNode(
      type: 'html_block',
      depth: 0,
      startCodeUnit: 0,
      endCodeUnit: source.length,
      startRow: 0,
      endRow: 0,
      raw: source,
      content: source,
    );

Widget _hostNode(MarkdownRenderNode node) => MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: [node],
          withholdIncompleteDestinations: true,
          suppressRawHtml: true,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
        ),
      ),
    );

Widget _host(String source) => MaterialApp(
      home: Scaffold(
        body: AnimatedStreamingMarkdown(
          blocks: [_paragraph(source)],
          withholdIncompleteDestinations: true,
          suppressRawHtml: true,
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
  group('analyzeWithheldMarkdownRegions', () {
    test('reports the boundary at the opener of an unresolved link', () {
      const String source = 'Before [help](https://secret.example';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      expect(regions.safeEndCodeUnits, source.indexOf('['),
          reason: 'the whole candidate is held back from its opener, so a '
              'later `](` cannot retract an already-painted label');
    });

    test('reports nothing for a source with no unresolved destination', () {
      const String source = 'Before [help](https://ok.example) after';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      expect(regions.safeEndCodeUnits, source.length);
      expect(regions.hiddenCodeUnitRanges, isEmpty);
    });

    test('counts UTF-16 code units, not bytes', () {
      // The failure this pins is silent: every offset here is identical under
      // both units for ASCII, so an ASCII-only fixture cannot see it. The
      // block model calls these offsets `startCodeUnit` and they are not.
      const String prefix = '先看這裡 ';
      const String source = '$prefix[help](https://secret.example';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      expect(regions.safeEndCodeUnits, prefix.length);
      expect(source.substring(0, regions.safeEndCodeUnits), prefix);
    });

    test('reports raw HTML as a hidden range, not as a boundary', () {
      // The leading paragraph is load-bearing: with the tag in the first
      // block, a report that forgot to translate block-local offsets into
      // source offsets would still be right by accident.
      const String source =
          'first\n\nsecond a <a href="https://x.example">b</a> c';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      expect(regions.safeEndCodeUnits, source.length,
          reason: 'a closed tag does not stop the stream; it just paints '
              'nothing');
      final List<String> hiddenText = regions.hiddenCodeUnitRanges
          .map((range) => source.substring(range.$1, range.$2))
          .toList();
      expect(hiddenText, <String>['<a href="https://x.example">', '</a>']);
    });

    test('a table the renderer synthesizes reports its real offsets', () {
      // The renderer builds one kind of block that no parser produced: a table
      // assembled from loose rows. It trims each row before joining them, so
      // the block's text is SHORTER than the span it claims — and for a while
      // the report answered that by refusing to speak for it at all, which
      // stopped the scan at the table and left everything after it unpainted.
      //
      // The rows know where they start, so the mapping is kept rather than
      // re-derived from a string it is no longer in. Every cell below is
      // indented; the offsets must point past the indentation, not at it.
      //
      // The rows below are what the NATIVE parser emits for this input; the
      // pure-Dart parser gives a whole `pipe_table` and never reaches the
      // synthesis. That is why this feeds the nodes directly: the shape only
      // occurs on the backend a host test cannot run.
      const String source = '  a | b  \n  c | d  ';
      MarkdownRenderNode row(int start, int end, int line) =>
          MarkdownRenderNode(
            type: 'pipe_table_row',
            depth: 0,
            startCodeUnit: start,
            endCodeUnit: end,
            startRow: line,
            endRow: line,
            raw: source.substring(start, end),
            content: source.substring(start, end),
          );

      final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
        source,
        blocks: <MarkdownRenderNode>[row(0, 9, 0), row(10, 19, 1)],
        suppressRawHtml: true,
        sourceComplete: true,
      );

      expect(regions.visibleText, 'a\nb\nc\nd');

      // The assertion that would have failed before: each painted character
      // read back out of the source at the offset the report gives for it.
      // Trimmed text rebased on the block's start put `b` on the `|`.
      final String readBack = <int>[
        for (final int at in regions.visibleSourceOffsets) at,
      ].map((int at) => source[at]).join();
      expect(readBack.replaceAll(RegExp(r'\s'), ''), 'abcd');

      // And the scan no longer stops at the table, so a block after it would
      // still be reported.
      expect(regions.safeEndCodeUnits, source.length);
    });

    test('and an unfinished link inside that table is not declared safe', () {
      // The half that matters. A cell here holds a destination that has not
      // finished arriving, and the caller paints
      // `source.substring(0, safeEndCodeUnits)` — so a boundary of
      // `source.length` puts that URL on the screen.
      //
      // This used to be protected by the table being skipped whole. It is not
      // skipped any more, so the protection now has to come from the inline
      // rules reading the cell — which is the point: the block is examined
      // rather than excused.
      const String source = '  a | b  \n  c | [x](https://secret.example  ';
      final int newline = source.indexOf('\n');
      MarkdownRenderNode row(int start, int end, int line) =>
          MarkdownRenderNode(
            type: 'pipe_table_row',
            depth: 0,
            startCodeUnit: start,
            endCodeUnit: end,
            startRow: line,
            endRow: line,
            raw: source.substring(start, end),
            content: source.substring(start, end),
          );
      List<MarkdownRenderNode> blocks() => <MarkdownRenderNode>[
            row(0, newline, 0),
            row(newline + 1, source.length, 1),
          ];

      final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
        source,
        blocks: blocks(),
        suppressRawHtml: true,
      );

      expect(source.substring(0, regions.safeEndCodeUnits),
          isNot(contains('secret.example')));

      // With destination withholding OFF the caller has asked for the
      // historical behaviour — an unresolved `[label](https://…` painted as
      // literal source — so there is nothing left to withhold here and the
      // boundary is free to reach the end. Before, the boundary stopped at 0
      // for a reason that had nothing to do with this input: the block was
      // never read. That is no longer a reason.
      final WithheldMarkdownRegions htmlOnly = analyzeWithheldMarkdownRegions(
        source,
        blocks: blocks(),
        withholdIncompleteDestinations: false,
        suppressRawHtml: true,
      );
      expect(htmlOnly.safeEndCodeUnits, source.length);

      // With every withholding rule off there is nothing to protect, so the
      // report keeps its boundary rather than throwing the rest away.
      final WithheldMarkdownRegions nothingWithheld =
          analyzeWithheldMarkdownRegions(
        source,
        blocks: blocks(),
        withholdIncompleteDestinations: false,
        suppressRawHtml: false,
      );
      expect(nothingWithheld.safeEndCodeUnits, source.length);
    });

    test('a lone CR stops the scan', () {
      // CommonMark calls a lone CR a line ending and this parser does not, so
      // the fence below never closes for it and swallows the rest — painting
      // the unfinished destination verbatim as code. The report will not vouch
      // for text it read under a grammar the spec disagrees with.
      //
      // ⚠️ Removed in #5 and put back. The comment that used to sit next to
      // this explained the analysis-vs-renderer disagreement, and that reason
      // really did go away — so it read like the whole justification. It was
      // not: `SMD-W-05 unsupported link grammar stays fail-closed` on the
      // consuming app says a half-arrived destination must not be painted at
      // all, and this construction is one of its twelve fixtures.
      const String source =
          '```md\ncode\r```\r[help](https://secret.example';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      // At or before the CR, not exactly at it: a block that reaches past the
      // CR is one the report cannot speak for at all, so the boundary goes to
      // that block's start. Pinning the exact index would be pinning which of
      // the two floors happened to be lower for this fixture.
      expect(regions.safeEndCodeUnits, lessThanOrEqualTo(source.indexOf('\r')));
      expect(source.substring(0, regions.safeEndCodeUnits),
          isNot(contains('secret.example')));

      // The boundary goes to the BLOCK's start, not to the CR — the block is
      // skipped, so nothing in it was scanned, and stopping at the CR would
      // declare the unscanned part before it safe. That is not theoretical:
      // this exact source handed the destination to the caller.
      expect(
        analyzeWithheldMarkdownRegionsOfSource(
                '[x](https://secret.example\rmore')
            .safeEndCodeUnits,
        0,
      );

      // TWO unreadable blocks: the boundary belongs to the FIRST one. The scan
      // stops there, so nothing later can move the boundary at all.
      //
      // What this catches is the scan carrying ON past an unreadable block:
      // the second one's start is LARGER, so assigning it RAISES the boundary
      // over a stretch nobody read. (A running minimum would answer 0 here
      // too — this fixture does not separate those two, and is not trying to.)
      final WithheldMarkdownRegions two = analyzeWithheldMarkdownRegionsOfSource(
        'one\rtwo\n\nthree\rfour',
      );
      expect(two.safeEndCodeUnits, 0);

      // The ledger stops cleanly, with no separator dangling off the end.
      //
      // A block separator is the gap BETWEEN two blocks, and once the scan
      // stops there is no block after this one to be separated from. The
      // earlier shape emitted it anyway — the next block asked for it before
      // finding out it would be clipped — and its offset sat just below the
      // boundary, so the clip kept it. `visibleText` ended in a `\n` that
      // separated the last block from nothing.
      final WithheldMarkdownRegions stops =
          analyzeWithheldMarkdownRegionsOfSource(
        'hello world\n\nlone\rCR here\n\nhello world',
      );
      expect(stops.visibleText, 'hello world');
      expect(stops.visibleSourceOffsets.last, 10);

      // A `\r` that is the last code unit received is NOT a lone CR while the
      // source is still arriving — it is half of a CRLF that has not finished.
      // Calling it lone blanks the block being typed for one frame, and a
      // chunk boundary between `\r` and `\n` is ordinary.
      expect(
        analyzeWithheldMarkdownRegionsOfSource('first para\n\nsecond\r')
            .safeEndCodeUnits,
        'first para\n\nsecond\r'.length,
      );
      expect(
        analyzeWithheldMarkdownRegionsOfSource('first para\n\nsecond\r',
                sourceComplete: true)
            .safeEndCodeUnits,
        lessThan('first para\n\nsecond\r'.length),
      );

      // And a parser that DOES read the CR as a line ending ends its block
      // there, so no block spans it and nothing stops. This is why the rule
      // reads the blocks rather than the source: scanning the string would
      // penalise a backend for something it gets right.
      const String split = 'first\rsecond';
      MarkdownRenderNode para(int start, int end) => MarkdownRenderNode(
            type: 'paragraph',
            depth: 0,
            startCodeUnit: start,
            endCodeUnit: end,
            startRow: 0,
            endRow: 0,
            raw: split.substring(start, end),
            content: split.substring(start, end),
          );
      expect(
        analyzeWithheldMarkdownRegions(
          split,
          blocks: <MarkdownRenderNode>[para(0, 5), para(6, 12)],
        ).safeEndCodeUnits,
        split.length,
      );

      // And with every withholding rule off there is nothing for the rule to
      // protect: the screen paints past the CR, so dropping the content would
      // only lose it. The rule exists because of withholding and goes away
      // with it.
      expect(
        analyzeWithheldMarkdownRegionsOfSource(
          source,
          withholdIncompleteDestinations: false,
          suppressRawHtml: false,
        ).safeEndCodeUnits,
        source.length,
      );
    });

    test('a newline never releases a destination mid-stream', () {
      // Three bugs, one cause: this scanner and the renderer are handed
      // DIFFERENT strings, so "a newline already ended this" fired on one side
      // and not the other. A block's raw slice keeps the trailing newline its
      // rendered content drops; a list item's raw keeps the continuation break
      // its joined content drops.
      for (final String source in <String>[
        'see [x](https://secret.example\n',
        '- see [help\n  ](https://secret.example',
      ]) {
        final WithheldMarkdownRegions regions =
            analyzeWithheldMarkdownRegionsOfSource(source);
        expect(source.substring(0, regions.safeEndCodeUnits),
            isNot(contains('secret.example')),
            reason: source);
      }
    });

    test('leaves a fenced code block alone', () {
      // Over-hiding is the failure a leak test cannot see: a code fence is
      // deliberately showing its contents, including syntax that would be
      // held back anywhere else.
      // Tilde fences, not backtick: a backtick fence's own marker is also an
      // inline code-span opener, so the content would be skipped for the wrong
      // reason and the guard would look present while doing nothing.
      const String source = '~~~\ntext <a href="https://shown.example\n~~~';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      expect(regions.safeEndCodeUnits, source.length);
      expect(regions.hiddenCodeUnitRanges, isEmpty);
    });

    test('settles prose once the source is final, but never a destination',
        () {
      // The two halves of the same call. `[not a link` has no destination in
      // it, so holding it back after the stream ends would hide the author's
      // own words; `[x](https://…` does, and the stream ending does not make
      // showing it correct.
      const String prose = 'see [not a link';
      expect(
        analyzeWithheldMarkdownRegionsOfSource(prose, sourceComplete: true)
            .safeEndCodeUnits,
        prose.length,
      );
      expect(analyzeWithheldMarkdownRegionsOfSource(prose).safeEndCodeUnits,
          prose.indexOf('['));

      const String truncated = 'see [x](https://secret.example';
      expect(
        analyzeWithheldMarkdownRegionsOfSource(truncated, sourceComplete: true)
            .safeEndCodeUnits,
        truncated.indexOf('['),
      );
    });

    test('resolves a reference link against a definition anywhere in source',
        () {
      const String resolved = 'see [help][ref]\n\n[ref]: https://ok.example';
      expect(analyzeWithheldMarkdownRegionsOfSource(resolved).safeEndCodeUnits,
          resolved.length);

      // A closed reference form carries no destination — the URL lives in the
      // definition block — so it shows as the author's text and a definition
      // arriving later upgrades it. Only an OPEN candidate is held back, where
      // a late `](` would retract a label that was already painted.
      const String unresolved = 'see [help][ref]';
      expect(analyzeWithheldMarkdownRegionsOfSource(unresolved).safeEndCodeUnits,
          unresolved.length);

      const String open = 'see [help';
      expect(analyzeWithheldMarkdownRegionsOfSource(open).safeEndCodeUnits,
          open.indexOf('['));
    });
  });

  group('a block of raw HTML', () {
    // This group used to assert the opposite — that the whole block is hidden
    // and paints nothing. That rule threw away the prose between the tags, so
    // an answer wrapped in `<div>` disappeared. The tag-hiding half of it is
    // what mattered and is asserted below; the text-keeping half has its own
    // file, `raw_html_block_keeps_its_text_test.dart`.
    const String source = '<div>\n<a href="https://secret.example">b</a>\n</div>';

    test('hides every tag in it, and only the tags', () {
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegionsOfSource(source);
      final StringBuffer hidden = StringBuffer();
      for (final (int start, int end) range in regions.hiddenCodeUnitRanges) {
        hidden.write(source.substring(range.$1, range.$2));
      }
      expect(hidden.toString(),
          '<div><a href="https://secret.example"></a></div>');
    });

    testWidgets('paints the label without the destination', (tester) async {
      await tester.pumpWidget(_hostNode(_htmlBlock(source)));
      await tester.pump();
      final String painted = _painted(tester);
      expect(painted, isNot(contains('secret.example')),
          reason: 'an attribute is not visible text');
      expect(painted, contains('b'),
          reason: 'the text the tags wrapped is the answer');
    });
  });

  group('the analysis and the rendering are one scan', () {
    // If these two ever disagree, something painted text the analysis promised
    // was not painted — which is the entire failure mode the second copy of
    // the grammar used to cause.
    const List<String> fixtures = <String>[
      // With NO leading word. Every fixture here used to start with one, and
      // that is why the empty-token path — where the withheld construct is the
      // first thing in the block — went unnoticed while three renderers fell
      // back to drawing the raw source.
      '[help](https://secret.example',
      '<a href="https://secret.example',
      'see [help](https://secret.example',
      'see [foo `]` bar](https://secret.example)',
      'see <a href="https://secret.example',
      'a <a href="https://x.example">b</a> c',
      'see [help](https://ok.example) after',
      'plain text with no syntax at all',
      'use x < 5 and <mailto:a@b> today',
    ];

    for (final String source in fixtures) {
      testWidgets('nothing the analysis withheld reaches paint: $source',
          (tester) async {
        final WithheldMarkdownRegions regions =
            analyzeWithheldMarkdownRegionsOfSource(source);
        await tester.pumpWidget(_host(source));
        await tester.pump();
        final String painted = _painted(tester);

        // Assert on the destinations themselves, not on the whole tail:
        // `isNot(contains(tail))` passes as long as the tail is not painted
        // VERBATIM, so painting just the URL out of it slips through.
        final String tail = source.substring(regions.safeEndCodeUnits);
        for (final String secret in const <String>[
          'secret.example',
          'private.example',
        ]) {
          if (tail.contains(secret)) {
            expect(painted, isNot(contains(secret)),
                reason: 'the analysis said this is held back');
          }
        }
        for (final (int, int) range in regions.hiddenCodeUnitRanges) {
          final String hidden = source.substring(range.$1, range.$2);
          expect(painted, isNot(contains(hidden)),
              reason: 'the analysis said this range paints nothing');
        }
      });
    }
  });
}
