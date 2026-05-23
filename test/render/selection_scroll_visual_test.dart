import 'dart:io';
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _selectionColor = Color(0x4DFF00FF);
const String _testFontFamily = 'Roboto';
const Size _surfaceSize = Size(420, 100);
const int _fps = 60;
const int _assertFrameCount = 24;
const int _recordFrameCount = 60;

void main() {
  setUpAll(() async {
    await _loadTestFont();
  });

  testWidgets(
    'selected first line never drifts to lower visible lines while streaming and scrolling',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bool recordVideo =
          Platform.environment['RECORD_SELECTION_SCROLL_VIDEO'] == '1';
      final int frameCount =
          recordVideo ? _recordFrameCount : _assertFrameCount;

      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      const String selectedLine =
          'SelectedFirstLineStaysAnchored lower wrapped text in ';
      const String firstBlock =
          'SelectedFirstLineStaysAnchored lower wrapped text in this same markdown block must never become selected, even while content streams in and the scroll view is moving.';
      List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _renderNode(firstBlock, startByte: 0),
        _renderNode(
          'Second line must never become selected.',
          startByte: firstBlock.length + 2,
          startRow: 2,
        ),
      ];
      late StateSetter updateHost;
      final GlobalKey boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: _surfaceSize.width,
                  height: _surfaceSize.height,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                      updateHost = setState;
                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          StreamingMarkdownRenderView(
                            nodes: nodes,
                            padding: const EdgeInsets.all(8),
                            enableTextSelection: true,
                            selectionStrategy: SelectionStrategy.raw,
                            tokenArrivalDelay: Duration.zero,
                            tokenFadeInDuration: Duration.zero,
                            markdownTheme: const StreamingMarkdownThemeData(
                              selectionColor: _selectionColor,
                              paragraphTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: _testFontFamily,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 420),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final RenderParagraph paragraph =
          _renderParagraphContaining(tester, selectedLine);
      final TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        paragraph.localToGlobal(const Offset(390, 10)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 80));

      for (int frame = 0; frame < frameCount; frame++) {
        if (frame % 10 == 0) {
          updateHost(() {
            nodes = <MarkdownRenderNode>[
              _renderNode(firstBlock, startByte: 0),
              _renderNode(
                'Second line must never become selected.',
                startByte: firstBlock.length + 2,
                startRow: 2,
              ),
              for (int i = 0; i <= frame ~/ 10; i++)
                _renderNode(
                  'Streaming append block $i keeps layout moving.',
                  startByte: 80 + i * 48,
                  startRow: 4 + i * 2,
                ),
            ];
          });
        }

        if (scrollController.hasClients) {
          final double offset = (frame * 1.5).clamp(
            scrollController.position.minScrollExtent,
            scrollController.position.maxScrollExtent,
          );
          scrollController.jumpTo(offset);
        }
        await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

        _expectOnlySelectedLineHasNativeSelection(tester, selectedLine);
        _expectSourceVisualHighlightsOnly(tester, selectedLine);
        if (recordVideo) {
          final String frameName = frame.toString().padLeft(4, '0');
          await expectLater(
            find.byKey(boundaryKey),
            matchesGoldenFile(
              'artifacts/selection_scroll_60fps/frames/frame_$frameName.png',
            ),
          );
        }
      }
    },
  );

  testWidgets(
    'locked selection can be replaced by dragging another visible line',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bool recordVideo =
          Platform.environment['RECORD_SELECTION_REPLACE_VIDEO'] == '1';

      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      const String firstLine = 'FirstLockedLineStaysPut';
      const String firstBlock =
          'FirstLockedLineStaysPut while appended content and scroll changes try to move the viewport.';
      const String secondLine = 'SecondLineCanBeSelectedAfterLock';
      List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _renderNode(firstBlock, startByte: 0),
        _renderNode(
          secondLine,
          startByte: firstBlock.length + 2,
          startRow: 2,
        ),
      ];
      late StateSetter updateHost;
      final GlobalKey boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: _surfaceSize.width,
                  height: _surfaceSize.height,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                      updateHost = setState;
                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          StreamingMarkdownRenderView(
                            nodes: nodes,
                            padding: const EdgeInsets.all(8),
                            enableTextSelection: true,
                            selectionStrategy: SelectionStrategy.raw,
                            tokenArrivalDelay: Duration.zero,
                            tokenFadeInDuration: Duration.zero,
                            markdownTheme: const StreamingMarkdownThemeData(
                              selectionColor: _selectionColor,
                              paragraphTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: _testFontFamily,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 360),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      RenderParagraph paragraph = _renderParagraphContaining(tester, firstLine);
      TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0) + const Offset(2, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(paragraph, firstLine.length) + const Offset(4, 8),
      );
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      scrollController.jumpTo(10);
      updateHost(() {
        nodes = <MarkdownRenderNode>[
          _renderNode(firstBlock, startByte: 0),
          _renderNode(
            secondLine,
            startByte: firstBlock.length + 2,
            startRow: 2,
          ),
          _renderNode(
            'Streaming append keeps arriving while the old selection is locked.',
            startByte: firstBlock.length + secondLine.length + 4,
            startRow: 4,
          ),
        ];
      });
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      if (recordVideo) {
        for (int frame = 0; frame < 12; frame++) {
          await _recordFrame(
            tester,
            boundaryKey,
            'selection_replace_60fps/frames/frame_${frame.toString().padLeft(4, '0')}.png',
          );
          await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
        }
      }

      paragraph = _renderParagraphContaining(tester, secondLine);
      final Offset start =
          _textOffsetToPosition(paragraph, 0) + const Offset(2, 8);
      final Offset end = _textOffsetToPosition(paragraph, secondLine.length) +
          const Offset(4, 8);
      gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      for (int frame = 12; frame < _recordFrameCount; frame++) {
        final double t = (frame - 12) / (_recordFrameCount - 13);
        await gesture.moveTo(Offset.lerp(start, end, t)!);
        await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
        if (recordVideo) {
          await _recordFrame(
            tester,
            boundaryKey,
            'selection_replace_60fps/frames/frame_${frame.toString().padLeft(4, '0')}.png',
          );
        }
      }

      await gesture.up();
      await tester.pump();
      _expectLineHasNativeSelection(tester, secondLine);
      _expectSourceVisualDoesNotHighlight(tester, firstLine);
    },
  );
}

Future<void> _recordFrame(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) {
  return expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('artifacts/$path'),
  );
}

void _expectOnlySelectedLineHasNativeSelection(
  WidgetTester tester,
  String selectedLine,
) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    final String text = widget.text.toPlainText();
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    if (text.contains(selectedLine)) {
      continue;
    }
    expect(
      paragraph.selections,
      isEmpty,
      reason: 'native selection drifted to "$text"',
    );
  }
}

void _expectSourceVisualHighlightsOnly(
  WidgetTester tester,
  String selectedLine,
) {
  final StringBuffer highlighted = StringBuffer();
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    _collectHighlightedText(widget.text, highlighted);
  }

  final String actual = highlighted.toString();
  if (actual.isEmpty) {
    return;
  }
  expect(
    actual,
    selectedLine,
    reason: 'source fallback highlight moved away from the first line',
  );
}

void _expectSourceVisualDoesNotHighlight(
  WidgetTester tester,
  String text,
) {
  final StringBuffer highlighted = StringBuffer();
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    _collectHighlightedText(widget.text, highlighted);
  }
  expect(highlighted.toString(), isNot(contains(text)));
}

void _expectLineHasNativeSelection(WidgetTester tester, String selectedLine) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (!widget.text.toPlainText().contains(selectedLine)) {
      continue;
    }
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.selections,
      isNotEmpty,
      reason: 'new drag selection did not attach to "$selectedLine"',
    );
    return;
  }
  throw StateError('No RichText RenderParagraph contains "$selectedLine".');
}

void _collectHighlightedText(InlineSpan span, StringBuffer out) {
  if (span is TextSpan) {
    final TextStyle? style = span.style;
    if (style?.backgroundColor == _selectionColor && span.text != null) {
      out.write(span.text);
    }
    final List<InlineSpan>? children = span.children;
    if (children != null) {
      for (final InlineSpan child in children) {
        _collectHighlightedText(child, out);
      }
    }
  }
}

RenderParagraph _renderParagraphContaining(
  WidgetTester tester,
  String plainText,
) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (!widget.text.toPlainText().contains(plainText) ||
        _containsWidgetSpan(widget.text)) {
      continue;
    }
    return element.renderObject! as RenderParagraph;
  }
  throw StateError('No RichText RenderParagraph contains "$plainText".');
}

bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) {
    return true;
  }
  if (span is TextSpan) {
    final List<InlineSpan>? children = span.children;
    if (children != null) {
      return children.any(_containsWidgetSpan);
    }
  }
  return false;
}

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const Rect caret = Rect.fromLTWH(0, 0, 2, 20);
  final Offset localOffset = paragraph.getOffsetForCaret(
    TextPosition(offset: offset),
    caret,
  );
  return paragraph.localToGlobal(localOffset);
}

MarkdownRenderNode _renderNode(
  String raw, {
  int startByte = 0,
  int startRow = 0,
}) {
  return MarkdownRenderNode(
    type: 'paragraph',
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: startRow,
    endRow: startRow,
    raw: raw,
    content: raw,
  );
}

Future<void> _loadTestFont() async {
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final String regularPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Regular.ttf',
  );
  final String boldPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Bold.ttf',
  );
  await _loadFontFamily(_testFontFamily, <String>[regularPath, boldPath]);
}

Future<String> _findFlutterFont(String? flutterRoot, String fileName) async {
  final List<String> candidates = <String>[
    if (flutterRoot != null && flutterRoot.isNotEmpty)
      '$flutterRoot/bin/cache/artifacts/material_fonts/$fileName',
    '/Users/hider152/sdk/flutter/bin/cache/artifacts/material_fonts/$fileName',
  ];
  for (final String path in candidates) {
    final File candidate = File(path);
    if (await candidate.exists()) {
      return path;
    }
  }
  throw StateError('$fileName not found in Flutter SDK cache.');
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  for (final String path in paths) {
    final Uint8List bytes = await File(path).readAsBytes();
    loader.addFont(
      Future<ByteData>.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  }
  await loader.load();
}
