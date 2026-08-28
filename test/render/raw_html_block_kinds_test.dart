/// Which HTML blocks carry prose, and which are raw data throughout.
///
/// Suppressing raw HTML means hiding the TAGS. That is right for a block whose
/// content is ordinary text with markup around it, and wrong for the four
/// elements CommonMark gives raw-text content — hiding only `<style>` and
/// `</style>` would paint the stylesheet as if it were the answer.
///
/// Where such an element ENDS is not decided here. The block parser that
/// produced the node already decided it, including the unclosed-at-end-of-
/// input case; a second answer computed in this layer disagreed with the first.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

String _hidden(String source) {
  final WithheldMarkdownRegions regions = analyzeWithheldMarkdownRegions(
    source,
    suppressRawHtml: true,
    sourceComplete: true,
  );
  return regions.hiddenCodeUnitRanges
      .map((range) => source.substring(range.$1, range.$2))
      .join();
}

void main() {
  group('raw-data blocks stay hidden whole', () {
    // Each of these was hidden entirely before block-level HTML was routed
    // through the inline scan, and must stay that way.
    const Map<String, String> cases = <String, String>{
      'style': '<style>\n.a { color: red }\n</style>',
      'script': '<script>\nvar secret = 1;\n</script>',
      // Unclosed at end of input: the block parser consumes it to the end, so
      // suppression has to as well. Releasing it as prose paints the payload.
      'unclosed script': '<script>private payload',
      'comment': '<!-- private note -->',
    };

    cases.forEach((String name, String source) {
      test('$name', () {
        expect(_hidden(source), source,
            reason: 'every character of it is raw data');
      });
    });
  });

  group('prose-bearing blocks keep their prose', () {
    test('a div keeps the answer between its tags', () {
      expect(_hidden('<div>\nImportant answer\n</div>'), '<div></div>');
    });

    test('a tag whose name merely starts with a raw-text name is ordinary', () {
      // `<prefix>` is not `<pre>`. Getting this wrong hides the sentence.
      expect(_hidden('<prefix>keep this'), '<prefix>');
    });
  });

  group('angle text that is not HTML is left alone', () {
    // The over-hiding direction: these are prose the renderer has always
    // shown, and deleting them is not "not rendering HTML".
    for (final String source in const <String>[
      '<!important> and the answer',
      'math <a + b> done',
      'use x < 5 today',
    ]) {
      test(source, () => expect(_hidden(source), isEmpty));
    }
  });
}
