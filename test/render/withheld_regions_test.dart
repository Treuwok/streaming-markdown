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
      startByte: 0,
      endByte: source.length,
      startRow: 0,
      endRow: 0,
      raw: source,
      content: source,
    );

MarkdownRenderNode _htmlBlock(String source) => MarkdownRenderNode(
      type: 'html_block',
      depth: 0,
      startByte: 0,
      endByte: source.length,
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
          analyzeWithheldMarkdownRegions(source);
      expect(regions.safeEndCodeUnits, source.indexOf('['),
          reason: 'the whole candidate is held back from its opener, so a '
              'later `](` cannot retract an already-painted label');
    });

    test('reports nothing for a source with no unresolved destination', () {
      const String source = 'Before [help](https://ok.example) after';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegions(source);
      expect(regions.safeEndCodeUnits, source.length);
      expect(regions.hiddenCodeUnitRanges, isEmpty);
    });

    test('counts UTF-16 code units, not bytes', () {
      // The failure this pins is silent: every offset here is identical under
      // both units for ASCII, so an ASCII-only fixture cannot see it. The
      // block model calls these offsets `startByte` and they are not.
      const String prefix = '先看這裡 ';
      const String source = '$prefix[help](https://secret.example';
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegions(source);
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
          analyzeWithheldMarkdownRegions(source);
      expect(regions.safeEndCodeUnits, source.length,
          reason: 'a closed tag does not stop the stream; it just paints '
              'nothing');
      final List<String> hiddenText = regions.hiddenCodeUnitRanges
          .map((range) => source.substring(range.$1, range.$2))
          .toList();
      expect(hiddenText, <String>['<a href="https://x.example">', '</a>']);
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
          analyzeWithheldMarkdownRegions(source);
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
        analyzeWithheldMarkdownRegions(prose, sourceComplete: true)
            .safeEndCodeUnits,
        prose.length,
      );
      expect(analyzeWithheldMarkdownRegions(prose).safeEndCodeUnits,
          prose.indexOf('['));

      const String truncated = 'see [x](https://secret.example';
      expect(
        analyzeWithheldMarkdownRegions(truncated, sourceComplete: true)
            .safeEndCodeUnits,
        truncated.indexOf('['),
      );
    });

    test('resolves a reference link against a definition anywhere in source',
        () {
      const String resolved = 'see [help][ref]\n\n[ref]: https://ok.example';
      expect(analyzeWithheldMarkdownRegions(resolved).safeEndCodeUnits,
          resolved.length);

      const String unresolved = 'see [help][ref]';
      expect(analyzeWithheldMarkdownRegions(unresolved).safeEndCodeUnits,
          unresolved.indexOf('['),
          reason: 'the definition may still be in flight');
    });
  });

  group('a whole block of raw HTML', () {
    const String source = '<div>\n<a href="https://secret.example">b</a>\n</div>';

    test('is reported as one hidden range covering the block', () {
      final WithheldMarkdownRegions regions =
          analyzeWithheldMarkdownRegions(source);
      expect(regions.hiddenCodeUnitRanges, <(int, int)>[(0, source.length)]);
    });

    testWidgets('paints nothing, so the two answers agree', (tester) async {
      await tester.pumpWidget(_hostNode(_htmlBlock(source)));
      await tester.pump();
      expect(_painted(tester), isEmpty,
          reason: 'the analysis reports the block as painting nothing; if the '
              'renderer drew it, the reveal cursor would credit visible text '
              'the analysis said did not exist');
    });
  });

  group('the analysis and the rendering are one scan', () {
    // If these two ever disagree, something painted text the analysis promised
    // was not painted — which is the entire failure mode the second copy of
    // the grammar used to cause.
    const List<String> fixtures = <String>[
      'see [help](https://secret.example',
      'see <https://secret.example',
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
            analyzeWithheldMarkdownRegions(source);
        await tester.pumpWidget(_host(source));
        await tester.pump();
        final String painted = _painted(tester);

        final String tail = source.substring(regions.safeEndCodeUnits);
        if (tail.trim().length > 2) {
          expect(painted, isNot(contains(tail)),
              reason: 'the analysis said this tail is held back');
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
