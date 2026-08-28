/// The visible text, and where every character of it came from.
///
/// This is the pair that lets a reveal cursor, an announcement, or a caption
/// timeline work from the same scan that paints the screen. Before it, mobile
/// re-derived both: it parsed the text a SECOND time with a different Markdown
/// package to get the plain text, then aligned that result back to the source
/// heuristically. Two parsers, no guarantee they agreed, and an alignment that
/// could silently give up.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

WithheldMarkdownRegions _scan(String source) => analyzeWithheldMarkdownRegions(
      source,
      suppressRawHtml: true,
      sourceComplete: true,
    );

void main() {
  group('the visible text is what a reader sees', () {
    const Map<String, String> cases = <String, String>{
      'hello': 'hello',
      '**bold** and _em_': 'bold and em',
      '[label](https://example.test)': 'label',
      'a <b>tag</b> c': 'a tag c',
      '<div>\nImportant answer\n</div>': 'Important answer',
      'see `code` here': 'see code here',
      'para one\n\npara two': 'para one\npara two',
      '```\nlet x = 1\n```': 'let x = 1',
    };

    cases.forEach((String source, String expected) {
      test(source.split('\n').join('|'), () {
        expect(_scan(source).visibleText, expected);
      });
    });
  });

  group('every visible character points back at itself', () {
    // The property that makes the offsets usable: for text that IS a verbatim
    // slice, source[offset] must be the very character that was painted. An
    // off-by-one anywhere in the scan shows up here and nowhere else.
    for (final String source in const <String>[
      'hello world',
      '**bold** tail',
      'lead [label](https://example.test) tail',
      'a <b>tag</b> c',
      'see `code` here',
      'x <https://auto.example> y',
      'para one\n\npara two',
      '- item one\n- item two',
      '# Heading\n\nbody',
      '> quoted text',
      '```\nlet x = 1\n```',
      '<div>\nkeep this\n</div>',
    ]) {
      test(source.split('\n').join('|'), () {
        final WithheldMarkdownRegions r = _scan(source);
        expect(r.visibleSourceOffsets.length, r.visibleText.length,
            reason: 'one offset per visible code unit');

        for (int i = 0; i < r.visibleText.length; i++) {
          final String painted = r.visibleText[i];
          if (painted == '\n') {
            continue; // block separators have no single source character
          }
          final int at = r.visibleSourceOffsets[i];
          expect(at, inInclusiveRange(0, source.length - 1),
              reason: 'offset $at for visible[$i] is outside the source');
          expect(source[at], painted,
              reason: 'visible[$i] = "$painted" claims to come from '
                  'source[$at] = "${source[at]}"');
        }
      });
    }
  });

  test('offsets never go backwards', () {
    // A reveal cursor derived from these advances monotonically; if the list
    // did not, revealing one more character could move the cursor back.
    final WithheldMarkdownRegions r =
        _scan('lead **bold** [label](https://example.test) `code` tail');
    for (int i = 1; i < r.visibleSourceOffsets.length; i++) {
      expect(r.visibleSourceOffsets[i], greaterThanOrEqualTo(r.visibleSourceOffsets[i - 1]),
          reason: 'offset went backwards at $i');
    }
  });

  test('a withheld destination contributes no visible text', () {
    // The original #2343 case: the URL has not arrived, so nothing from it
    // may be counted as painted.
    final WithheldMarkdownRegions r = analyzeWithheldMarkdownRegions(
      'see [help](https://secret.example',
      suppressRawHtml: true,
    );
    expect(r.visibleText, isNot(contains('secret.example')));
  });

  group('blocks that paint no text contribute none', () {
    // Each of these draws a rule, a gap, or nothing at all. Counting their
    // source as painted characters credited a reveal budget for text the
    // reader never sees, and the cursor then ran ahead of the screen.
    for (final String source in const <String>[
      '***',
      '---',
      '[ref]: https://example.test',
    ]) {
      test(source, () => expect(_scan(source).visibleText, isEmpty));
    }
  });
}
