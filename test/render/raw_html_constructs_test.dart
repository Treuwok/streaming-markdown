/// Every construct the spec calls raw HTML, hidden when raw HTML is suppressed.
///
/// The class here is not "the ones somebody noticed". `example/assets/
/// github_gfm_spec.md` § Raw HTML defines an HTML tag as exactly six things —
/// open tag, closing tag, comment, processing instruction, declaration, CDATA
/// section — and that closed list is where these cases come from. The scanner
/// knew the first three, so the other three were painted verbatim WITH
/// suppression on (#2366), which is worse than rendering them.
///
/// The fixtures are the spec's own example inputs wherever it has one, so the
/// question "is this really raw HTML" is answered by the document that
/// defines the term rather than by this file.
///
/// The prose group is the other half and the reason this was split out of
/// #2343 rather than fixed there. A first attempt wrote the declaration
/// grammar from memory, dropped "uppercase" and "whitespace", and deleted a
/// sentence somebody had written. A rule that hides raw HTML by deleting
/// prose has not done the job.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

String _visible(String source) => analyzeWithheldMarkdownRegionsOfSource(
      source,
      suppressRawHtml: true,
      sourceComplete: true,
    ).visibleText;

void main() {
  group('the six constructs the spec calls raw HTML are all hidden', () {
    // Spec: "An HTML tag consists of an open tag, a closing tag, an HTML
    // comment, a processing instruction, a declaration, or a CDATA section."
    const Map<String, String> cases = <String, String>{
      'open tag': 'foo <a><bab><c2c>',
      'closing tag': 'foo </a></foo >',
      'comment': 'foo <!-- this is a comment -->',
      'processing instruction': 'foo <?php echo \$a; ?>',
      'declaration': 'foo <!ELEMENT br EMPTY>',
      'CDATA section': 'foo <![CDATA[>&<]]>',
    };

    for (final MapEntry<String, String> entry in cases.entries) {
      test(entry.key, () {
        expect(_visible(entry.value), 'foo ');
      });
    }

    test('a doctype is a declaration, which is how #2366 was reported', () {
      expect(_visible('<!DOCTYPE html>'), '');
    });
  });

  group('prose that only resembles a construct stays on screen', () {
    // Each of these fails exactly one clause of the spec's grammar. They are
    // here because over-hiding wears the safety flag's clothes: nothing looks
    // wrong on screen, the sentence is simply gone.
    const Map<String, String> cases = <String, String>{
      // Declaration names are UPPERCASE.
      'lowercase name': 'note <!important> here',
      // A declaration has whitespace after the name.
      'no whitespace after the name': 'note <!DOCTYPE> here',
      // A declaration has a name.
      'no name at all': 'x <!= y is nonsense',
      // `<?` is the processing-instruction opener; `< ?` is not.
      'space before the question mark': 'is a < ? b',
      // A tag name starts with a letter.
      'digits are not a tag name': 'compare <33> and <__>',
    };

    for (final MapEntry<String, String> entry in cases.entries) {
      test(entry.key, () {
        expect(_visible(entry.value), entry.value);
      });
    }
  });

  group('a construct whose closer never arrives', () {
    // The rule this follows already existed for comments, and the reason
    // given for it was never about comments: an opener that declares its own
    // contents unreadable was not withdrawn by a stream that stopped early.
    // Releasing an unclosed `<?php` is the case where that puts source code
    // on the screen.
    const Map<String, String> optedOut = <String, String>{
      'comment': 'foo <!-- secret',
      'processing instruction': 'foo <?php echo 1;',
      'CDATA section': 'foo <![CDATA[x',
      'declaration': 'foo <!DOCTYPE htm',
    };

    for (final MapEntry<String, String> entry in optedOut.entries) {
      test('${entry.key} stays hidden even once nothing more can arrive', () {
        expect(_visible(entry.value), 'foo ');
      });
    }

    test('an unclosed ordinary tag is still released, as it always was', () {
      const String source = 'foo <a href';
      expect(_visible(source), source);
    });
  });
}
