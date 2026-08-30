import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

String _visible(String source) => analyzeWithheldMarkdownRegionsOfSource(
      source,
      sourceComplete: true,
    ).visibleText;

void main() {
  // A backslash escape says "this punctuation is a character, not syntax". The
  // scanner used to ignore it entirely: the backslash reached the screen AND
  // the character it protected was still read as syntax — so `\*x\*` lost both
  // asterisks and gained two backslashes, which is the author's text altered
  // rather than merely mis-styled.
  //
  // Both directions are asserted per case, because fixing one alone looks like
  // progress and is not: dropping the backslash while still opening a link
  // leaves `\[a](b)` as a link with a tidier label.
  // Scope: escaped OPENERS. An escaped CLOSER inside a look-ahead-scanned
  // construct (`[foo \\] bar](url)`, `*foo \\* bar*`) is still mis-parsed — that
  // blindness lives in the construct scanners and predates this work. No test
  // here pins the current wrong output for those: writing one would make the
  // gap a contract and tell the next person not to fix it.
  group('a backslash escape makes the next character literal', () {
    const List<(String, String, String)> cases = <(String, String, String)>[
      (
        'a cancelled link stays text',
        r'\[not a link](https://x/y)',
        '[not a link](https://x/y)'
      ),
      ('a cancelled bracket keeps its brackets', r'a \[b] c', 'a [b] c'),
      (
        'cancelled emphasis keeps its asterisks',
        r'a \*not em\* b',
        'a *not em* b'
      ),
      (
        'cancelled code keeps its backticks',
        r'a \`not code\` b',
        'a `not code` b'
      ),
      ('an escaped backslash is one backslash', r'a \\ b', r'a \ b'),
    ];
    for (final (name, source, expected) in cases) {
      test(name, () => expect(_visible(source), expected));
    }
  });

  // The other half of the same rule, and the reason the scanner checks
  // membership rather than treating every backslash as an escape: CommonMark
  // escapes ASCII punctuation only.
  test('a backslash before a non-punctuation character is literal', () {
    expect(_visible(r'a \z b'), r'a \z b');
  });

  // The adjacent legal cases — one per construct the inline dispatch
  // recognises, enumerated from that dispatch rather than from the handful the
  // fix happened to have in mind. Adding a rule can OVER-apply it, and the
  // first version of this list did: it named `[`, `*` and backtick, missed
  // that `\\(`/`\\[` are this package's documented math delimiters, and the fix
  // stopped both forms from ever rendering as math. The list is derived from
  // the contract now, so a construct cannot be forgotten by being unmemorable.
  group('unescaped syntax still works', () {
    const List<(String, String, String)> cases = <(String, String, String)>[
      ('image', '![alt](https://x/i.png)', ''),
      ('link', '[a link](https://x/y)', 'a link'),
      ('autolink', 'a <https://x/y> b', 'a https://x/y b'),
      ('inline math', r'a \(x+1\) b', 'a x+1 b'),
      ('display math', r'a \[y=2\] b', 'a y=2 b'),
      ('dollar math', r'a $z$ b', 'a z b'),
      ('inline code', 'a `code` b', 'a code b'),
      ('strikethrough', 'a ~~gone~~ b', 'a gone b'),
      ('star emphasis', 'a *em* b', 'a em b'),
      ('underscore emphasis', 'a _em_ b', 'a em b'),
    ];
    for (final (name, source, expected) in cases) {
      test(name, () => expect(_visible(source), expected));
    }
  });
}
