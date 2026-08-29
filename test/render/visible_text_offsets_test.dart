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
      // The line breaks either side of the suppressed tags are painted as
      // spaces, exactly as the renderer paints them.
      '<div>\nImportant answer\n</div>': ' Important answer ',
      'see `code` here': 'see code here',
      'para one\n\npara two': 'para one\npara two',
      // No info string, so no header. This used to expect `let\nlet x = 1`:
      // the language pattern ran past the opening line and labelled the
      // block with the first word of its own body.
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
          if (painted == ' ' && source[at] == '\n') {
            // The one documented substitution: a paragraph's line break is
            // painted as a space, and it still points at the break it came
            // from. Everything else must be the character itself.
            continue;
          }
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
    ]) {
      test(source, () => expect(_scan(source).visibleText, isEmpty));
    }
  });

  group('block syntax is not visible text (codex R1)', () {
    // Each of these was reported with its own syntax in it, because the
    // analysis scanned the raw block slice while the renderer scans the text
    // it extracts from that slice. They now run through the same extraction.
    const Map<String, String> cases = <String, String>{
      '# Heading': 'Heading',
      '### Deeper': 'Deeper',
      '> quoted text': 'quoted text',
      '> line one\n> line two': 'line one\nline two',
      'first line\nsecond line': 'first line second line',
      // header + body: the info string is painted above the code.
      '```dart\ndart\n```': 'dart\ndart',
      // No info string, so no header — this is the BODY. It used to be
      // `code\ncode`, because the language pattern ran past the opening line
      // and labelled the block with the first word of its own body.
      '```\ncode   \n```': 'code',
    };
    cases.forEach((String source, String expected) {
      test(source.split('\n').join('|'),
          () => expect(_scan(source).visibleText, expected));
    });
  });

  test('a block that paints nothing adds no separator', () {
    // `first\n\n<div></div>\n\nlast` — the tag-only block contributes no
    // characters, so it must not contribute a gap either. Two separators for
    // one gap shifted every offset after it.
    expect(_scan('first\n\n<div></div>\n\nlast').visibleText, 'first\nlast');
  });

  test('a definition block is painted, so it contributes its text', () {
    // The renderer draws link-reference and footnote definitions through its
    // definition-block path, so they are not textless. Skipping them made the
    // report claim an empty screen for a message that has text on it.
    expect(_scan('[ref]: https://example.test').visibleText, isNotEmpty);
  });

  test('a caller that drops definition blocks can say so', () {
    // The default renderer paints them, so the analysis cannot decide this on
    // its own. A caller that removes the block and stays quiet gets a report
    // describing text that is not on its screen.
    expect(
      analyzeWithheldMarkdownRegions(
        '[ref]: https://example.test',
        sourceComplete: true,
        hideLinkReferenceDefinitions: true,
      ).visibleText,
      isEmpty,
    );
  });

  group('list, table and callout projections (codex R2)', () {
    const Map<String, String> cases = <String, String>{
      '- item one\n- item two': 'item one\nitem two',
      '1. first\n2. second': 'first\nsecond',
      '| a | b |\n| --- | --- |\n| c | d |': 'a\nb\nc\nd',
      '> [!NOTE]\n> body text': 'Note\nbody text',
      '# Title #': 'Title',
    };
    cases.forEach((String source, String expected) {
      test(source.split('\n').join('|'),
          () => expect(_scan(source).visibleText, expected));
    });
  });

  test('a repeated table cell maps to its own occurrence', () {
    // The reason the walk is in order rather than a plain search: two cells
    // holding the same text must not both point at the first one.
    const String source = '| x | y |\n| --- | --- |\n| y | z |';
    final WithheldMarkdownRegions r = _scan(source);
    final int firstY = source.indexOf('y');
    final int secondY = source.indexOf('y', firstY + 1);
    expect(firstY, isNot(secondY));
    final List<int> yOffsets = <int>[
      for (int i = 0; i < r.visibleText.length; i++)
        if (r.visibleText[i] == 'y') r.visibleSourceOffsets[i],
    ];
    expect(yOffsets, <int>[firstY, secondY]);
  });

  test('trimming uses the same whitespace definition as the renderer', () {
    // A non-breaking space is whitespace to `String.trim`, which is what the
    // renderer used. An ASCII-only predicate kept it and started painting it.
    expect(_scan('\u00a0text\u00a0').visibleText, 'text');
  });

  test('an inline image contributes no characters', () {
    // It paints an image once loaded, nothing while loading, and a fallback
    // line on error — three screens for one source, decided at runtime. Alt
    // text agrees with none of them.
    expect(_scan('before ![cat](https://example.test/c.png) after').visibleText,
        'before  after');
  });

  group('the projection is the renderer\'s, for every block type (codex R3)',
      () {
    const Map<String, String> cases = <String, String>{
      // A definition block paints `id: body`; the identifier is visible.
      '[^a]: the note': 'a: the note',
      // Front matter keeps its line breaks — no paragraph folding.
      '---\ntitle: value\n---': '---\ntitle: value\n---',
      // A custom callout title is drawn by a plain widget, so its asterisks
      // are on the screen.
      '> [!WARNING] **Danger**\n> body': '**Danger**\nbody',
    };
    cases.forEach((String source, String expected) {
      test(source.split('\n').join('|'),
          () => expect(_scan(source).visibleText, expected));
    });

    test('a code body keeps its leading blank line', () {
      // Verbatim: the blank first line is content, not the gap between blocks.
      expect(_scan('```\n\ncode\n```').visibleText, '\ncode');
    });

    test('an unfinished destination in a later item keeps the earlier one', () {
      // The boundary is the PIECE's start, not the block's — otherwise the
      // first item is discarded along with the second.
      final WithheldMarkdownRegions r = analyzeWithheldMarkdownRegions(
        '- first\n- [link](https://unfinished',
        suppressRawHtml: true,
      );
      expect(r.visibleText, contains('first'));
      expect(r.visibleText, isNot(contains('unfinished')));
    });
  });

  test('an escaped pipe keeps the cell located', () {
    // `\\|` used to be turned into `|` by a string replace — a REWRITE, which
    // left the cell unable to say where anything in it came from, so ranges
    // inside it had to be suppressed. Dropping the backslash is a DELETION,
    // so the surviving pipe keeps its own position and the tag's range lands
    // exactly on the tag.
    const String source = '| a \\| <a href="https://secret.example">x</a> | b |\n'
        '| --- | --- |\n| c | d |';
    final WithheldMarkdownRegions r = _scan(source);
    expect(r.visibleText, 'a | x\nb\nc\nd');
    expect(
      r.hiddenCodeUnitRanges
          .map(((int, int) g) => source.substring(g.$1, g.$2))
          .toList(),
      <String>['<a href="https://secret.example">', '</a>'],
    );
  });

  test('a code block reports its header (codex R4)', () {
    // The info string is painted above the body, so it is on the screen.
    expect(_scan('```dart\nlet x = 1\n```').visibleText, 'dart\nlet x = 1');
  });

  test('a list body is not confused with its own marker (codex R4)', () {
    // `1. 1` — searching the block for the body `1` used to find the ordered
    // marker. The body's position now comes from the match that produced it.
    final WithheldMarkdownRegions r = _scan('1. 1');
    expect(r.visibleText, '1');
    expect(r.visibleSourceOffsets, <int>['1. '.length]);
  });

  test('a footnote body is not confused with its identifier (codex R4)', () {
    final WithheldMarkdownRegions r = _scan('[^note]: note');
    expect(r.visibleText, 'note: note');
    // The label is generated; the body points at the real body.
    expect(r.visibleSourceOffsets.last, '[^note]: not'.length);
  });

  test('a hidden definition still resolves its references (codex R5)', () {
    // The flag means the block is not DRAWN, not that it is gone: the mobile
    // adapter keeps those nodes in the list it hands the renderer precisely so
    // references resolve, and only suppresses their own rendering.
    expect(
      analyzeWithheldMarkdownRegions(
        'see [help][ref]\n\n[ref]: https://example.test',
        sourceComplete: true,
        hideLinkReferenceDefinitions: true,
      ).visibleText,
      'see help',
    );
  });

  test('a continuation line keeps the item traceable (codex R5)', () {
    // The joining space IS the line break it replaced, so the item stays
    // traceable end to end. A position-less space used to cost the whole item
    // every hidden range in it.
    const String source = '- first\n  <a href="https://secret.example">x</a>';
    final WithheldMarkdownRegions r = _scan(source);
    expect(r.visibleText, 'first\nx');
    expect(
      r.hiddenCodeUnitRanges
          .map(((int, int) g) => source.substring(g.$1, g.$2))
          .toList(),
      <String>['<a href="https://secret.example">', '</a>'],
    );
  });

  test('a code header is only the language token (codex R5)', () {
    // ` ```dart linenums ` paints `dart`, not the whole info string.
    expect(_scan('```dart linenums\nx\n```').visibleText, 'dart\nx');
  });

  test('a footnote reference reports the label it paints (codex R6)', () {
    // The renderer paints the assigned number, or the id when nothing defines
    // it. Both are derivable here — the earlier claim that this scan cannot
    // know the numbering was wrong.
    expect(_scan('note[^a]\n\n[^a]: body').visibleText, 'note1\na: body');
    expect(_scan('note[^undefined]').visibleText, 'noteundefined');
  });

  test('an empty fence paints nothing, header included (codex R6)', () {
    // The code widget returns early on an empty body, before its header.
    expect(_scan('```dart\n```').visibleText, isEmpty);
  });

  test('a footnote label with delimiters stays literal (codex R7)', () {
    // Drawn by a plain widget, so `*note*` keeps its asterisks and cannot
    // pair delimiters with the body beside it.
    expect(_scan('[^*note*]: body').visibleText, '*note*: body');
  });

  test('suppression leaving only syntax still paints it (codex R7)', () {
    // The renderer's own fallback: no tokens but source left over, so it
    // paints what survived rather than nothing.
    expect(_scan('**<b></b>**').visibleText, '****');
  });

  test('a tag spanning CRLF keeps its range (codex R7)', () {
    // Normalization drops the `\r`, so the tag's surviving offsets jump one.
    // Requiring +1 rejected the range and the URL went unreported.
    const String source = '<a\r\n href="https://secret.example">x</a>';
    final WithheldMarkdownRegions r = _scan(source);
    expect(r.visibleText, 'x');
    expect(
      r.hiddenCodeUnitRanges.length,
      2,
      reason: 'the opening tag and the closing one',
    );
    expect(source.substring(r.hiddenCodeUnitRanges.first.$1,
        r.hiddenCodeUnitRanges.first.$2), contains('secret.example'));
  });
}
