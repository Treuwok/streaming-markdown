library;
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdownRenderNode _p(String s) => MarkdownRenderNode(type: 'paragraph', depth: 0,
    startCodeUnit: 0, endCodeUnit: s.length, startRow: 0, endRow: 0, raw: s, content: s);

// The app's configuration: token animation switched off entirely.
Widget _h(String s) => MaterialApp(home: Scaffold(body: Align(
    alignment: Alignment.topLeft, child: SizedBox(width: 300,
      child: AnimatedStreamingMarkdown(blocks: [_p(s)], sourceComplete: false,
        tokenStaggerDelay: Duration.zero, tokenAnimationDuration: Duration.zero)))));

// The height of the outer paragraph, which is the number of lines the reply
// occupies. `.first` is it: the tree is walked in pre-order, so the paragraph
// comes before the token widgets its placeholders host.
//
// Deliberately not "the RichText whose text starts with `Note:`". Once the
// text is split, the outer paragraph's plain text is object-replacement
// characters, that lookup finds an inner token widget instead, and a one-line
// box reads as an improvement.
double _renderedHeight(WidgetTester t) =>
    t.getSize(find.byType(RichText).first).height;

void main() {
  testWidgets('with the animation off, the streaming layout is the settled layout',
      (WidgetTester t) async {
    // Splitting text into one WidgetSpan per whitespace-delimited run is what
    // the reveal animation needs, and it costs line breaking: a WidgetSpan is
    // atomic to the line breaker, so the only breaks left are the whitespace
    // runs between spans. This clause has none, so it used to be pushed to a
    // line of its own until compaction replaced the spans with plain text —
    // the reply visibly re-flowed the moment it finished arriving.
    const String src =
        'Note: 這是一段很長的中文文字完全沒有空白所以整段會被當成單一 token 來處理喔';

    // The first frame, before compaction's post-frame callback has run. An
    // extra `pump()` here reads the compacted frame instead and the assertion
    // holds either way — it stops testing anything.
    await t.pumpWidget(_h(src));
    final double whileStreaming = _renderedHeight(t);

    await t.pumpAndSettle();
    final double afterSettling = _renderedHeight(t);

    expect(whileStreaming, afterSettling);
  });

  testWidgets('a link label stays one tap target with the animation off',
      (WidgetTester t) async {
    // A tap target needs the opposite of what the reveal needs. Split the
    // label into one detector per word and two things go: the space between
    // the words stops being a hit area, and accessibility services see several
    // actions instead of one carrying the whole label. Both need the pieces to
    // share an ancestor widget, which separate spans cannot have.
    final SemanticsHandle handle = t.ensureSemantics();
    String? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreamingMarkdownRenderView(
          nodes: <MarkdownRenderNode>[_p('see [the docs](https://x.test) now')],
          padding: EdgeInsets.zero,
          onLinkTap: (String url) => tapped = url,
        ),
      ),
    ));
    await t.pump();

    // The whole label, not one of its words: this is the finder that goes
    // looking for a single tap target.
    final Finder label = find.text('the docs');
    expect(label, findsOneWidget);
    expect(
      t.getSemantics(label).getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await t.tap(label);
    await t.pump();
    expect(tapped, 'https://x.test');
    handle.dispose();
  });

  testWidgets('debug token colours still render with the animation off',
      (WidgetTester t) async {
    // The debug colouring paints one box per token, so it needs the per-token
    // split for its own reason — unrelated to the animation being on.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreamingMarkdownRenderView(
          nodes: <MarkdownRenderNode>[_p('hello world debug')],
          padding: EdgeInsets.zero,
          debugTokenHighlight: true,
        ),
      ),
    ));
    await t.pump();

    final int boxes = find.byType(Container).evaluate().where((Element e) {
      return (e.widget as Container).decoration is BoxDecoration;
    }).length;
    expect(boxes, 3);
  });
}
