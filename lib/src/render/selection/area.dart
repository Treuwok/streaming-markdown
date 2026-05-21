part of '../view.dart';

class _MarkdownSelectionArea extends StatefulWidget {
  const _MarkdownSelectionArea({
    required this.projection,
    required this.selectionStrategy,
    required this.allowUnclosedInlineDelimiters,
    required this.child,
  });

  final _MarkdownSelectionProjection projection;
  final SelectionStrategy selectionStrategy;
  final bool allowUnclosedInlineDelimiters;
  final Widget child;

  @override
  State<_MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<_MarkdownSelectionArea> {
  SelectedContent? _selectedContent;
  late final FocusNode _focusNode = FocusNode(debugLabel: 'markdown-selection');

  @override
  void initState() {
    super.initState();
    web_copy.WebCopyInterceptor.attach(
      focusNode: _focusNode,
      onCopy: _handleBrowserCopy,
    );
  }

  @override
  void dispose() {
    web_copy.WebCopyInterceptor.detach(focusNode: _focusNode);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: true,
      child: SelectionArea(
        contextMenuBuilder: (
          BuildContext context,
          SelectableRegionState selectableRegionState,
        ) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: selectableRegionState.contextMenuButtonItems
                .map((ContextMenuButtonItem item) {
              if (item.type != ContextMenuButtonType.copy) {
                return item;
              }
              return ContextMenuButtonItem(
                type: item.type,
                label: item.label,
                onPressed: () {
                  _copyMarkdownSelection();
                  selectableRegionState.hideToolbar();
                },
              );
            }).toList(growable: false),
          );
        },
        onSelectionChanged: (SelectedContent? content) {
          _selectedContent = content;
          if (content != null && !_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
              onInvoke: (CopySelectionTextIntent intent) {
                _copyMarkdownSelection();
                return null;
              },
            ),
          },
          child: widget.child,
        ),
      ),
    );
  }

  void _copyMarkdownSelection() {
    final _MarkdownClipboardPayloadData? data = _buildClipboardPayload();
    if (data == null) {
      return;
    }
    final String? htmlText = widget.selectionStrategy == SelectionStrategy.rich
        ? _selectedMarkdownToHtml(
            data.markdownText,
            allowUnclosedInlineDelimiters:
                widget.allowUnclosedInlineDelimiters,
          )
        : null;
    final MarkdownClipboardPayload payload = MarkdownClipboardPayload(
      plainText: data.plainText,
      rawMarkdown: data.markdownText,
      htmlText: htmlText,
    );
    unawaited(
      MarkdownClipboardHandler().copySelection(
        strategy: widget.selectionStrategy,
        payload: payload,
      ),
    );
  }

  web_copy.BrowserCopyData? _handleBrowserCopy() {
    final _MarkdownClipboardPayloadData? payload = _buildClipboardPayload();
    if (payload == null) {
      return null;
    }
    final String? htmlText = widget.selectionStrategy == SelectionStrategy.rich
        ? _selectedMarkdownToHtml(
            payload.markdownText,
            allowUnclosedInlineDelimiters:
                widget.allowUnclosedInlineDelimiters,
          )
        : null;
    final String plainText = switch (widget.selectionStrategy) {
      SelectionStrategy.plain => payload.plainText,
      SelectionStrategy.raw => payload.markdownText.isEmpty
          ? payload.plainText
          : payload.markdownText,
      SelectionStrategy.rich => payload.plainText,
    };
    return web_copy.BrowserCopyData(
      plainText: plainText,
      htmlText: widget.selectionStrategy == SelectionStrategy.rich
          ? htmlText
          : null,
    );
  }

  _MarkdownClipboardPayloadData? _buildClipboardPayload() {
    final String plainText = _extractSelectedPlainText(
      projection: widget.projection,
      selectedContent: _selectedContent,
    );
    final String markdownText = _extractSelectedRawMarkdown(
      projection: widget.projection,
      selectedPlainText: plainText,
    );
    if (plainText.isEmpty && markdownText.isEmpty) {
      return null;
    }
    return _MarkdownClipboardPayloadData(
      plainText: plainText,
      markdownText: markdownText,
    );
  }
}

class _MarkdownClipboardPayloadData {
  const _MarkdownClipboardPayloadData({
    required this.plainText,
    required this.markdownText,
  });

  final String plainText;
  final String markdownText;
}
