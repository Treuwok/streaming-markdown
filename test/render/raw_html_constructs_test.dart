/// Every construct CommonMark calls raw HTML, not just the two obvious ones.
///
/// "Do not render raw HTML" used to mean "hide comments and tags whose name
/// starts with a letter". The rest of the grammar — processing instructions,
/// declarations, CDATA, and the four elements whose content is raw text —
/// fell through as ordinary prose and was painted VERBATIM, which is a worse
/// outcome than rendering it. The set below is the spec's, so it is closed.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// (source, what must be hidden) — hidden asserted exactly, because
/// over-hiding is the failure that reads as success.
const List<(String, String)> _constructs = <(String, String)>[
  ('<!DOCTYPE html>\nanswer', '<!DOCTYPE html>'),
  ('<?php echo 1; ?>\nanswer', '<?php echo 1; ?>'),
  ('<![CDATA[x > y]]>\nanswer', '<![CDATA[x > y]]>'),
  ('<!-- note -->\nanswer', '<!-- note -->'),
  ('<style>\n.a { color: red }\n</style>\nanswer',
      '<style>\n.a { color: red }\n</style>'),
  ('<script>\nvar secret = 1;\n</script>\nanswer',
      '<script>\nvar secret = 1;\n</script>'),
];

void main() {
  for (final (String source, String mustHide) in _constructs) {
    test('hides ${mustHide.split('\n').first} and keeps the prose', () {
      final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
        source,
        suppressRawHtml: true,
        sourceComplete: true,
      );

      final StringBuffer hidden = StringBuffer();
      for (final (int start, int end) range in regions.hiddenCodeUnitRanges) {
        hidden.write(source.substring(range.$1, range.$2));
      }
      expect(hidden.toString(), mustHide);

      // The complement: the answer after the construct is still visible.
      final StringBuffer visible = StringBuffer();
      var cursor = 0;
      for (final (int start, int end) range in regions.hiddenCodeUnitRanges) {
        if (range.$1 > cursor) visible.write(source.substring(cursor, range.$1));
        cursor = range.$2;
      }
      if (cursor < regions.safeEndCodeUnits) {
        visible.write(source.substring(cursor, regions.safeEndCodeUnits));
      }
      expect(visible.toString(), contains('answer'));
    });
  }

  test('a name that merely starts with a raw-text element name is not one', () {
    // `<prefix>` is an ordinary tag, not the `<pre>` element, so only the tag
    // itself is hidden — its "content" is prose that keeps flowing.
    const String source = '<prefix>keep this';
    final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
      source,
      suppressRawHtml: true,
      sourceComplete: true,
    );
    final StringBuffer hidden = StringBuffer();
    for (final (int start, int end) range in regions.hiddenCodeUnitRanges) {
      hidden.write(source.substring(range.$1, range.$2));
    }
    expect(hidden.toString(), '<prefix>');
  });
}
