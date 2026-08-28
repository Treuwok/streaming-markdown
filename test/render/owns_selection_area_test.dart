/// `ownsSelectionArea` separates two concerns that used to share one flag.
///
/// `enableSelection` answers "does my text take part in selection". Whether
/// this widget also *owns* a selection region is a separate question, and only
/// the host can answer it: a chat transcript that wants one drag to run across
/// several messages already owns a `SelectionArea`, and a nested region breaks
/// the drag at this widget's boundary.
library;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool ownsSelectionArea}) => MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: AnimatedStreamingMarkdown(
            blocks: const [
              MarkdownRenderNode(
                type: 'paragraph',
                depth: 0,
                startByte: 0,
                endByte: 5,
                startRow: 0,
                endRow: 0,
                raw: 'hello',
                content: 'hello',
              ),
            ],
            enableSelection: true,
            ownsSelectionArea: ownsSelectionArea,
          ),
        ),
      ),
    );

void main() {
  testWidgets('owning the area keeps the historical nested region', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ownsSelectionArea: true));
    await tester.pump();

    expect(
      find.byType(SelectableRegion),
      findsNWidgets(2),
      reason: 'default behaviour is unchanged: the host area plus our own',
    );
  });

  testWidgets('disowning the area leaves the host region alone', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ownsSelectionArea: false));
    await tester.pump();

    expect(
      find.byType(SelectableRegion),
      findsOneWidget,
      reason:
          'the host owns selection; a nested region would break a drag that '
          'crosses this widget',
    );
  });
}
