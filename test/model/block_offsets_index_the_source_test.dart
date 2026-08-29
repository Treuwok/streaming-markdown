/// A block's offsets index the string the block came from.
///
/// This is the whole contract of `startCodeUnit` / `endCodeUnit`, and it is
/// deliberately written so that it does not care which parser produced the
/// blocks — because the bug it guards was precisely that the answer depended
/// on that. Tree-sitter counts UTF-8 bytes; a Dart string is indexed in UTF-16
/// code units; the field carried whichever one the active backend happened to
/// produce, under a name that claimed bytes.
///
/// ⚠️ Every fixture here is non-ASCII on purpose. For ASCII the two units are
/// the same number, so an ASCII fixture passes with or without the fix and
/// tells you nothing. That is why nothing caught this for as long as it lasted.
///
/// ⚠️ Honest limit: on a machine without the native library both backends fall
/// back to pure Dart, which always produced code units, so this passes there
/// either way. It fails before the fix only where the native parser actually
/// runs — which is where the product runs.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<(String, String)> sources = <(String, String)>[
    ('chinese prose', '第一段落文字\n\n第二段落文字'),
    ('chinese and ascii mixed', '先看這裡 abc\n\n第二段 def'),
    ('a heading and a list', '# 標題文字\n\n- 第一項\n- 第二項'),
    ('a fence with chinese inside', '```dart\n// 註解文字\nprint(1);\n```'),
    ('accented latin', 'café naïve\n\ndeuxième paragraphe'),
    ('an emoji, which is a surrogate pair', '開始 \u{1F600} 結束\n\n下一段'),
    ('ascii only, as the control', 'first para\n\nsecond para'),
  ];

  for (final (String name, String source) in sources) {
    test('$name — every block slices back to its own raw text', () {
      final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
        source,
      );

      expect(result.blocks, isNotEmpty, reason: 'nothing to check otherwise');

      for (final MarkdownRenderNode block in result.blocks) {
        expect(block.startCodeUnit, inInclusiveRange(0, source.length),
            reason: '${block.type} start is a valid string index');
        expect(block.endCodeUnit, inInclusiveRange(0, source.length),
            reason: '${block.type} end is a valid string index');
        expect(
          source.substring(block.startCodeUnit, block.endCodeUnit),
          block.raw,
          reason: '${block.type} — native=${result.nativeAvailable}',
        );
      }
    });
  }

  group('a producer that never converted its offsets is refused', () {
    // The half of this change that a machine without the native library can
    // actually exercise. The native path is where the wrong unit came from and
    // it cannot run here — so instead of asserting the conversion happened,
    // this asserts that skipping it is impossible to do quietly.
    //
    // `startByte` was UTF-8 bytes on one path and code units on the other, and
    // both read fine as an integer. A producer left behind by this change
    // would have kept working and been wrong by a factor of three on Chinese.
    test('the old key throws instead of being read as code units', () {
      expect(
        () => MarkdownRenderNode.fromDynamicMap(<String, Object>{
          'type': 'paragraph',
          'depth': 0,
          'startByte': 0,
          'endByte': 12,
          'startRow': 0,
          'endRow': 0,
          'raw': '先看這裡',
          'content': '先看這裡',
        }),
        throwsArgumentError,
      );
    });

    test('the new key is read normally', () {
      final MarkdownRenderNode node =
          MarkdownRenderNode.fromDynamicMap(<String, Object>{
        'type': 'paragraph',
        'depth': 0,
        'startCodeUnit': 0,
        'endCodeUnit': 4,
        'startRow': 0,
        'endRow': 0,
        'raw': '先看這裡',
        'content': '先看這裡',
      });
      expect(node.startCodeUnit, 0);
      expect(node.endCodeUnit, 4);
      expect('先看這裡'.substring(node.startCodeUnit, node.endCodeUnit),
          node.raw);
    });
  });

  test('the offsets advance through the source and never invert', () {
    // Ordering is what the render pipeline uses these for, and it survives a
    // wrong unit as long as the unit is wrong CONSISTENTLY — which is why the
    // pipeline never noticed. Worth pinning so a change that converts only
    // some producers shows up here rather than in a cursor.
    //
    // Starts only, not "each start follows the previous end": the native
    // parser returns a depth-first flattened TREE, so a `list` is followed by
    // the `list_item`s inside it, whose starts are legitimately before the
    // container's end. Asserting non-overlap would fail on the one backend
    // this test exists to check.
    const String source = '# 標題\n\n段落一\n\n- 甲\n- 乙\n\n段落二';
    final List<MarkdownRenderNode> blocks =
        MarkdownSyncParser.parseMarkdown(source).blocks;

    int previousStart = 0;
    for (final MarkdownRenderNode block in blocks) {
      expect(block.startCodeUnit, greaterThanOrEqualTo(previousStart),
          reason: '${block.type} starts no earlier than the block before it');
      expect(block.endCodeUnit, greaterThanOrEqualTo(block.startCodeUnit),
          reason: '${block.type} does not end before it starts');
      expect(block.endCodeUnit, lessThanOrEqualTo(source.length),
          reason: '${block.type} stays inside the source');
      previousStart = block.startCodeUnit;
    }
  });
}
