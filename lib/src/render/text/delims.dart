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
    // Released once no more source can arrive — deliberately NOT on "a newline
    // already ended this line".
    //
    // That newline test was wrong three times for one reason: it asks about the
    // shape of the text THIS scanner was handed, and the renderer is handed a
    // different string. A block's raw slice carries the trailing newline its
    // rendered content does not; a list item's raw carries the continuation
    // break its joined content does not; a lone CR ends a line for one parser
    // and not the other. Each time the arm fired here and not there, and a
    // destination still in flight was released.
    //
    // Not depending on it at all is what closes that class. The cost is
    // over-holding a bracket in mid-stream prose, which the source ending then
    // releases; the cost of the other direction is a URL on screen.
    return sourceComplete
        ? const _InlineLinkScan.notALink()
        : const _InlineLinkScan.incompleteDestination();
  }

  final String label = text.substring(start + 1, closeBracket);
  if (label.isEmpty) {
    // `![](https://…` with no closing paren: the image scanner returns null
    // because `)` has not arrived, and rejecting the leftover on the empty
    // label alone let the whole URL fall through as plain text.
    //
    // Only for an IMAGE though. An empty alt is valid for a completed image,
    // but this parser rejects empty LINK labels outright — so without the `!`
    // check, ordinary prose like `see [](just text` was truncated at the `[`.
    final bool isImageCandidate = start > 0 && text.codeUnitAt(start - 1) == 33;
    final bool opensAnUnclosedDestination = closeBracket + 1 < text.length &&
        text[closeBracket + 1] == '(' &&
        text.indexOf(')', closeBracket + 2) == -1;
    return isImageCandidate && opensAnUnclosedDestination
        ? const _InlineLinkScan.incompleteDestination()
        : const _InlineLinkScan.notALink();
  }
  if (_hasUnmatchedBacktick(label)) {
    // `[foo `]` bar](https://…` — this `]` is inside a code span, so it is not
    // where the label ends. Any reading built on it is short, and painting the
    // difference paints the `](…)` that really follows.
    //
    // Only while something could follow it, though. With no `](` in reach at
    // all there is no destination for the short reading to expose, and holding
    // back prose like ``the bracket [x`y] is fine`` would truncate a finished
    // reply at the `[` — an over-hide that no leak test can see.
    if (!sourceComplete || text.contains('](', start)) {
      return const _InlineLinkScan.incompleteDestination();
    }
    return const _InlineLinkScan.notALink();
  }

  if (closeBracket + 1 < text.length && text[closeBracket + 1] == '(') {
    final int closeParen = text.indexOf(')', closeBracket + 2);
    if (closeParen == -1) {
      // `[label](https://…` with no closing paren yet — the destination is
      // mid-flight. This is the leak: painting the source here shows the URL.
      // Never released by a newline (see above), and not by the source ending
      // either — the destination is right there in the text.
      return const _InlineLinkScan.incompleteDestination();
    }

    final String raw = text.substring(closeBracket + 2, closeParen).trim();
    if (raw.isEmpty) {
      return const _InlineLinkScan.notALink();
    }
    if (raw.startsWith('<') && !raw.contains('>')) {
      // `[label](<https://…/a)secret>)` — the `)` that closed the scan is
      // inside an angle-bracketed destination, so the destination really runs
      // past it. Treating the short reading as a match would paint the rest of
      // the destination as ordinary text.
      return const _InlineLinkScan.incompleteDestination();
    }
    final String url = _stripEnclosingAngles(raw.split(RegExp(r'\s+')).first);
    return _InlineLinkScan.matched(
      _InlineLinkMatch(label: label, url: url, end: closeParen + 1),
    );
  }

  if (closeBracket + 1 < text.length && text[closeBracket + 1] == '[') {
    final int closeRef = text.indexOf(']', closeBracket + 2);
    if (closeRef == -1) {
      return sourceComplete
          ? const _InlineLinkScan.notALink()
          : const _InlineLinkScan.incompleteDestination();
    }
    final String rawKey = text.substring(closeBracket + 2, closeRef).trim();
    final String key = _normalizeReferenceKey(
      rawKey.isEmpty ? label : rawKey,
    );
    final String? url = references[key];
    if (url == null) {
      // A complete reference form with no definition yet. Nothing here is a
      // destination — the URL lives in the definition, which is a block of its
      // own — so this is the author's text and it shows. A definition arriving
      // later upgrades it to a link; that rebuild is expected, unlike the one
      // a late `](` would cause, which is why an OPEN candidate is held back
      // and a closed one is not.
      return const _InlineLinkScan.notALink();
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

  // `[label]` with no definition anywhere: a closed candidate carrying no
  // destination. Same reasoning as the explicit reference form above.
  return const _InlineLinkScan.notALink();
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
_AngleScan _scanAngleAt(
  String text,
  int start, {
  required bool sourceComplete,
}) {
  if (start >= text.length || text.codeUnitAt(start) != 60 /* < */) {
    return const _AngleScan(_AngleScanKind.notAngleSyntax);
  }

  if (text.startsWith('<http://', start) ||
      text.startsWith('<https://', start)) {
    final int end = text.indexOf('>', start + 1);
    if (end != -1) {
      return _AngleScan(_AngleScanKind.autolink, end + 1);
    }
    // Not withheld while it grows. An autolink's destination IS its visible
    // text, so there is nothing hidden to protect — and the cross-platform
    // parity contract records this case as url-visible, because the other
    // renderer shows it too. Holding it back would be the over-hiding failure
    // wearing the safety flag's clothes.
    return const _AngleScan(_AngleScanKind.notAngleSyntax);
  }

  // CommonMark's raw-HTML grammar is a closed set of six constructs, and all
  // six have to be recognised here or "do not render raw HTML" leaks the ones
  // that are missing — verbatim, which is worse than rendering them. The list
  // below is the spec's, not a guess at what looks HTML-ish; that distinction
  // is why it is safe to enumerate at all.
  for (final (String open, String close) delimiters in const <(String, String)>[
    ('<!--', '-->'), // comment
    ('<![CDATA[', ']]>'), // CDATA section
    ('<?', '?>'), // processing instruction
  ]) {
    if (!text.startsWith(delimiters.$1, start)) {
      continue;
    }
    final int end =
        text.indexOf(delimiters.$2, start + delimiters.$1.length);
    if (end != -1) {
      return _AngleScan(_AngleScanKind.html, end + delimiters.$2.length);
    }
    return _unterminatedAngle(text, start, sourceComplete: sourceComplete);
  }

  // Declaration (`<!DOCTYPE html>`). `<!` followed by a letter, closed by the
  // first `>`; CDATA is `<![`, already taken above, so the order matters.
  if (text.startsWith('<!', start) && _isHtmlTagNameStart(text, start + 2)) {
    final int end = text.indexOf('>', start + 2);
    if (end != -1) {
      return _AngleScan(_AngleScanKind.html, end + 1);
    }
    return _unterminatedAngle(text, start, sourceComplete: sourceComplete);
  }

  // Elements whose CONTENT is raw text, not markup: hiding only their tags
  // would paint a stylesheet or a script body as if it were the answer. The
  // hidden run therefore reaches the matching close tag.
  final int? literalEnd =
      _scanLiteralContentElementAt(text, start, sourceComplete: sourceComplete);
  if (literalEnd != null) {
    return literalEnd == -1
        ? _unterminatedAngle(text, start, sourceComplete: sourceComplete)
        : _AngleScan(_AngleScanKind.html, literalEnd);
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
  //
  // The characters between the name and that `>` must actually look like an
  // attribute list. Accepting anything was wrong in a way suppression makes
  // visible: `math <a + b> done` is prose the renderer has always shown, and
  // `+` cannot begin an attribute — deleting it is not "not rendering HTML",
  // it is deleting the author's sentence. This is the HTML open-tag grammar,
  // not a guess about what looks tag-like.
  int? quote;
  bool inAttributeValue = false;
  bool atAttributeStart = true;
  while (cursor < text.length) {
    final int unit = text.codeUnitAt(cursor);
    if (quote != null) {
      if (unit == quote) {
        quote = null;
        inAttributeValue = false;
        atAttributeStart = true;
      }
    } else if (unit == 34 /* " */ || unit == 39 /* ' */) {
      quote = unit;
    } else if (unit == 62 /* > */) {
      return _AngleScan(_AngleScanKind.html, cursor + 1);
    } else if (unit == 61 /* = */) {
      inAttributeValue = true;
      atAttributeStart = false;
    } else if (_isHtmlWhitespace(unit)) {
      inAttributeValue = false;
      atAttributeStart = true;
    } else if (unit == 47 /* / */) {
      inAttributeValue = false;
    } else if (atAttributeStart) {
      // Every attribute begins with a letter. The spec allows nearly any
      // character LATER in a name, so checking the whole name lets `<a + b>`
      // through — and suppression then deletes a sentence the renderer has
      // always shown. The first character is the part that separates an
      // attribute list from arbitrary prose.
      if (!_isAsciiLetter(unit)) {
        return const _AngleScan(_AngleScanKind.notAngleSyntax);
      }
      atAttributeStart = false;
    } else if (!inAttributeValue && !_isHtmlAttributeNameChar(unit)) {
      return const _AngleScan(_AngleScanKind.notAngleSyntax);
    }
    cursor += 1;
  }
  return _unterminatedAngle(text, start, sourceComplete: sourceComplete);
}

/// What an unterminated `<…` is once nothing more can arrive.
///
/// While the source grows, it is a tag whose attributes — and any destination
/// among them — may still be on their way, so it is held back.
///
/// Once the source is final, nothing is "still arriving" and the flag's whole
/// promise is vacuous: what is on the page is what the author wrote, exactly
/// as it would render with the flag off. So it is released.
///
/// The one exception is a comment opener. `<!--` is the only construct here
/// where the author said "do not show this", and a stream that stopped one
/// chunk before `-->` did not withdraw that.
///
/// An earlier version asked instead whether the text contained an `=`, as a
/// stand-in for "does it carry an attribute". That is a guess about an open
/// set, and it was wrong in both directions within one review round:
/// `Use T<U where x=1` was truncated as if it were a tag, and an unterminated
/// comment was released as if it were prose.
_AngleScan _unterminatedAngle(
  String text,
  int start, {
  required bool sourceComplete,
}) {
  if (!sourceComplete || text.startsWith('<!--', start)) {
    return const _AngleScan(_AngleScanKind.incompleteHtml);
  }
  return const _AngleScan(_AngleScanKind.notAngleSyntax);
}

/// End of a raw-text element (`<script>`, `<style>`, `<pre>`, `<textarea>`)
/// beginning at [start], `-1` if it has not closed yet, or null if there is no
/// such element here.
///
/// CommonMark gives these four elements raw-text content. Everything between
/// the tags is data, so the whole run is one hidden construct rather than two
/// tags with prose between them.
int? _scanLiteralContentElementAt(
  String text,
  int start, {
  required bool sourceComplete,
}) {
  for (final String name in const <String>[
    'script',
    'textarea',
    'style',
    'pre',
  ]) {
    final int nameEnd = start + 1 + name.length;
    if (!_startsWithIgnoreAsciiCase(text, '<$name', start)) {
      continue;
    }
    // `<pre>` and `<pre class=…>` are the element; `<prefix>` is not.
    if (nameEnd < text.length &&
        !_isHtmlTagNameTerminator(text.codeUnitAt(nameEnd))) {
      continue;
    }
    final int close = _indexOfIgnoreAsciiCase(text, '</$name', nameEnd);
    if (close == -1) {
      return -1;
    }
    final int end = text.indexOf('>', close);
    return end == -1 ? -1 : end + 1;
  }
  return null;
}

bool _startsWithIgnoreAsciiCase(String text, String needle, int start) {
  if (start + needle.length > text.length) {
    return false;
  }
  for (int i = 0; i < needle.length; i++) {
    if (_toLowerAscii(text.codeUnitAt(start + i)) !=
        _toLowerAscii(needle.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

int _indexOfIgnoreAsciiCase(String text, String needle, int from) {
  for (int i = from; i + needle.length <= text.length; i++) {
    if (_startsWithIgnoreAsciiCase(text, needle, i)) {
      return i;
    }
  }
  return -1;
}

int _toLowerAscii(int unit) =>
    (unit >= 65 && unit <= 90) ? unit + 32 : unit;

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

/// Whether [label] contains an odd number of backticks.
///
/// An odd count means a code span opened inside the label and has not closed,
/// so the `]` that ended this reading is code content, not the label's end.
bool _hasUnmatchedBacktick(String label) {
  int count = 0;
  for (int i = 0; i < label.length; i++) {
    if (label.codeUnitAt(i) == 96 /* ` */) {
      count += 1;
    }
  }
  return count.isOdd;
}

bool _isHtmlWhitespace(int unit) =>
    unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 12;

/// Characters an unquoted attribute name may contain, per the HTML spec:
/// anything except whitespace, `"`, `'`, `>`, `/`, `=` and controls.
bool _isHtmlAttributeNameChar(int unit) {
  if (unit <= 32 || unit == 127) {
    return false;
  }
  return unit != 34 && unit != 39 && unit != 62 && unit != 47 && unit != 61;
}

bool _isAsciiLetter(int unit) =>
    (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
