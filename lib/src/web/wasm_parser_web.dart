// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import '../model/render_node.dart';
import '../model/utf8_code_unit_index.dart';

typedef _WasmStringParser = String? Function(String input);
typedef _WasmBlockNodeParser = String? Function(String input, int maxNodes);

class StreamingMarkdownWasmParser {
  static const String _assetBase =
      'assets/packages/animated_streaming_markdown/assets/wasm/';
  static const int _maxRenderNodes = 20000;

  static Future<bool>? _loadFuture;
  static js.JsObject? _module;
  static Object? _loadError;
  static _WasmStringParser? _parseBlocks;
  static _WasmStringParser? _parseInlines;
  static _WasmBlockNodeParser? _parseBlockNodes;

  static bool get isReady => _module != null;

  static Object? get loadError => _loadError;

  static Future<bool> ensureInitialized() {
    return _loadFuture ??= _load();
  }

  static String? parseBlocksJson(String markdown) {
    return _parseBlocks?.call(markdown);
  }

  static String? parseInlinesJson(String markdown) {
    return _parseInlines?.call(markdown);
  }

  static List<MarkdownRenderNode>? parseRenderNodes(String markdown) {
    final String? json = _parseBlockNodes?.call(markdown, _maxRenderNodes);
    if (json == null || json.isEmpty) {
      return null;
    }

    final Object? decoded = jsonDecode(json);
    if (decoded is! List<dynamic>) {
      return null;
    }

    // Same reason as the isolate's funnel: the wasm build is the same
    // tree-sitter, so its offsets are bytes and have to be translated here.
    final Utf8CodeUnitIndex index = Utf8CodeUnitIndex(markdown);
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> map) => _normalizeRenderNode(map, index))
        .where((MarkdownRenderNode node) => !_shouldDropNode(node))
        .toList(growable: false);
  }

  static Future<bool> _load() async {
    try {
      await _loadScriptOnce();
      final Object? factory = js.context['createStreamingMarkdownWasmModule'];
      if (factory == null) {
        throw StateError(
            'Streaming Markdown WASM module factory was not found');
      }

      _module = await _createModule();
      _parseBlocks = _wrapStringParser(
        'streaming_markdown_web_parse_blocks_json',
      );
      _parseInlines = _wrapStringParser(
        'streaming_markdown_web_parse_inlines_json',
      );
      _parseBlockNodes = _wrapBlockNodeParser(
        'streaming_markdown_web_block_nodes_json',
      );
      return true;
    } catch (error) {
      _loadError = error;
      _module = null;
      _parseBlocks = null;
      _parseInlines = null;
      _parseBlockNodes = null;
      return false;
    }
  }

  static Future<js.JsObject> _createModule() {
    final Completer<js.JsObject> completer = Completer<js.JsObject>();
    final js.JsObject promise = js.context.callMethod(
      'createStreamingMarkdownWasmModule',
      const <Object>[],
    ) as js.JsObject;
    promise.callMethod('then', <Object>[
      (Object module) {
        if (!completer.isCompleted) {
          completer.complete(module as js.JsObject);
        }
      },
      (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    ]);
    return completer.future;
  }

  static Future<void> _loadScriptOnce() {
    const String src = '${_assetBase}streaming_markdown_wasm.js';
    final html.Element? existing = html.document.querySelector(
      'script[data-streaming-markdown-wasm="true"]',
    );
    if (existing != null) {
      return Future<void>.value();
    }

    final Completer<void> completer = Completer<void>();
    final html.ScriptElement script = html.ScriptElement()
      ..src = src
      ..async = true
      ..defer = true
      ..dataset['streamingMarkdownWasm'] = 'true';
    script.onLoad.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    script.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Unable to load Streaming Markdown WASM asset: $src'),
        );
      }
    });
    html.document.head!.append(script);
    return completer.future;
  }

  static _WasmStringParser _wrapStringParser(String exportName) {
    final js.JsFunction fn = _cwrap(exportName, 'string', <String>['string']);
    return (String input) {
      return fn.apply(<Object>[input]) as String?;
    };
  }

  static _WasmBlockNodeParser _wrapBlockNodeParser(String exportName) {
    final js.JsFunction fn =
        _cwrap(exportName, 'string', <String>['string', 'number']);
    return (String input, int maxNodes) {
      return fn.apply(<Object>[input, maxNodes]) as String?;
    };
  }

  static js.JsFunction _cwrap(
    String exportName,
    String returnType,
    List<String> argTypes,
  ) {
    final js.JsObject? module = _module;
    if (module == null) {
      throw StateError('Streaming Markdown WASM module is not initialized');
    }
    return module.callMethod('cwrap', <Object>[
      exportName,
      returnType,
      argTypes,
    ]) as js.JsFunction;
  }

  static MarkdownRenderNode _normalizeRenderNode(
    Map<dynamic, dynamic> map,
    Utf8CodeUnitIndex index,
  ) {
    final MarkdownRenderNode node = MarkdownRenderNode.fromDynamicMap(map);
    return MarkdownRenderNode(
      type: node.type,
      depth: node.depth,
      startCodeUnit: index.codeUnitFor(node.startCodeUnit),
      endCodeUnit: index.codeUnitFor(node.endCodeUnit),
      startRow: node.startRow,
      endRow: node.endRow,
      raw: node.raw,
      content: _meaningfulContent(node.type, node.raw),
    );
  }

  static bool _shouldDropNode(MarkdownRenderNode node) {
    final String type = node.type;
    final String raw = node.raw;
    final String content = node.content;
    if (type == 'document' || type == 'section') {
      return true;
    }
    if (type == 'pipe_table_delimiter_row') {
      return false;
    }
    if (type.contains('marker') ||
        type.contains('delimiter') ||
        type == 'block_continuation') {
      return true;
    }
    if (_keepNodeWhenContentEmpty(type)) {
      return false;
    }
    if (raw.trim().isEmpty) {
      return content.isEmpty;
    }
    return content.isEmpty;
  }

  static bool _keepNodeWhenContentEmpty(String type) {
    switch (type) {
      case 'thematic_break':
      case 'fenced_code_block':
      case 'indented_code_block':
      case 'block_quote':
      case 'list':
      case 'list_item':
      case 'pipe_table':
      case 'pipe_table_delimiter_row':
      case 'table':
      case 'html_block':
      case 'front_matter':
        return true;
      default:
        return false;
    }
  }

  static String _meaningfulContent(String type, String raw) {
    String content = raw.replaceAll('\r', '').trim();
    switch (type) {
      case 'atx_heading':
      case 'setext_heading':
        content = content
            .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
            .replaceFirst(RegExp(r'\s*#{1,}\s*$'), '');
        break;
      case 'list_item':
        content = content.replaceFirst(
          RegExp(r'^\s*(?:[-+*]|\d+[.)])\s*(?:\[[ xX]\]\s*)?'),
          '',
        );
        break;
      case 'list':
        content = content
            .split('\n')
            .map(
              (String line) => line.replaceFirst(
                RegExp(r'^\s*(?:[-+*]|\d+[.)])\s*(?:\[[ xX]\]\s*)?'),
                '',
              ),
            )
            .where((String line) => line.trim().isNotEmpty)
            .join(' ');
        break;
      case 'block_quote':
        content = content
            .split('\n')
            .map((String line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
            .join(' ');
        break;
      case 'fenced_code_block':
        final List<String> lines = content.split('\n');
        if (lines.isNotEmpty &&
            RegExp(r'^\s*(```+|~~~+)').hasMatch(lines.first)) {
          lines.removeAt(0);
        }
        if (lines.isNotEmpty &&
            RegExp(r'^\s*(```+|~~~+)\s*$').hasMatch(lines.last)) {
          lines.removeLast();
        }
        content = lines.join(' ');
        break;
      case 'footnote_definition':
        content = content.replaceFirst(
          RegExp(r'^\s{0,3}\[\^[^\]]+\]:\s*'),
          '',
        );
        break;
      case 'link_reference_definition':
        content = content.replaceFirst(
          RegExp(r'^\s{0,3}\[[^\]]+\]:\s*'),
          '',
        );
        break;
      default:
        break;
    }
    content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (RegExp(r'^[`*_~#>\-\+\|\[\]\(\){}.!?:;=/\\\s]+$').hasMatch(content)) {
      return '';
    }
    return content;
  }
}
