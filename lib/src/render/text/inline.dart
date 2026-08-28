part of '../view.dart';

extension _StreamingMarkdownInlineParsing on _InlineParser {
  /// [offset] is where [text] starts inside the text handed to [scan], so a
  /// nested scan reports its findings in the caller's coordinates rather than
  /// its own.
  List<_InlineToken> _parseInlineTokens(
    String text, {
    _InlineStyle style = const _InlineStyle(),
    int depth = 0,
    int offset = 0,
  }) {
    if (text.isEmpty) {
      return <_InlineToken>[];
    }
    if (depth > 8) {
      return <_InlineToken>[
        _InlineToken.text(text: text, style: style, sourceMarkdown: text),
      ];
    }

    final List<_InlineToken> tokens = <_InlineToken>[];
    final StringBuffer plain = StringBuffer();

    void flushPlain() {
      if (plain.isEmpty) {
        return;
      }
      final String value = plain.toString();
      tokens.add(
          _InlineToken.text(text: value, style: style, sourceMarkdown: value));
      plain.clear();
    }

    int i = 0;
    while (i < text.length) {
      if (_withheldFrom != null) {
        // First thing in the loop, not halfway down it. A nested scan can set
        // this, and the branches above the old guard (`![`, `[`, `<`) then ran
        // anyway — so a second link AFTER the boundary got painted while the
        // text before it was dropped, and the reply came out in the wrong
        // order.
        return tokens;
      }

      if (text.startsWith('![', i)) {
        final _InlineImageMatch? image = _matchInlineImageAt(text, i);
        if (image != null) {
          flushPlain();
          tokens.add(
            _InlineToken.image(
              altText: image.alt,
              imageUrl: image.url,
              sourceMarkdown: text.substring(i, image.end),
            ),
          );
          i = image.end;
          continue;
        }
      }

      if (text.codeUnitAt(i) == 91) {
        final _FootnoteReferenceMatch? footnoteRef = _matchFootnoteReferenceAt(
          text,
          i,
        );
        // A footnote-shaped label immediately followed by `(` is a link
        // candidate, not a footnote: `[^note](https://…`. The footnote arm used
        // to consume `[^note]` and let the rest fall through to plain text,
        // which painted the destination this flag exists to hold back.
        final bool footnoteOpensADestination = footnoteRef != null &&
            footnoteRef.end < text.length &&
            text.codeUnitAt(footnoteRef.end) == 40 /* ( */;
        if (footnoteRef != null && !footnoteOpensADestination) {
          flushPlain();
          tokens.add(
            _InlineToken.footnote(
              footnoteReferenceId: footnoteRef.id,
              sourceMarkdown: text.substring(i, footnoteRef.end),
            ),
          );
          i = footnoteRef.end;
          continue;
        }

        final _InlineLinkScan scan = _scanInlineLinkAt(
          text,
          i,
          references: references,
          sourceComplete: sourceComplete,
        );
        if (scan.kind == _InlineLinkScanKind.incompleteDestination &&
            withholdIncompleteDestinations) {
          _withholdAt(offset + i);
          // Stop here rather than falling through to the plain-text path. That
          // fall-through is what paints a destination still in flight: the
          // source is written out verbatim, URL included. Everything already
          // tokenised stays; only the unresolved tail is held back, and the
          // next chunk re-tokenises from the same source.
          flushPlain();
          return tokens;
        }
        final _InlineLinkMatch? link = scan.match;
        if (link != null) {
          flushPlain();
          final List<_InlineToken> labelTokens = _parseInlineTokens(
            link.label,
            style: style,
            depth: depth + 1,
            offset: offset + i + 1,
          );
          if (labelTokens.isEmpty && _hiddenRanges.isEmpty) {
            tokens.add(
              _InlineToken.text(
                text: link.label,
                style: style,
                linkUrl: link.url,
                sourceMarkdown: text.substring(i, link.end),
              ),
            );
          } else if (labelTokens.isEmpty) {
            // The label produced no tokens because the nested scan SUPPRESSED
            // all of it — `[<a href="https://…">](https://ok)`. Rebuilding it
            // as raw text here paints the very `href` that scan refused to
            // draw.
            //
            // The whole construct painted nothing, so the whole construct is
            // what gets reported as hidden — not just the tag inside the
            // label. Reporting only the inner range left `[](https://outer)`
            // behind for anything that rebuilds text from the ranges, which
            // put the OUTER destination into a copied selection.
            _hiddenRanges
                .removeWhere((range) => range.$1 >= offset + i);
            _hiddenRanges.add((offset + i, offset + link.end));
          } else {
            for (final _InlineToken token in labelTokens) {
              if (token.isImage) {
                tokens.add(token);
              } else {
                tokens.add(
                  token.withLink(link.url,
                      sourceMarkdown: text.substring(i, link.end)),
                );
              }
            }
          }
          i = link.end;
          continue;
        }
      }

      if (text.codeUnitAt(i) == 60 /* < */) {
        final _AngleScan angle =
            _scanAngleAt(text, i, sourceComplete: sourceComplete);
        switch (angle.kind) {
          case _AngleScanKind.autolink:
            flushPlain();
            final String url = text.substring(i + 1, angle.end - 1);
            tokens.add(
              _InlineToken.text(
                text: url,
                style: style,
                linkUrl: url,
                sourceMarkdown: text.substring(i, angle.end),
              ),
            );
            i = angle.end;
            continue;
          case _AngleScanKind.incompleteHtml:
            if (suppressRawHtml) {
              // A tag whose attribute value is still arriving. Its `href` is
              // exactly the kind of destination that must not reach the screen
              // while it is in flight.
              _withholdAt(offset + i);
              flushPlain();
              return tokens;
            }
          case _AngleScanKind.html:
            if (suppressRawHtml) {
              flushPlain();
              _hiddenRanges.add((offset + i, offset + angle.end));
              i = angle.end;
              continue;
            }
          case _AngleScanKind.notAngleSyntax:
            break;
        }
      }

      final _LatexMatch? latex = _matchLatexAt(text, i);
      if (latex != null) {
        flushPlain();
        tokens.add(
          _InlineToken.latex(
            latexExpression: latex.expression,
            latexDisplay: latex.display,
            sourceMarkdown: latex.sourceMarkdown,
          ),
        );
        i = latex.end;
        continue;
      }

      final _DelimitedMatch? code = _matchDelimited(text, i, '`');
      if (code != null) {
        flushPlain();
        tokens.add(
          _InlineToken.text(
            text: code.inner,
            style: style.copyWith(code: true),
            sourceMarkdown: text.substring(i, code.end),
          ),
        );
        i = code.end;
        continue;
      }

      final _DelimitedMatch? boldItalicStar = _matchDelimited(
        text,
        i,
        '***',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (boldItalicStar != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            boldItalicStar.inner,
            style: style.copyWith(bold: true, italic: true),
            depth: depth + 1,
            offset: offset + i + 3,
          ),
        );
        i = boldItalicStar.end;
        continue;
      }

      final _DelimitedMatch? boldItalicUnderscore = _matchDelimited(
        text,
        i,
        '___',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (boldItalicUnderscore != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            boldItalicUnderscore.inner,
            style: style.copyWith(bold: true, italic: true),
            depth: depth + 1,
            offset: offset + i + 3,
          ),
        );
        i = boldItalicUnderscore.end;
        continue;
      }

      final _DelimitedMatch? bold = _matchAnyDelimited(
          text,
          i,
          const <String>[
            '**',
            '__',
          ],
          allowUnclosedDelimiters: allowUnclosedDelimiters);
      if (bold != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            bold.inner,
            style: style.copyWith(bold: true),
            depth: depth + 1,
            offset: offset + i + 2,
          ),
        );
        i = bold.end;
        continue;
      }

      final _DelimitedMatch? strike = _matchDelimited(text, i, '~~');
      if (strike != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            strike.inner,
            style: style.copyWith(strikethrough: true),
            depth: depth + 1,
            offset: offset + i + 2,
          ),
        );
        i = strike.end;
        continue;
      }

      final _DelimitedMatch? italicStar = _matchDelimited(
        text,
        i,
        '*',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (italicStar != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            italicStar.inner,
            style: style.copyWith(italic: true),
            depth: depth + 1,
            offset: offset + i + 1,
          ),
        );
        i = italicStar.end;
        continue;
      }

      final _DelimitedMatch? italicUnderscore = _matchDelimited(
        text,
        i,
        '_',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (italicUnderscore != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            italicUnderscore.inner,
            style: style.copyWith(italic: true),
            depth: depth + 1,
            offset: offset + i + 1,
          ),
        );
        i = italicUnderscore.end;
        continue;
      }

      plain.write(text[i]);
      i += 1;
    }

    flushPlain();
    return tokens;
  }
}

_LatexMatch? _matchLatexAt(String text, int start) {
  if (start > 0 && text.codeUnitAt(start - 1) == 92) {
    return null;
  }

  if (text.startsWith(r'\(', start)) {
    return _matchDelimitedLatex(
      text,
      start,
      open: r'\(',
      close: r'\)',
      display: false,
    );
  }
  if (text.startsWith(r'\[', start)) {
    return _matchDelimitedLatex(
      text,
      start,
      open: r'\[',
      close: r'\]',
      display: true,
    );
  }
  if (text.startsWith(r'$$', start)) {
    return _matchDelimitedLatex(
      text,
      start,
      open: r'$$',
      close: r'$$',
      display: true,
    );
  }
  if (text.codeUnitAt(start) == 36) {
    if (start + 1 >= text.length || text.codeUnitAt(start + 1) == 36) {
      return null;
    }
    final _LatexMatch? match = _matchDelimitedLatex(
      text,
      start,
      open: r'$',
      close: r'$',
      display: false,
    );
    if (match == null) {
      return null;
    }
    return match;
  }
  return null;
}

_LatexMatch? _matchDelimitedLatex(
  String text,
  int start, {
  required String open,
  required String close,
  required bool display,
}) {
  if (!text.startsWith(open, start)) {
    return null;
  }
  final int contentStart = start + open.length;
  final int closeStart = _findUnescapedDelimiter(text, close, contentStart);
  if (closeStart == -1 || closeStart == contentStart) {
    return null;
  }
  final int end = closeStart + close.length;
  final String expression = text.substring(contentStart, closeStart).trim();
  if (expression.isEmpty) {
    return null;
  }
  return _LatexMatch(
    expression: expression,
    sourceMarkdown: text.substring(start, end),
    display: display,
    end: end,
  );
}

int _findUnescapedDelimiter(String text, String delimiter, int start) {
  int index = start;
  while (index < text.length) {
    final int found = text.indexOf(delimiter, index);
    if (found == -1) {
      return -1;
    }
    if (!_isEscaped(text, found)) {
      return found;
    }
    index = found + delimiter.length;
  }
  return -1;
}

bool _isEscaped(String text, int index) {
  int slashCount = 0;
  int cursor = index - 1;
  while (cursor >= 0 && text.codeUnitAt(cursor) == 92) {
    slashCount += 1;
    cursor -= 1;
  }
  return slashCount.isOdd;
}

_DelimitedMatch? _matchAnyDelimited(
  String text,
  int start,
  List<String> delimiters, {
  required bool allowUnclosedDelimiters,
}) {
  for (final String delimiter in delimiters) {
    final _DelimitedMatch? match = _matchDelimited(
      text,
      start,
      delimiter,
      allowUnclosedTail: allowUnclosedDelimiters,
    );
    if (match != null) {
      return match;
    }
  }
  return null;
}

_FootnoteReferenceMatch? _matchFootnoteReferenceAt(String text, int start) {
  final Match? match = RegExp(r'\[\^([^\]]+)\]').matchAsPrefix(text, start);
  if (match is! RegExpMatch) {
    return null;
  }
  return _FootnoteReferenceMatch(id: match.group(1)!, end: match.end);
}
