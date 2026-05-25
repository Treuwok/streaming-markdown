import 'dart:convert';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:animated_streaming_markdown/src/copy/clipboard_handler.dart';
import 'package:animated_streaming_markdown/src/copy/platform/clipboard_writer_interface.dart';
import 'package:animated_streaming_markdown/src/copy/platform/windows_clipboard_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _messiMarkdown = '''Hello! You are asking about the ultimate debate in football: **Messi vs. Ronaldo**! 🐐🐐

This is one of the biggest and most passionate debates in sports, and the answer really depends on what qualities you value most in a player. Both are absolute legends, but they excel in different areas.

Here is a quick breakdown to help you think about it:👑 

# Lionel Messi

* **Strengths**: Playmaking, dribbling, vision, passing, and overall creativity.
* **Style**: Often seen as the ultimate natural playmaker and genius. He controls the game and creates chances for others, while also scoring incredible goals.''';

const String _messiPlain = '''Hello! You are asking about the ultimate debate in football: Messi vs. Ronaldo! 🐐🐐

This is one of the biggest and most passionate debates in sports, and the answer really depends on what qualities you value most in a player. Both are absolute legends, but they excel in different areas.

Here is a quick breakdown to help you think about it:👑 

Lionel Messi

Strengths: Playmaking, dribbling, vision, passing, and overall creativity.
Style: Often seen as the ultimate natural playmaker and genius. He controls the game and creates chances for others, while also scoring incredible goals.''';

const String _messiRaw = _messiMarkdown;

const String _messiRichHtml = '<p>Hello! You are asking about the ultimate debate in football: <strong>Messi vs. Ronaldo</strong>! 🐐🐐</p>'
    '<p>This is one of the biggest and most passionate debates in sports, and the answer really depends on what qualities you value most in a player. Both are absolute legends, but they excel in different areas.</p>'
    '<p>Here is a quick breakdown to help you think about it:👑</p>'
    '<h1>Lionel Messi</h1>'
    '<ul>'
    '<li><strong>Strengths</strong>: Playmaking, dribbling, vision, passing, and overall creativity.</li>'
    '<li><strong>Style</strong>: Often seen as the ultimate natural playmaker and genius. He controls the game and creates chances for others, while also scoring incredible goals.</li>'
    '</ul>';

void main() {
  test('plain selection writes visible text only', () async {
    final _RecordingWriter writer = _RecordingWriter();
    final MarkdownClipboardHandler handler = MarkdownClipboardHandler(
      writer: writer,
    );

    await handler.copySelection(
      strategy: SelectionStrategy.plain,
      payload: const MarkdownClipboardPayload(
        plainText: 'Hello world',
        rawMarkdown: '**Hello** world',
      ),
    );

    expect(writer.plainWrites, <String>['Hello world']);
  });

  test('plain selection preserves block line breaks', () async {
    final _RecordingWriter writer = _RecordingWriter();
    final MarkdownClipboardHandler handler = MarkdownClipboardHandler(
      writer: writer,
    );

    await handler.copySelection(
      strategy: SelectionStrategy.plain,
      payload: const MarkdownClipboardPayload(
        plainText: 'Hello world\n\nSecond paragraph',
        rawMarkdown: '**Hello** world\n\nSecond paragraph',
      ),
    );

    expect(writer.plainWrites, <String>['Hello world\n\nSecond paragraph']);
  });

  test('raw selection returns original markdown source', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '**Hello** world',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText: 'Hello world',
      ),
      '**Hello** world',
    );
  });

  test('rich selection converts bold text to HTML', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '**Hello**',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugHtmlForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText: 'Hello',
      ),
      '<p><strong>Hello</strong></p>',
    );
  });

  test('partial selection across two blocks converts only selected content', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '**Hello** world\n\nSecond `code` block',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugHtmlForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText: 'Hello world\n\nSecond code',
      ),
      '<p><strong>Hello</strong> world</p><p>Second <code>code</code></p>',
    );
  });

  test('heading rich selection uses matching level', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '# Title',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugHtmlForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText: 'Title',
      ),
      '<h1>Title</h1>',
    );
  });

  test('code block rich selection emits fenced HTML structure', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '```dart\nfinal answer = 42;\n```',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugHtmlForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText: 'final answer = 42;',
      ),
      '<pre><code class="language-dart">final answer = 42;</code></pre>',
    );
  });

  test('rich selection preserves nested list structure', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '- Parent\n  - Child\n  - Child 2\n1. Ordered root\n   1. Ordered child',
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(
      StreamingMarkdownRenderView.debugHtmlForSelectedPlainText(
        nodes: result.blocks,
        selectedPlainText:
            'Parent\nChild\nChild 2\n\nOrdered root\nOrdered child',
      ),
      '<ul><li>Parent<ul><li>Child</li><li>Child 2</li></ul></li></ul>'
      '<ol><li>Ordered root<ol><li>Ordered child</li></ol></li></ol>',
    );
  });

  test('rich clipboard fallback silently writes plain text on failure', () async {
    final _RecordingWriter writer = _RecordingWriter(throwOnRich: true);
    final MarkdownClipboardHandler handler = MarkdownClipboardHandler(
      writer: writer,
    );

    await handler.copySelection(
      strategy: SelectionStrategy.rich,
      payload: const MarkdownClipboardPayload(
        plainText: 'Hello world',
        rawMarkdown: '**Hello** world',
        htmlText: '<p><strong>Hello</strong> world</p>',
      ),
    );

    expect(writer.plainWrites, <String>['Hello world']);
    expect(writer.richWrites, isEmpty);
  });

  test('windows CF_HTML formatter builds valid offsets', () {
    const String fragment = '<p><strong>Hello</strong></p>';
    final String cfHtml =
        WindowsClipboardHtmlFormatter.buildCfHtml(fragment);
    final RegExpMatch match = RegExp(
      r'StartHTML:(\d+)\r\nEndHTML:(\d+)\r\nStartFragment:(\d+)\r\nEndFragment:(\d+)',
    ).firstMatch(cfHtml)!;
    final int endHtml = int.parse(match.group(2)!);
    final int startFragment = int.parse(match.group(3)!);
    final int endFragment = int.parse(match.group(4)!);
    final List<int> bytes = utf8.encode(cfHtml);

    expect(bytes.length, endHtml);
    expect(
      utf8.decode(bytes.sublist(startFragment, endFragment)),
      fragment,
    );
    expect(cfHtml, contains('<!--StartFragment-->'));
    expect(cfHtml, contains('<!--EndFragment-->'));
  });

  testWidgets('copy after runtime strategy change uses the new strategy', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<SelectionStrategy> strategy =
        ValueNotifier<SelectionStrategy>(SelectionStrategy.raw);
    final _RecordingWriter writer = _RecordingWriter();
    MarkdownClipboardHandler.debugWriterFactory = () => writer;
    addTearDown(() {
      MarkdownClipboardHandler.debugWriterFactory = null;
      strategy.dispose();
    });

    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '**Hello** world',
      backend: MarkdownSyncParserBackend.dart,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<SelectionStrategy>(
          valueListenable: strategy,
          builder: (_, SelectionStrategy value, __) {
            return Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: result.blocks,
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionStrategy: value,
                tokenFadeInDuration: Duration.zero,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final BuildContext context = tester.element(
      find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('Hello world'),
          )
          .first,
    );

    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();
    expect(writer.plainWrites.last, '**Hello** world');

    strategy.value = SelectionStrategy.plain;
    await tester.pumpAndSettle();

    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();
    expect(writer.plainWrites.last, 'Hello world');
  });

  testWidgets('plain strategy preserves paragraph breaks in widget copy', (
    WidgetTester tester,
  ) async {
    final _RecordingWriter writer = _RecordingWriter();
    MarkdownClipboardHandler.debugWriterFactory = () => writer;
    addTearDown(() {
      MarkdownClipboardHandler.debugWriterFactory = null;
    });

    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '**Hello** world\n\nSecond paragraph',
      backend: MarkdownSyncParserBackend.dart,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: result.blocks,
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final BuildContext context = tester.element(
      find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('Hello world'),
          )
          .first,
    );

    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();
    expect(writer.plainWrites.last, 'Hello world\n\nSecond paragraph');
  });

  testWidgets('plain strategy copies Messi fixture exactly as plain text', (
    WidgetTester tester,
  ) async {
    final _RecordingWriter writer = _RecordingWriter();
    await _copyAllFromMarkdown(
      tester,
      markdown: _messiMarkdown,
      strategy: SelectionStrategy.plain,
      writer: writer,
      anchorText: 'Messi vs. Ronaldo',
    );

    expect(writer.plainWrites, <String>[_messiPlain]);
    expect(writer.richWrites, isEmpty);
  });

  testWidgets('raw strategy copies Messi fixture exactly as markdown source', (
    WidgetTester tester,
  ) async {
    final _RecordingWriter writer = _RecordingWriter();
    await _copyAllFromMarkdown(
      tester,
      markdown: _messiMarkdown,
      strategy: SelectionStrategy.raw,
      writer: writer,
      anchorText: 'Messi vs. Ronaldo',
    );

    expect(writer.plainWrites, <String>[_messiRaw]);
    expect(writer.richWrites, isEmpty);
  });

  testWidgets('rich strategy copies Messi fixture as rich HTML for docs', (
    WidgetTester tester,
  ) async {
    final _RecordingWriter writer = _RecordingWriter();
    await _copyAllFromMarkdown(
      tester,
      markdown: _messiMarkdown,
      strategy: SelectionStrategy.rich,
      writer: writer,
      anchorText: 'Messi vs. Ronaldo',
    );

    expect(writer.plainWrites, isEmpty);
    expect(
      writer.richWrites,
      <Map<String, String>>[
        <String, String>{
          'plain': _messiPlain,
          'html': _messiRichHtml,
        },
      ],
    );
  });
}

Future<void> _copyAllFromMarkdown(
  WidgetTester tester, {
  required String markdown,
  required SelectionStrategy strategy,
  required _RecordingWriter writer,
  required String anchorText,
}) async {
  final Size oldSize = tester.view.physicalSize;
  final double oldDpr = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 2200);
  addTearDown(() {
    tester.view.physicalSize = oldSize;
    tester.view.devicePixelRatio = oldDpr;
  });
  MarkdownClipboardHandler.debugWriterFactory = () => writer;
  addTearDown(() {
    MarkdownClipboardHandler.debugWriterFactory = null;
  });

  final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
    markdown,
    backend: MarkdownSyncParserBackend.dart,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StreamingMarkdownRenderView(
          nodes: result.blocks,
          padding: EdgeInsets.zero,
          enableTextSelection: true,
          selectionStrategy: strategy,
          tokenFadeInDuration: Duration.zero,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final SelectableRegionState regionState =
      tester.state<SelectableRegionState>(find.byType(SelectableRegion));
  regionState.selectAll(SelectionChangedCause.keyboard);
  await tester.pumpAndSettle();
  expect(
    find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText && widget.text.toPlainText().contains(anchorText),
    ),
    findsWidgets,
  );
  final BuildContext context = tester.element(
    find
        .byWidgetPredicate(
          (Widget widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains(anchorText),
        )
        .first,
  );
  Actions.invoke(context, CopySelectionTextIntent.copy);
  await tester.pump();
}

class _RecordingWriter implements MarkdownClipboardWriter {
  _RecordingWriter({this.throwOnRich = false});

  final bool throwOnRich;
  final List<String> plainWrites = <String>[];
  final List<Map<String, String>> richWrites = <Map<String, String>>[];

  @override
  Future<void> writePlainText(String text) async {
    plainWrites.add(text);
  }

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) async {
    if (throwOnRich) {
      throw PlatformException(code: 'unsupported');
    }
    richWrites.add(<String, String>{
      'plain': plainText,
      'html': htmlText,
    });
  }
}
