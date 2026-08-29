/// The translation between what tree-sitter counts and what a Dart string is
/// indexed in.
///
/// Every case here is one where the two numbers differ. An ASCII fixture
/// cannot fail any of them, which is exactly how one field came to carry both
/// units without anything noticing.
library;

import 'dart:convert';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the answer must be, computed the slow honest way.
int _expected(String source, int byteOffset) =>
    utf8.decode(utf8.encode(source).sublist(0, byteOffset)).length;

void main() {
  group('every character boundary maps to itself', () {
    for (final (String name, String source) in const <(String, String)>[
      ('ascii', 'hello world'),
      ('cjk', '先看這裡'),
      ('cjk and ascii', '先看這裡 abc 第二段'),
      ('two-byte latin', 'café naïve'),
      ('emoji, which is a surrogate pair', 'a\u{1F600}b'),
      ('mixed with newlines', '# 標題\n\n段落 with ascii\n\n- 項目'),
      ('empty', ''),
    ]) {
      test(name, () {
        final Utf8CodeUnitIndex index = Utf8CodeUnitIndex(source);
        final List<int> bytes = utf8.encode(source);

        expect(index.byteLength, bytes.length, reason: 'byte length');
        expect(index.codeUnitLength, source.length, reason: 'code-unit length');

        // Walk every byte offset that starts a character, which is every
        // offset a parser can report.
        for (int b = 0; b <= bytes.length; b++) {
          final bool startsCharacter =
              b == bytes.length || (bytes[b] & 0xC0) != 0x80;
          if (!startsCharacter) {
            continue;
          }
          expect(index.codeUnitFor(b), _expected(source, b),
              reason: 'byte $b of ${source.length} code units');
        }
      });
    }
  });

  test('a substring taken at the translated offset is the right substring', () {
    // The property the callers actually need: a block reported as bytes
    // [start, end) must come back as the same text when sliced by code units.
    const String source = '先看這裡\n\nsecond 段落\n\n第三段 x';
    final List<int> bytes = utf8.encode(source);
    final Utf8CodeUnitIndex index = Utf8CodeUnitIndex(source);

    // These names say `Byte` because these ARE byte offsets. A blanket rename
    // across the suite turned them into `startCodeUnit` for a moment, which is
    // the same lie this whole change removes, told in the one test that exists
    // to keep the two units apart.
    for (final (int startByte, int endByte) in const <(int, int)>[
      (0, 12),
      (14, 27),
      (0, 0),
    ]) {
      expect(
        source.substring(
            index.codeUnitFor(startByte), index.codeUnitFor(endByte)),
        utf8.decode(bytes.sublist(startByte, endByte)),
        reason: 'bytes [$startByte, $endByte)',
      );
    }
  });

  test('an offset inside a character rounds down to its start', () {
    // No parser should report one, but rounding down yields a valid string
    // index while splitting the character yields a corrupt substring.
    final Utf8CodeUnitIndex index = Utf8CodeUnitIndex('先x');
    expect(index.codeUnitFor(0), 0);
    expect(index.codeUnitFor(1), 0);
    expect(index.codeUnitFor(2), 0);
    expect(index.codeUnitFor(3), 1);
  });

  test('offsets outside the source clamp to its ends', () {
    final Utf8CodeUnitIndex index = Utf8CodeUnitIndex('先看');
    expect(index.codeUnitFor(-5), 0);
    expect(index.codeUnitFor(999), 2);
  });
}
