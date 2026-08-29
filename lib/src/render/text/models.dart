part of '../view.dart';

class _ParsedList {
  const _ParsedList({required this.items});

  final List<_ParsedListItem> items;
}

class _ParsedListItem {
  const _ParsedListItem({
    required this.level,
    required this.ordered,
    required this.order,
    required this.taskState,
    required this.body,
    required this.stableKey,
  });

  /// The item's painted text with its origins. [text] is this, flattened.
  final _SourceSlice body;

  String get text => body.text;

  final int level;
  final bool ordered;
  final int order;
  final bool? taskState;
  final String stableKey;
}

/// A table's cells with their origins.
///
/// The cells are slices, not strings: the split that produced a cell already
/// knew where it came from, so nothing downstream has to search the block for
/// a cell's text to learn where it was. [headers] and [rows] are that same
/// data flattened, which is all most consumers want.
class _ParsedTable {
  const _ParsedTable({required this.headerCells, required this.rowCells});

  final List<_SourceSlice> headerCells;
  final List<List<_SourceSlice>> rowCells;

  List<String> get headers =>
      headerCells.map((_SourceSlice cell) => cell.text).toList(growable: false);

  List<List<String>> get rows => rowCells
      .map((List<_SourceSlice> row) =>
          row.map((_SourceSlice cell) => cell.text).toList(growable: false))
      .toList(growable: false);

  /// Every cell in the order the table widget paints them.
  Iterable<_SourceSlice> get cellsInRenderOrder sync* {
    yield* headerCells;
    for (final List<_SourceSlice> row in rowCells) {
      yield* row;
    }
  }
}

class _CalloutData {
  const _CalloutData({
    required this.kind,
    required this.titleSlice,
    required this.bodySlice,
  });

  final String kind;

  /// The title as painted. A DEFAULT title (`Note`) is generated and reports
  /// the marker it replaced; a CUSTOM one is a real slice of the first line.
  final _SourceSlice titleSlice;

  /// The body with its origins.
  final _SourceSlice bodySlice;

  String get title => titleSlice.text;
  String get body => bodySlice.text;
}

class _DelimitedMatch {
  const _DelimitedMatch({required this.inner, required this.end});

  final String inner;
  final int end;
}

class _InlineImageMatch {
  const _InlineImageMatch({
    required this.alt,
    required this.url,
    required this.end,
  });

  final String alt;
  final String url;
  final int end;
}

/// Why `_scanInlineLinkAt` cannot answer with a nullable match.
///
/// A null conflates two opposite facts: "this is not a link, paint the source
/// as written" and "this IS a link whose destination has not arrived yet, so
/// painting the source as written puts the destination on screen". Streaming
/// makes the second one routine — every transport chunk can land mid-URL — and
/// the caller has no way to tell them apart, so it paints both.
///
/// Splitting the return type is what makes the distinction available at all.
/// The scanner already knows which branch it took; it was simply discarding
/// that on the way out.
enum _InlineLinkScanKind { matched, notALink, incompleteDestination }

class _InlineLinkScan {
  const _InlineLinkScan.matched(_InlineLinkMatch this.match)
      : kind = _InlineLinkScanKind.matched;
  const _InlineLinkScan.notALink()
      : kind = _InlineLinkScanKind.notALink,
        match = null;
  const _InlineLinkScan.incompleteDestination()
      : kind = _InlineLinkScanKind.incompleteDestination,
        match = null;

  final _InlineLinkScanKind kind;
  final _InlineLinkMatch? match;
}

class _InlineLinkMatch {
  const _InlineLinkMatch({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
}

class _FootnoteReferenceMatch {
  const _FootnoteReferenceMatch({required this.id, required this.end});

  final String id;
  final int end;
}

class _LatexMatch {
  const _LatexMatch({
    required this.expression,
    required this.sourceMarkdown,
    required this.display,
    required this.end,
  });

  final String expression;
  final String sourceMarkdown;
  final bool display;
  final int end;
}

class _FootnoteDefinition {
  const _FootnoteDefinition({
    required this.id,
    required this.bodySlice,
    required this.sourceStart,
  });

  final String id;

  /// The body with its origins. [body] is this, flattened.
  final _SourceSlice bodySlice;

  /// Where `[^id]:` starts. The label the renderer paints is generated text,
  /// so it reports the construct it stands for rather than the body it sits
  /// in front of — a cursor consuming the label must not already be inside
  /// the body.
  final int sourceStart;

  String get body => bodySlice.text;
}

int? _footnoteNumberForId(Map<String, int> footnoteNumbers, String id) {
  return footnoteNumbers[_normalizeFootnoteKey(id)];
}

String _normalizeFootnoteKey(String key) {
  return key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Reference keys and footnote keys normalise identically.
String _normalizeReferenceKey(String key) {
  return _normalizeFootnoteKey(key);
}

/// `<https://x>` -> `https://x`. Pure string work, shared by the grammar and
/// by the reference-definition extractor, so it lives at library level rather
/// than on either consumer.
String _stripEnclosingAngles(String value) {
  final String trimmed = value.trim();
  if (trimmed.startsWith('<') && trimmed.endsWith('>') && trimmed.length > 2) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
    );
  }
}

class _InlineToken {
  const _InlineToken.text({
    required this.text,
    required this.style,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
    this.linkUrl,
  })  : altText = '',
        imageUrl = null,
        footnoteReferenceId = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.image({
    required this.altText,
    required this.imageUrl,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        footnoteReferenceId = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.footnote({
    required this.footnoteReferenceId,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null,
        latexExpression = null,
        latexDisplay = false;

  const _InlineToken.latex({
    required this.latexExpression,
    required this.latexDisplay,
    required this.sourceMarkdown,
    required this.visibleSourceStart,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null,
        footnoteReferenceId = null;

  final String text;
  final _InlineStyle style;
  final String? linkUrl;
  final String altText;
  final String? imageUrl;
  final String? footnoteReferenceId;
  final String? latexExpression;
  final bool latexDisplay;
  final String sourceMarkdown;

  /// Where this token's visible [text] begins in the source handed to `scan`.
  ///
  /// Absolute, in the same code-unit coordinates as the reported hidden
  /// ranges — a nested scan is given its caller's offset, so a link label
  /// reports where the LABEL sits, not where the construct does.
  ///
  /// Anything mapping painted characters back to source needs this. Without
  /// it, a caller can only re-derive the mapping by parsing the text a second
  /// time with a second parser and aligning the two results heuristically,
  /// which is what mobile did before #2360 — and the two parsers did not have
  /// to agree.
  final int visibleSourceStart;

  /// Whether [text] is a verbatim slice of the source at [visibleSourceStart].
  ///
  /// True for ordinary text runs, so character `k` of [text] came from source
  /// offset `visibleSourceStart + k`. False where what is painted is not a
  /// slice of the source — an image's alt text, a footnote's assigned number,
  /// a rendered formula — and every character of those maps to the
  /// construct's start.
  bool get isVerbatimSlice => !isImage && !isFootnoteReference && !isLatex;

  bool get isImage => imageUrl != null;
  bool get isFootnoteReference => footnoteReferenceId != null;
  bool get isLatex => latexExpression != null;

  _InlineToken withLink(String url, {required String sourceMarkdown}) {
    if (isImage || isFootnoteReference || isLatex) {
      return this;
    }
    return _InlineToken.text(
      text: text,
      style: style,
      linkUrl: url,
      sourceMarkdown: sourceMarkdown,
      visibleSourceStart: visibleSourceStart,
    );
  }
}

/// One separately-rendered run of a block, and how it is drawn.
class _ProjectedPiece {
  const _ProjectedPiece(
    this.slice, {
    this.literal = false,
    this.continuesLine = false,
    this.emptyTokenFallback = true,
  });

  final _SourceSlice slice;

  /// Whether the widget drawing this run falls back to the surviving source
  /// when suppression leaves no tokens. `_buildInlineMarkdown` does — that is
  /// why `**<b></b>**` still shows its asterisks. A footnote definition line
  /// appends its tokens directly and so paints nothing at all in that case.
  final bool emptyTokenFallback;

  /// Drawn by a plain widget rather than inline-parsed — a callout's title, a
  /// footnote definition's label. Its own delimiters are on the screen, so
  /// scanning it would report `note` where `*note*` is painted, and could pair
  /// delimiters across the boundary with the run beside it.
  final bool literal;

  /// Whether this run sits on the SAME line as the one before it. A footnote
  /// definition's label and its body share a line; a callout's title is a row
  /// of its own above the body.
  final bool continuesLine;
}

/// The text a block paints, in the pieces the renderer paints them as.
class _BlockProjection {
  const _BlockProjection(this.pieces, {this.verbatim = false});

  /// One per separately-rendered run: a list item, a table cell, a definition.
  final List<_ProjectedPiece> pieces;

  /// Whether [pieces] are shown as-is rather than inline-parsed. Code blocks
  /// are, and their edge whitespace is content rather than block syntax.
  final bool verbatim;
}

/// The one decision about a block: which shape it renders as, and — for the
/// shapes that show text — exactly which slices that shape paints.
///
/// This exists because it used to be TWO decisions. A switch built the widget
/// and a second switch beside it said what the widget would paint. They were
/// written to agree, they carried the same case labels, and they still drifted
/// on almost every block type: a fence's header showed `dart` but was reported
/// as `dart linenums`; a loose table's rows ended at a plain line on screen but
/// not in the report; an empty fence painted nothing and reported its language.
/// Every one of those was found by a reviewer rather than by a test, because
/// two copies that agree today are indistinguishable from two copies that
/// agree forever.
///
/// Now the renderer is HANDED this. It cannot paint text that is not in
/// [projection], because it has nowhere else to get the text from.
sealed class _BlockPlan {
  const _BlockPlan();

  /// What this block puts on the screen, with origins.
  _BlockProjection get projection => const _BlockProjection(<_ProjectedPiece>[]);
}

/// Paints nothing at all: a delimiter row, an empty block, suppressed raw data.
class _NothingPlan extends _BlockPlan {
  const _NothingPlan();
}

/// A horizontal rule. No text.
class _ThematicBreakPlan extends _BlockPlan {
  const _ThematicBreakPlan();
}

class _HeadingPlan extends _BlockPlan {
  const _HeadingPlan(this.text, this.level);

  final _SourceSlice text;
  final int level;

  @override
  _BlockProjection get projection =>
      _BlockProjection(<_ProjectedPiece>[_ProjectedPiece(text)]);
}

class _ParagraphPlan extends _BlockPlan {
  const _ParagraphPlan(this.text);

  /// Already folded: the renderer replaces a paragraph's line breaks with
  /// spaces before it paints, so this is the string that reaches the screen.
  final _SourceSlice text;

  @override
  _BlockProjection get projection =>
      _BlockProjection(<_ProjectedPiece>[_ProjectedPiece(text)]);
}

/// A paragraph that is one display formula.
///
/// The screen shows rendered glyphs, so there is no span of the source to map
/// character by character — the expression stands in for them, anchored at the
/// construct that produced it. That is the same answer an INLINE formula
/// already gives (`_paintedTextOf` returns its expression); a standalone one
/// disagreeing with it would be a difference with no reason behind it.
class _DisplayLatexPlan extends _BlockPlan {
  const _DisplayLatexPlan(this.latex, this.sourceStart);

  final _LatexMatch latex;
  final int sourceStart;

  @override
  _BlockProjection get projection => _BlockProjection(<_ProjectedPiece>[
        _ProjectedPiece(
          _SourceSlice.generated(latex.expression, sourceStart),
          literal: true,
        ),
      ]);
}

/// A paragraph that is one image. Nothing textual is painted.
class _ImagePlan extends _BlockPlan {
  const _ImagePlan(this.image);

  final _InlineImageMatch image;
}

class _ListPlan extends _BlockPlan {
  const _ListPlan(this.list);

  final _ParsedList list;

  @override
  _BlockProjection get projection => _BlockProjection(list.items
      .map((_ParsedListItem item) => _ProjectedPiece(item.body))
      .toList(growable: false));
}

class _QuotePlan extends _BlockPlan {
  const _QuotePlan(this.body, this.callout);

  /// The quote's text when it is not a callout; the callout's body when it is.
  final _SourceSlice body;
  final _CalloutData? callout;

  @override
  _BlockProjection get projection {
    final _CalloutData? data = callout;
    if (data == null) {
      return _BlockProjection(<_ProjectedPiece>[_ProjectedPiece(body)]);
    }
    return _BlockProjection(<_ProjectedPiece>[
      // A plain `Text`, so a custom title like `**Danger**` shows its asterisks.
      _ProjectedPiece(data.titleSlice, literal: true),
      _ProjectedPiece(body),
    ]);
  }
}

class _CodePlan extends _BlockPlan {
  const _CodePlan({
    required this.body,
    required this.language,
    required this.showCopyButton,
  });

  final _SourceSlice body;

  /// The header token, or null when the header shows no text. For a fence it
  /// is the span the language was read from — an info string can carry more
  /// (` ```dart linenums `) and only the language reaches the screen.
  final _SourceSlice? language;

  final bool showCopyButton;

  bool get showHeader => language != null || showCopyButton;

  @override
  _BlockProjection get projection => _BlockProjection(
        <_ProjectedPiece>[
          if (language != null) _ProjectedPiece(language!, literal: true),
          _ProjectedPiece(body),
        ],
        verbatim: true,
      );
}

class _TablePlan extends _BlockPlan {
  const _TablePlan(this.table, this.source, {required this.hasRenderableCell});

  final _ParsedTable table;
  final _SourceSlice source;

  /// A table with nothing paintable in it still renders an empty frame, which
  /// holds the layout steady while the rest of it streams in. The frame is on
  /// the screen; no text is.
  final bool hasRenderableCell;

  @override
  _BlockProjection get projection => _BlockProjection(hasRenderableCell
      ? table.cellsInRenderOrder
          .where((_SourceSlice cell) => cell.text.isNotEmpty)
          .map(_ProjectedPiece.new)
          .toList(growable: false)
      : const <_ProjectedPiece>[]);
}

/// Front matter and any definition-shaped block with no definitions in it.
/// Its line breaks survive to the screen — no paragraph folding.
class _MetadataPlan extends _BlockPlan {
  const _MetadataPlan(this.text);

  final _SourceSlice text;

  @override
  _BlockProjection get projection =>
      _BlockProjection(<_ProjectedPiece>[_ProjectedPiece(text)]);
}

class _DefinitionPlan extends _BlockPlan {
  const _DefinitionPlan(this.definitions);

  final List<_FootnoteDefinition> definitions;

  @override
  _BlockProjection get projection {
    final List<_ProjectedPiece> pieces = <_ProjectedPiece>[];
    for (final _FootnoteDefinition definition in definitions) {
      pieces.add(_ProjectedPiece(
        // Generated: the painted label is `id: `, which is not a span of the
        // source. It reports the construct's start, so consuming it does not
        // put a cursor inside a body that has not been shown yet.
        _SourceSlice.generated('${definition.id}: ', definition.sourceStart),
        literal: true,
      ));
      pieces.add(_ProjectedPiece(
        definition.bodySlice,
        continuesLine: true,
        // This line appends its tokens directly instead of going through
        // `_buildInlineMarkdown`, so it has no surviving-source fallback.
        emptyTokenFallback: false,
      ));
    }
    return _BlockProjection(pieces);
  }
}

/// Raw HTML rendered as a card, which happens only with `suppressRawHtml`
/// off.
///
/// ⚠️ KNOWN GAP, and it is silent: the card parses the HTML and paints its DOM
/// text, and this reports none of it. Describing that text means deriving
/// "what does this HTML show" a third time, next to the card's own renderer —
/// the shape this whole file exists to stop — so it is not attempted here.
///
/// There used to be an `approximate` flag set at this spot. Nothing ever read
/// it: it reached no consumer and was absent from the public report, so it
/// documented a warning that was never delivered. A flag nobody reads is a
/// claim, not a safeguard, and it made this gap look handled. Removed.
///
/// Every caller in this repo passes `suppressRawHtml: true`, so nothing hits
/// this today.
class _HtmlCardPlan extends _BlockPlan {
  const _HtmlCardPlan(this.html);

  final String html;
}
