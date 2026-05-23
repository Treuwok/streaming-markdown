part of '../view.dart';

class _MarkdownSelectionArea extends StatefulWidget {
  const _MarkdownSelectionArea({
    required this.projection,
    required this.selectionStrategy,
    required this.allowUnclosedInlineDelimiters,
    required this.selectionColor,
    required this.child,
  });

  final _MarkdownSelectionProjection projection;
  final SelectionStrategy selectionStrategy;
  final bool allowUnclosedInlineDelimiters;
  final Color selectionColor;
  final Widget child;

  @override
  State<_MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<_MarkdownSelectionArea> {
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();
  SelectedContent? _selectedContent;
  _MarkdownSelectionRange? _selectionRange;
  _MarkdownSourceSelectionRange? _sourceSelectionRange;
  String _lastSelectedPlainText = '';
  bool _selectionRangeLocked = false;
  bool _suppressFrameworkSelectionClear = false;
  bool _sourceSelectionVisualActive = false;
  bool _frameworkSelectionClearScheduled = false;
  bool _selectionPointerActive = false;
  bool _selectionCreatedByPointer = false;
  bool _deferViewportFreezeUntilPointerUp = false;
  bool _frameworkSelectionChanging = false;
  int? _activeSelectionPointer;
  int _selectionEpoch = 0;
  ScrollPosition? _scrollPosition;
  double? _lastScrollPixels;
  late final FocusNode _focusNode = FocusNode(debugLabel: 'markdown-selection');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    web_copy.WebCopyInterceptor.attach(
      focusNode: _focusNode,
      onCopy: _handleBrowserCopy,
    );
  }

  @override
  void dispose() {
    web_copy.WebCopyInterceptor.detach(focusNode: _focusNode);
    _detachScrollPosition();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScrollPosition? nextScrollPosition =
        Scrollable.maybeOf(context)?.position;
    if (nextScrollPosition == _scrollPosition) {
      return;
    }
    _detachScrollPosition();
    _scrollPosition = nextScrollPosition;
    _lastScrollPixels = nextScrollPosition?.pixels;
    nextScrollPosition?.isScrollingNotifier.addListener(_handleScrollActivity);
    nextScrollPosition?.addListener(_handleScrollOffsetChanged);
  }

  @override
  void didUpdateWidget(covariant _MarkdownSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldFreezeForProjectionChange(oldWidget.projection)) {
      _freezeSelectionForViewportMutation(deferClear: true);
    }
    final _MarkdownSelectionRange? currentRange = _selectionRange;
    if (currentRange == null) {
      return;
    }
    final int max = widget.projection.fullPlainText.length;
    final int start = currentRange.start.clamp(0, max);
    final int end = currentRange.end.clamp(start, max);
    _selectionRange = _MarkdownSelectionRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (CopySelectionTextIntent intent) {
            _copyMarkdownSelection();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: true,
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerFinished,
          onPointerCancel: _handlePointerFinished,
          child: SelectionArea(
            key: _selectionAreaKey,
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
              final String plainText = content?.plainText ?? '';
              if (plainText.isEmpty) {
                if (_suppressFrameworkSelectionClear) {
                  _suppressFrameworkSelectionClear = false;
                  return;
                }
                if (_selectionRangeLocked && _sourceSelectionRange != null) {
                  return;
                }
                if (!_focusNode.hasFocus) {
                  _clearSelectionCache();
                }
                return;
              }
              if (_selectionRangeLocked) {
                if (_selectionPointerActive || _frameworkSelectionChanging) {
                  _clearSelectionCache(
                    notify: _sourceSelectionVisualActive,
                  );
                } else {
                  _clearFrameworkSelectionVisual();
                  return;
                }
              }
              _setSourceSelectionVisualActive(false);
              _selectionCreatedByPointer = _selectionCreatedByPointer ||
                  _selectionPointerActive ||
                  _frameworkSelectionChanging;
              _lastSelectedPlainText = plainText;
              _selectionRange = widget.projection.findRangeForSelectedPlainText(
                plainText,
                preferredStart: _selectionRange?.start,
              );
              _sourceSelectionRange =
                  widget.projection.sourceRangeForSelectedPlainText(
                plainText,
                preferredPlainStart: _selectionRange?.start,
              );
              _selectionEpoch += 1;
              if (content != null && !_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
            },
            child: _MarkdownSourceSelectionVisualScope(
              sourceRange:
                  _sourceSelectionVisualActive ? _sourceSelectionRange : null,
              plainRange: _sourceSelectionVisualActive ? _selectionRange : null,
              selectionColor: widget.selectionColor,
              child: _SelectableRegionStatusListener(
                onStatusChanged: _handleSelectableRegionStatusChanged,
                child: widget.child,
              ),
            ),
          ),
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
            allowUnclosedInlineDelimiters: widget.allowUnclosedInlineDelimiters,
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
            allowUnclosedInlineDelimiters: widget.allowUnclosedInlineDelimiters,
          )
        : null;
    final String plainText = switch (widget.selectionStrategy) {
      SelectionStrategy.plain => payload.plainText,
      SelectionStrategy.raw =>
        payload.markdownText.isEmpty ? payload.plainText : payload.markdownText,
      SelectionStrategy.rich => payload.plainText,
    };
    return web_copy.BrowserCopyData(
      plainText: plainText,
      htmlText:
          widget.selectionStrategy == SelectionStrategy.rich ? htmlText : null,
    );
  }

  _MarkdownClipboardPayloadData? _buildClipboardPayload() {
    final _MarkdownClipboardPayloadData? rangePayload =
        _buildRangeClipboardPayload();
    final _MarkdownSourceSelectionRange? sourceRange = _sourceSelectionRange;
    if (sourceRange != null) {
      final String markdownText =
          widget.projection.markdownForSourceRange(sourceRange);
      if (markdownText.isNotEmpty || _lastSelectedPlainText.isNotEmpty) {
        if (rangePayload != null &&
            rangePayload.markdownText.length > markdownText.length &&
            rangePayload.markdownText.startsWith(markdownText)) {
          return rangePayload;
        }
        return _MarkdownClipboardPayloadData(
          plainText: _lastSelectedPlainText,
          markdownText: markdownText,
        );
      }
    }

    if (rangePayload != null) {
      return rangePayload;
    }

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

  _MarkdownClipboardPayloadData? _buildRangeClipboardPayload() {
    final _MarkdownSelectionRange? range = _selectionRange;
    if (range != null) {
      final String plainText = widget.projection.plainTextForRange(range);
      final String markdownText = widget.projection.markdownForRange(range);
      if (plainText.isNotEmpty || markdownText.isNotEmpty) {
        return _MarkdownClipboardPayloadData(
          plainText: plainText,
          markdownText: markdownText,
        );
      }
    }
    return null;
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      return;
    }
    if (_selectionRangeLocked && _sourceSelectionRange != null) {
      return;
    }
    _clearSelectionCache();
  }

  void _handleScrollActivity() {
    if (_sourceSelectionRange == null ||
        _scrollPosition?.isScrollingNotifier.value != true) {
      return;
    }
    _freezeSelectionForViewportMutation();
  }

  void _handleScrollOffsetChanged() {
    final ScrollPosition? scrollPosition = _scrollPosition;
    if (scrollPosition == null) {
      return;
    }
    final double previousPixels = _lastScrollPixels ?? scrollPosition.pixels;
    final double pixels = scrollPosition.pixels;
    _lastScrollPixels = pixels;
    if ((pixels - previousPixels).abs() < 0.001 ||
        _sourceSelectionRange == null) {
      return;
    }
    _freezeSelectionForViewportMutation();
  }

  void _handleSelectableRegionStatusChanged(
    SelectableRegionSelectionStatus status,
  ) {
    if (_suppressFrameworkSelectionClear) {
      return;
    }
    switch (status) {
      case SelectableRegionSelectionStatus.changing:
        if (_scrollPosition?.isScrollingNotifier.value == true) {
          _freezeSelectionForViewportMutation();
          return;
        }
        _frameworkSelectionChanging = true;
        if (_selectionRangeLocked && _sourceSelectionRange != null) {
          return;
        }
        break;
      case SelectableRegionSelectionStatus.finalized:
        _frameworkSelectionChanging = false;
        break;
    }
  }

  void _clearSelectionCache({bool notify = false}) {
    void clear() {
      _selectedContent = null;
      _selectionRange = null;
      _sourceSelectionRange = null;
      _lastSelectedPlainText = '';
      _selectionRangeLocked = false;
      _suppressFrameworkSelectionClear = false;
      _sourceSelectionVisualActive = false;
      _frameworkSelectionClearScheduled = false;
      _selectionCreatedByPointer = false;
      _deferViewportFreezeUntilPointerUp = false;
      _frameworkSelectionChanging = false;
      _selectionEpoch += 1;
      _lastScrollPixels = _scrollPosition?.pixels;
    }

    if (notify && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  void _clearFrameworkSelectionVisual() {
    final SelectionAreaState? state = _selectionAreaKey.currentState;
    if (state == null) {
      return;
    }
    _suppressFrameworkSelectionClear = true;
    state.selectableRegion.clearSelection();
    _selectedContent = null;
    _setSourceSelectionVisualActive(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressFrameworkSelectionClear = false;
      }
    });
  }

  void _freezeSelectionForViewportMutation({bool deferClear = false}) {
    if (_sourceSelectionRange == null) {
      return;
    }
    if (_selectionPointerActive) {
      _deferViewportFreezeUntilPointerUp = true;
      return;
    }
    _selectionRangeLocked = true;
    if (deferClear) {
      _sourceSelectionVisualActive = true;
      _scheduleFrameworkSelectionClear();
      return;
    }
    _clearFrameworkSelectionVisual();
  }

  void _scheduleFrameworkSelectionClear() {
    if (_frameworkSelectionClearScheduled) {
      return;
    }
    final int epoch = _selectionEpoch;
    _frameworkSelectionClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        _frameworkSelectionClearScheduled = false;
        if (epoch != _selectionEpoch) {
          return;
        }
        _clearFrameworkSelectionVisual();
      });
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _selectionPointerActive = true;
    _activeSelectionPointer = event.pointer;
    _selectionCreatedByPointer = true;
  }

  void _handlePointerFinished(PointerEvent event) {
    if (_activeSelectionPointer != event.pointer) {
      return;
    }
    _activeSelectionPointer = null;
    _selectionPointerActive = false;
    if (_deferViewportFreezeUntilPointerUp) {
      _deferViewportFreezeUntilPointerUp = false;
      _freezeSelectionForViewportMutation(deferClear: true);
    }
  }

  bool _shouldFreezeForProjectionChange(
    _MarkdownSelectionProjection oldProjection,
  ) {
    final _MarkdownSourceSelectionRange? sourceRange = _sourceSelectionRange;
    if (sourceRange == null ||
        oldProjection.fullMarkdownText == widget.projection.fullMarkdownText) {
      return false;
    }
    if (_selectionRangeLocked ||
        _sourceSelectionVisualActive ||
        !_selectionCreatedByPointer) {
      return true;
    }
    final String oldSelectedMarkdown =
        oldProjection.markdownForSourceRange(sourceRange);
    final String newSelectedMarkdown =
        widget.projection.markdownForSourceRange(sourceRange);
    if (newSelectedMarkdown.isEmpty && oldSelectedMarkdown.isNotEmpty) {
      return true;
    }
    return oldSelectedMarkdown != newSelectedMarkdown;
  }

  void _detachScrollPosition() {
    _scrollPosition?.isScrollingNotifier.removeListener(_handleScrollActivity);
    _scrollPosition?.removeListener(_handleScrollOffsetChanged);
    _lastScrollPixels = null;
  }

  void _setSourceSelectionVisualActive(bool active) {
    if (_sourceSelectionVisualActive == active) {
      return;
    }
    if (!mounted) {
      _sourceSelectionVisualActive = active;
      return;
    }
    setState(() {
      _sourceSelectionVisualActive = active;
    });
  }
}

class _MarkdownSourceSelectionVisualScope extends InheritedWidget {
  const _MarkdownSourceSelectionVisualScope({
    required this.sourceRange,
    required this.plainRange,
    required this.selectionColor,
    required super.child,
  });

  final _MarkdownSourceSelectionRange? sourceRange;
  final _MarkdownSelectionRange? plainRange;
  final Color selectionColor;

  static _MarkdownSourceSelectionVisualScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        _MarkdownSourceSelectionVisualScope>();
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownSourceSelectionVisualScope oldWidget,
  ) {
    return sourceRange != oldWidget.sourceRange ||
        plainRange != oldWidget.plainRange ||
        selectionColor != oldWidget.selectionColor;
  }
}

class _MarkdownSelectionBlockVisualScope extends InheritedWidget {
  const _MarkdownSelectionBlockVisualScope({
    required this.blockRange,
    required super.child,
  });

  final _MarkdownSelectionBlockRange blockRange;

  static _MarkdownSelectionBlockVisualScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        _MarkdownSelectionBlockVisualScope>();
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownSelectionBlockVisualScope oldWidget,
  ) {
    return blockRange != oldWidget.blockRange;
  }
}

class _SelectableRegionStatusListener extends StatefulWidget {
  const _SelectableRegionStatusListener({
    required this.onStatusChanged,
    required this.child,
  });

  final ValueChanged<SelectableRegionSelectionStatus> onStatusChanged;
  final Widget child;

  @override
  State<_SelectableRegionStatusListener> createState() =>
      _SelectableRegionStatusListenerState();
}

class _SelectableRegionStatusListenerState
    extends State<_SelectableRegionStatusListener> {
  ValueListenable<SelectableRegionSelectionStatus>? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ValueListenable<SelectableRegionSelectionStatus>? nextStatus =
        SelectableRegionSelectionStatusScope.maybeOf(context);
    if (nextStatus == _status) {
      return;
    }
    _status?.removeListener(_handleStatusChanged);
    _status = nextStatus;
    _status?.addListener(_handleStatusChanged);
  }

  @override
  void dispose() {
    _status?.removeListener(_handleStatusChanged);
    super.dispose();
  }

  void _handleStatusChanged() {
    final SelectableRegionSelectionStatus? status = _status?.value;
    if (status == null) {
      return;
    }
    widget.onStatusChanged(status);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MarkdownClipboardPayloadData {
  const _MarkdownClipboardPayloadData({
    required this.plainText,
    required this.markdownText,
  });

  final String plainText;
  final String markdownText;
}
