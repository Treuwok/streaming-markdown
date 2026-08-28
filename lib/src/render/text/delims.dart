part of '../view.dart';

extension _StreamingMarkdownDelimiterParsing on StreamingMarkdownRenderView {
  List<_FootnoteDefinition> _parseFootnoteDefinitions(String raw) {
    final List<String> lines = _normalizedRaw(raw).split('\n');
    if (lines.isEmpty) {
      return <_FootnoteDefinition>[];
    }

    final RegExp definitionLine = RegExp(r'^\s{0,3}\[\^([^\]]+)\]:\s*(.*)$');
    final List<_FootnoteDefinition> definitions = <_FootnoteDefinition>[];
    String? currentId;
    List<String> currentBody = <String>[];

    void flush() {
      final String? id = currentId;
      if (id == null) {
        return;
      }
      definitions.add(
        _FootnoteDefinition(id: id, body: currentBody.join('\n').trim()),
      );
    }

    for (final String line in lines) {
      final RegExpMatch? definition = definitionLine.firstMatch(line);
      if (definition != null) {
        flush();
        currentId = definition.group(1)!.trim();
        currentBody = <String>[definition.group(2)!.trim()];
        continue;
      }
      if (currentId == null) {
        continue;
      }
      if (line.trim().isEmpty) {
        currentBody.add('');
        continue;
      }
      currentBody.add(line.replaceFirst(RegExp(r'^\s{0,4}'), '').trimRight());
    }
    flush();

    return definitions;
  }

  _InlineImageMatch? _matchSingleInlineImage(String text) {
    final String trimmed = text.trim();
    final _InlineImageMatch? image = _matchInlineImageAt(trimmed, 0);
    if (image == null || image.end != trimmed.length) {
      return null;
    }
    return image;
  }
}

_DelimitedMatch? _matchDelimited(
  String text,
  int start,
  String delimiter, {
  bool allowUnclosedTail = false,
}) {
  if (!text.startsWith(delimiter, start)) {
    return null;
  }
  if (!_canOpenDelimiter(text, start, delimiter)) {
    return null;
  }
  final int endStart = text.indexOf(delimiter, start + delimiter.length);
  if (endStart == -1) {
    if (!allowUnclosedTail) {
      return null;
    }
    final String unclosedInner = text.substring(start + delimiter.length);
    if (unclosedInner.isEmpty) {
      return null;
    }
    return _DelimitedMatch(inner: unclosedInner, end: text.length);
  }
  final String inner = text.substring(start + delimiter.length, endStart);
  if (inner.isEmpty) {
    return null;
  }
  return _DelimitedMatch(inner: inner, end: endStart + delimiter.length);
}

bool _canOpenDelimiter(String text, int start, String delimiter) {
  if (!delimiter.startsWith('_')) {
    return true;
  }
  final int previousIndex = start - 1;
  final int nextIndex = start + delimiter.length;
  if (previousIndex < 0 || nextIndex >= text.length) {
    return true;
  }
  final int previous = text.codeUnitAt(previousIndex);
  final int next = text.codeUnitAt(nextIndex);
  return !_isAsciiAlphanumeric(previous) || !_isAsciiAlphanumeric(next);
}

bool _isAsciiAlphanumeric(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}

_InlineImageMatch? _matchInlineImageAt(String text, int start) {
  if (!text.startsWith('![', start)) {
    return null;
  }
  final int closeBracket = text.indexOf(']', start + 2);
  if (closeBracket == -1 || closeBracket + 1 >= text.length) {
    return null;
  }

  if (text[closeBracket + 1] != '(') {
    return null;
  }
  final int closeParen = text.indexOf(')', closeBracket + 2);
  if (closeParen == -1) {
    return null;
  }

  final String alt = text.substring(start + 2, closeBracket).trim();
  final String rawUrl = text.substring(closeBracket + 2, closeParen).trim();
  if (rawUrl.isEmpty) {
    return null;
  }

  final String url = _stripEnclosingAngles(
    rawUrl.split(RegExp(r'\s+')).first,
  );
  return _InlineImageMatch(alt: alt, url: url, end: closeParen + 1);
}

/// Scan for an inline link, reporting WHICH of the two "no match" cases
/// applies. See [_InlineLinkScanKind] for why that distinction has to leave
/// this function rather than being rediscovered outside it.
///
/// "Incomplete" means: the syntax so far can still become a link, and the
/// part that has not arrived is the part that would be HIDDEN once it does.
/// A destination is only ever a candidate while the source keeps growing, so
/// every incomplete arm below is conditioned on being at the end of what has
/// been received.
_InlineLinkScan _scanInlineLinkAt(
  String text,
  int start, {
  required Map<String, String> references,
  required bool sourceComplete,
}) {
  if (!text.startsWith('[', start)) {
    return const _InlineLinkScan.notALink();
  }

  final int closeBracket = text.indexOf(']', start + 1);
  if (closeBracket == -1) {
    // An unclosed label is only a pending link while more source may follow;
    // a newline ends the inline context, and so does the end of the source.
    // Nothing that could be a destination has appeared yet, so releasing it
    // shows the author's own text — holding it back would hide prose.
    return text.contains('\n', start) || sourceComplete
        ? const _InlineLinkScan.notALink()
        : const _InlineLinkScan.incompleteDestination();
  }

  final String label = text.substring(start + 1, closeBracket);
  if (label.isEmpty) {
    return const _InlineLinkScan.notALink();
  }

  if (closeBracket + 1 < text.length && text[closeBracket + 1] == '(') {
    final int closeParen = text.indexOf(')', closeBracket + 2);
    if (closeParen == -1) {
      // `[label](https://…` with no closing paren yet — the destination is
      // mid-flight. This is the leak: painting the source here shows the URL.
      return text.contains('\n', closeBracket)
          ? const _InlineLinkScan.notALink()
          : const _InlineLinkScan.incompleteDestination();
    }

    final String raw = text.substring(closeBracket + 2, closeParen).trim();
    if (raw.isEmpty) {
      return const _InlineLinkScan.notALink();
    }
    final String url = _stripEnclosingAngles(raw.split(RegExp(r'\s+')).first);
    return _InlineLinkScan.matched(
      _InlineLinkMatch(label: label, url: url, end: closeParen + 1),
    );
  }

  if (closeBracket + 1 < text.length && text[closeBracket + 1] == '[') {
    final int closeRef = text.indexOf(']', closeBracket + 2);
    if (closeRef == -1) {
      return text.contains('\n', closeBracket) || sourceComplete
          ? const _InlineLinkScan.notALink()
          : const _InlineLinkScan.incompleteDestination();
    }
    final String rawKey = text.substring(closeBracket + 2, closeRef).trim();
    final String key = _normalizeReferenceKey(
      rawKey.isEmpty ? label : rawKey,
    );
    final String? url = references[key];
    if (url == null) {
      // The definition may still arrive later in the stream. Until it does,
      // the label is a reference whose destination is unknown — not text.
      // Once the source is final it never will, and no destination text is
      // present to leak, so it settles as the prose it turned out to be.
      return sourceComplete
          ? const _InlineLinkScan.notALink()
          : const _InlineLinkScan.incompleteDestination();
    }
    return _InlineLinkScan.matched(
      _InlineLinkMatch(label: label, url: url, end: closeRef + 1),
    );
  }

  final String? shortcutUrl = references[_normalizeReferenceKey(label)];
  if (shortcutUrl != null) {
    return _InlineLinkScan.matched(
      _InlineLinkMatch(
        label: label,
        url: shortcutUrl,
        end: closeBracket + 1,
      ),
    );
  }

  // `[label]` with no definition anywhere. Shortcut references resolve late
  // in a stream, so while it is still growing this is a destination that has
  // not arrived; once it is final, it is prose.
  return sourceComplete
      ? const _InlineLinkScan.notALink()
      : const _InlineLinkScan.incompleteDestination();
}

/// What an angle-bracket construct turned out to be, and where it ends.
///
/// The inline scanner used to recognise exactly one `<…>` shape — an http(s)
/// autolink — and let everything else fall through to the plain-text path.
/// That fall-through is the same one the link scanner's `null` took: a raw tag
/// whose attribute value is still arriving gets written out verbatim, URL
/// included.
enum _AngleScanKind {
  /// Not angle syntax at all (`x < 5`, `<mailto:a@b>`, a lone `<`).
  notAngleSyntax,

  /// A complete `<http://…>` / `<https://…>`.
  autolink,

  /// An autolink whose closing `>` has not arrived.
  incompleteAutolink,

  /// A complete raw HTML tag or comment.
  html,

  /// A raw HTML tag or comment that has not closed yet.
  incompleteHtml,
}

class _AngleScan {
  const _AngleScan(this.kind, [this.end = -1]);

  final _AngleScanKind kind;

  /// Exclusive end offset; only meaningful for [_AngleScanKind.autolink] and
  /// [_AngleScanKind.html].
  final int end;
}

/// Classify the `<` at [start].
///
/// Unterminated HTML stays unterminated across newlines on purpose: a tag may
/// legitimately span lines, so a newline is not evidence that it settled as
/// text. An unterminated autolink is the opposite — CommonMark ends it at the
/// line break — so a newline settles it, matching the inline-link scanner.
_AngleScan _scanAngleAt(String text, int start) {
  if (start >= text.length || text.codeUnitAt(start) != 60 /* < */) {
    return const _AngleScan(_AngleScanKind.notAngleSyntax);
  }

  if (text.startsWith('<http://', start) ||
      text.startsWith('<https://', start)) {
    final int end = text.indexOf('>', start + 1);
    if (end != -1) {
      return _AngleScan(_AngleScanKind.autolink, end + 1);
    }
    return text.contains('\n', start)
        ? const _AngleScan(_AngleScanKind.notAngleSyntax)
        : const _AngleScan(_AngleScanKind.incompleteAutolink);
  }

  if (text.startsWith('<!--', start)) {
    final int end = text.indexOf('-->', start + 4);
    return end == -1
        ? const _AngleScan(_AngleScanKind.incompleteHtml)
        : _AngleScan(_AngleScanKind.html, end + 3);
  }

  final int nameStart = text.startsWith('</', start) ? start + 2 : start + 1;
  if (!_isHtmlTagNameStart(text, nameStart)) {
    return const _AngleScan(_AngleScanKind.notAngleSyntax);
  }

  int cursor = nameStart;
  while (cursor < text.length && _isHtmlTagNameChar(text.codeUnitAt(cursor))) {
    cursor += 1;
  }
  if (cursor < text.length && !_isHtmlTagNameTerminator(text.codeUnitAt(cursor))) {
    // `<mailto:a@b>` and friends: a name character sequence that does not end
    // the way a tag name ends is not a tag, so it keeps its old rendering.
    return const _AngleScan(_AngleScanKind.notAngleSyntax);
  }

  // Attribute values may contain `>`; only an unquoted one closes the tag.
  int? quote;
  while (cursor < text.length) {
    final int unit = text.codeUnitAt(cursor);
    if (quote != null) {
      if (unit == quote) {
        quote = null;
      }
    } else if (unit == 34 /* " */ || unit == 39 /* ' */) {
      quote = unit;
    } else if (unit == 62 /* > */) {
      return _AngleScan(_AngleScanKind.html, cursor + 1);
    }
    cursor += 1;
  }
  return const _AngleScan(_AngleScanKind.incompleteHtml);
}

bool _isHtmlTagNameStart(String text, int index) {
  if (index >= text.length) {
    return false;
  }
  final int unit = text.codeUnitAt(index);
  return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
}

bool _isHtmlTagNameChar(int unit) {
  return (unit >= 65 && unit <= 90) ||
      (unit >= 97 && unit <= 122) ||
      (unit >= 48 && unit <= 57) ||
      unit == 45 /* - */;
}

bool _isHtmlTagNameTerminator(int unit) {
  return unit == 62 /* > */ ||
      unit == 47 /* / */ ||
      unit == 32 ||
      unit == 9 ||
      unit == 10 ||
      unit == 13;
}
