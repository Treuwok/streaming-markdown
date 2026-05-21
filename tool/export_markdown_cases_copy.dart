import 'dart:io';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export markdown cases demo copy artifacts', () async {
    final Directory repoRoot = Directory.current;
    final File sourceFile = File(
      '${repoRoot.path}/example/lib/src/demos/markdown_cases_demo.dart',
    );
    final String source = await sourceFile.readAsString();
    final String markdown = _extractAllCasesMarkdown(source);

    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      markdown,
      backend: MarkdownSyncParserBackend.dart,
    );
    final String plain = StreamingMarkdownRenderView.debugFullPlainText(
      nodes: result.blocks,
    );
    final String html = StreamingMarkdownRenderView.debugFullHtml(
      nodes: result.blocks,
    );

    await File('${repoRoot.path}/plain.txt').writeAsString(plain);
    await File('${repoRoot.path}/raw.md').writeAsString(markdown);
    await _writeRichDocx(
      outputPath: '${repoRoot.path}/rich.docx',
      htmlBody: html,
    );

    expect(File('${repoRoot.path}/plain.txt').existsSync(), isTrue);
    expect(File('${repoRoot.path}/raw.md').existsSync(), isTrue);
    expect(File('${repoRoot.path}/rich.docx').existsSync(), isTrue);
  });
}

String _extractAllCasesMarkdown(String source) {
  final RegExp sectionPattern = RegExp(
    r'final List<_MarkdownCase> _regularMarkdownCases = <_MarkdownCase>\[(.*?)\n\];',
    dotAll: true,
  );
  final RegExpMatch sectionMatch = sectionPattern.firstMatch(source)!;
  final String section = sectionMatch.group(1)!;
  final RegExp markdownPattern = RegExp(r"markdown:\s*r'''(.*?)'''", dotAll: true);
  final List<String> markdownCases = markdownPattern
      .allMatches(section)
      .map((RegExpMatch match) => match.group(1)!.trim())
      .toList(growable: false);
  return '${markdownCases.join('\n\n---\n\n')}\n';
}

Future<void> _writeRichDocx({
  required String outputPath,
  required String htmlBody,
}) async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'streaming_markdown_docx_',
  );
  try {
    await Directory('${tempDir.path}/_rels').create(recursive: true);
    await Directory('${tempDir.path}/word/_rels').create(recursive: true);

    await File('${tempDir.path}/[Content_Types].xml').writeAsString(
      _contentTypesXml,
    );
    await File('${tempDir.path}/_rels/.rels').writeAsString(_rootRelsXml);
    await File('${tempDir.path}/word/document.xml').writeAsString(
      _documentXml,
    );
    await File('${tempDir.path}/word/_rels/document.xml.rels').writeAsString(
      _documentRelsXml,
    );
    await File('${tempDir.path}/word/afchunk.html').writeAsString(
      _htmlWrapper(htmlBody),
    );

    final File output = File(outputPath);
    if (output.existsSync()) {
      output.deleteSync();
    }

    final ProcessResult zipResult = await Process.run(
      'zip',
      <String>['-qr', output.path, '.'],
      workingDirectory: tempDir.path,
    );
    if (zipResult.exitCode != 0) {
      throw ProcessException(
        'zip',
        <String>['-qr', output.path, '.'],
        '${zipResult.stdout}\n${zipResult.stderr}',
        zipResult.exitCode,
      );
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

String _htmlWrapper(String body) {
  return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Markdown Cases Rich Copy</title>
    <style>
      body {
        margin: 0;
        color: #111827;
        font-family: Roboto, "Noto Sans", "Segoe UI", Arial, sans-serif;
        font-size: 16px;
        line-height: 1.55;
      }
      p, ul, ol, blockquote, pre, table, hr {
        margin: 0 0 16px 0;
      }
      h1, h2, h3, h4, h5, h6 {
        margin: 0 0 16px 0;
        color: #111827;
        font-weight: 700;
        line-height: 1.2;
      }
      h1 { font-size: 30px; }
      h2 { font-size: 24px; }
      h3 { font-size: 20px; }
      h4 { font-size: 18px; }
      h5 { font-size: 16px; }
      h6 { font-size: 14px; }
      ul, ol {
        padding-left: 24px;
      }
      li {
        margin: 0 0 6px 0;
      }
      li > ul, li > ol {
        margin-top: 6px;
        margin-bottom: 0;
      }
      code, pre {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      }
      code {
        background: #eff6ff;
        color: #1d4ed8;
        padding: 1px 4px;
        border-radius: 4px;
      }
      pre {
        background: #0f172a;
        color: #e2e8f0;
        padding: 12px 14px;
        border-radius: 8px;
        white-space: pre-wrap;
      }
      pre code {
        background: transparent;
        color: inherit;
        padding: 0;
        border-radius: 0;
      }
      blockquote {
        border-left: 3px solid #94a3b8;
        padding: 8px 0 8px 12px;
        color: #334155;
        background: #f8fafc;
      }
      table {
        border-collapse: collapse;
      }
      th, td {
        border: 1px solid #cbd5e1;
        padding: 8px 10px;
        text-align: left;
        vertical-align: top;
      }
      th {
        background: #f1f5f9;
      }
      a {
        color: #2563eb;
      }
      hr {
        border: 0;
        border-top: 1px solid #cbd5e1;
      }
    </style>
  </head>
  <body>
$body
  </body>
</html>
''';
}

const String _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="html" ContentType="text/html"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

const String _rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';

const String _documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:altChunk r:id="htmlChunk"/>
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';

const String _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="htmlChunk" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/aFChunk" Target="afchunk.html"/>
</Relationships>
''';
