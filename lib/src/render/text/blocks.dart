part of '../view.dart';

extension _StreamingMarkdownBlockTextParsing on StreamingMarkdownRenderView {
  _ParsedList _parseListNode(MarkdownRenderNode node) =>
      _parseListSlices(_normalizedSlice(node.raw, 0));

  /// Items with their bodies as slices.
  ///
  /// The body's position comes from the regex match that found it — the group
  /// start is already known here. It used to be discarded, leaving the caller
  /// to search the block for the body's text, which matched the marker for an
  /// item like `1. 1`.
  _ParsedList _parseListSlices(_SourceSlice source) {
    final List<_SourceSlice> lines = source.splitLines();
    final List<_ParsedListItem> items = <_ParsedListItem>[];

    for (final _SourceSlice line in lines) {
      final RegExpMatch? markerMatch = RegExp(
        r'^(\s*)([-+*]|\d+[.)])\s+(.*)$',
      ).firstMatch(line.text);
      if (markerMatch == null) {
        if (items.isNotEmpty && line.text.trim().isNotEmpty) {
          final _ParsedListItem last = items.removeLast();
          items.add(
            _ParsedListItem(
              level: last.level,
              ordered: last.ordered,
              order: last.order,
              taskState: last.taskState,
              // The joining space IS the line break it replaced, painted
              // differently — same as a paragraph's folded newline. Giving it
              // that position keeps the whole body traceable, where a
              // position-less space used to cost the item every range in it.
              body: last.body +
                  _SourceSlice.whole(' ', last.body.sourceEnd) +
                  line.trim(),
              stableKey: last.stableKey,
            ),
          );
        }
        continue;
      }

      final String marker = markerMatch.group(2)!;
      // Dart has no per-group offset, but the pattern is anchored at both
      // ends, so the body starts exactly where the line stops being marker.
      final String bodyText = markerMatch.group(3)!;
      _SourceSlice body = line
          .sub(line.text.length - bodyText.length, line.text.length)
          .trimRight();
      bool? taskState;
      final RegExpMatch? taskMatch = RegExp(
        r'^\[([ xX])\]\s*(.*)$',
      ).firstMatch(body.text);
      if (taskMatch != null) {
        taskState = taskMatch.group(1)!.toLowerCase() == 'x';
        final String afterTask = taskMatch.group(2)!;
        body = body.sub(
            body.text.length - afterTask.length, body.text.length);
      }

      final int level = (markerMatch.group(1)!.length / 2).floor();
      final bool ordered = RegExp(r'^\d').hasMatch(marker);
      final int order = ordered
          ? int.tryParse(marker.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1
          : 0;

      items.add(
        _ParsedListItem(
          level: level,
          ordered: ordered,
          order: order,
          taskState: taskState,
          body: body.trim(),
          stableKey: 'line_${items.length}',
        ),
      );
    }

    return _ParsedList(items: items);
  }

  _CalloutData? _parseCallout(String text) =>
      _parseCalloutSlices(_SourceSlice.whole(text, 0));

  /// The callout's title and body, each knowing where it came from.
  ///
  /// A custom title is a slice of the first line; only the DEFAULT title is
  /// generated, and only that one has no position of its own.
  _CalloutData? _parseCalloutSlices(_SourceSlice source) {
    final List<_SourceSlice> lines = source.splitLines();
    if (lines.isEmpty) {
      return null;
    }

    final _SourceSlice first = lines.first;
    final RegExpMatch? match = RegExp(
      r'^\s*\[!(\w+)\]\s*(.*)$',
    ).firstMatch(first.text);
    if (match == null) {
      return null;
    }

    final String kind = match.group(1)!.toLowerCase();
    final String customTitle = match.group(2)!;
    final int at = first.offsets.isEmpty ? 0 : first.offsets.first;
    final _SourceSlice titleSlice = customTitle.trim().isEmpty
        ? _SourceSlice.generated(
            kind[0].toUpperCase() + kind.substring(1), at)
        : first
            .sub(first.text.length - customTitle.length, first.text.length)
            .trim();

    return _CalloutData(
      kind: kind,
      titleSlice: titleSlice,
      bodySlice: _joinSliceLines(lines.skip(1).toList(growable: false)).trim(),
    );
  }


  Color _calloutColor(String? kind) {
    switch (kind) {
      case 'note':
        return const Color(0xFF58A6FF);
      case 'tip':
        return const Color(0xFF3FB950);
      case 'warning':
        return const Color(0xFFD29922);
      case 'important':
        return const Color(0xFFBC8CFF);
      case 'caution':
        return const Color(0xFFF85149);
      default:
        return const Color(0xFF8B949E);
    }
  }

  IconData _calloutIcon(String kind) {
    switch (kind) {
      case 'note':
        return Icons.info_outline;
      case 'tip':
        return Icons.lightbulb_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'important':
        return Icons.priority_high;
      case 'caution':
        return Icons.error_outline;
      default:
        return Icons.notes;
    }
  }

  String _quoteText(MarkdownRenderNode node) =>
      _quoteSlice(node.raw, 0).text;


  String _codeText(MarkdownRenderNode node) =>
      _codeSlice(node.raw, 0, node.type).text;


  String _codeLanguage(String raw) {
    final RegExpMatch? match = RegExp(
      r'^\s*(```+|~~~+)\s*([A-Za-z0-9_+\-\.#]*)',
      multiLine: true,
    ).firstMatch(raw);
    if (match == null) {
      return '';
    }
    return match.group(2)!.trim();
  }
}
