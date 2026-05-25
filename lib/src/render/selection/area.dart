part of '../view.dart';

class _MarkdownSelectionArea extends StatefulWidget {
  const _MarkdownSelectionArea({
    required this.projection,
    required this.selectionStrategy,
    required this.allowUnclosedInlineDelimiters,
    required this.selectionColor,
    required this.useSourceSelectionVisual,
    required this.lockFinalizedSelectionVisual,
    required this.child,
  });

  final _MarkdownSelectionProjection projection;
  final SelectionStrategy selectionStrategy;
  final bool allowUnclosedInlineDelimiters;
  final Color selectionColor;
  final bool useSourceSelectionVisual;
  final bool lockFinalizedSelectionVisual;
  final Widget child;

  @override
  State<_MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<_MarkdownSelectionArea> {
  static const Duration _selectionAutoScrollTick = Duration(milliseconds: 16);
  static const double _selectionAutoScrollEdgeExtent = 56;
  static const double _selectionAutoScrollMaxVelocity = 720;

  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();
  final _MarkdownInlineSelectionRegistry _inlineSelectionRegistry =
      _MarkdownInlineSelectionRegistry();
  SelectedContent? _selectedContent;
  _MarkdownSelectionRange? _selectionRange;
  _MarkdownSelectionRange? _selectionCompactRange;
  _MarkdownSourceSelectionRange? _sourceSelectionRange;
  _MarkdownSelectionDragAnchor? _selectionDragAnchor;
  _MarkdownInlineSelectionDragUpdate? _lastSelectionDragUpdate;
  Offset? _selectionPointerDownGlobalPosition;
  String _lastSelectedPlainText = '';
  bool _selectionRangeLocked = false;
  bool _suppressFrameworkSelectionClear = false;
  bool _sourceSelectionVisualActive = false;
  bool _frameworkSelectionClearScheduled = false;
  bool _selectionPointerActive = false;
  bool _selectionCreatedByPointer = false;
  bool _deferViewportFreezeUntilPointerUp = false;
  bool _frameworkSelectionChanging = false;
  bool _ignoreFrameworkDragUpdatesUntilFinalized = false;
  bool _hasPointerHitTestDragUpdate = false;
  int? _activeSelectionPointer;
  int _selectionEpoch = 0;
  ScrollPosition? _scrollPosition;
  double? _lastScrollPixels;
  Timer? _selectionAutoScrollTimer;
  Offset? _lastSelectionDragGlobalPosition;
  bool _selectionAutoScrollMutatingViewport = false;
  final Set<_MarkdownSelectionAutoScrollRegion> _selectionAutoScrollRegions =
      <_MarkdownSelectionAutoScrollRegion>{};
  late final FocusNode _focusNode = FocusNode(debugLabel: 'markdown-selection');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _inlineSelectionRegistry.addListener(_handleInlineSelectionChanged);
    _inlineSelectionRegistry.addDragUpdateListener(
      _handleInlineSelectionDragUpdate,
    );
    web_copy.WebCopyInterceptor.attach(
      focusNode: _focusNode,
      onCopy: _handleBrowserCopy,
    );
  }

  @override
  void dispose() {
    _stopSelectionAutoScroll(clearDragPosition: true);
    web_copy.WebCopyInterceptor.detach(focusNode: _focusNode);
    _detachScrollPosition();
    _inlineSelectionRegistry.removeDragUpdateListener(
      _handleInlineSelectionDragUpdate,
    );
    _inlineSelectionRegistry.removeListener(_handleInlineSelectionChanged);
    _inlineSelectionRegistry.dispose();
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
    final _MarkdownSelectionRange? compactRange = _selectionCompactRange;
    if (compactRange != null) {
      final int compactMax = widget.projection.compactPlainText.length;
      final int compactStart = compactRange.start.clamp(0, compactMax);
      final int compactEnd = compactRange.end.clamp(compactStart, compactMax);
      _selectionCompactRange = _MarkdownSelectionRange(
        start: compactStart,
        end: compactEnd,
      );
    }
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
          onPointerMove: _handlePointerMove,
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
                if (_selectionPointerActive &&
                    _deferViewportFreezeUntilPointerUp) {
                  _clearFrameworkSelectionVisual();
                  return;
                }
                if (_selectionPointerActive) {
                  _clearSelectionCache(
                    notify: _sourceSelectionVisualActive,
                  );
                } else {
                  _clearFrameworkSelectionVisual();
                  return;
                }
              }
              _selectionCreatedByPointer =
                  _selectionCreatedByPointer || _selectionPointerActive;
              _syncSelectionFromFramework(plainText);
              if (content != null && !_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
            },
            child: _MarkdownInlineSelectionRegistryScope(
              registry: _inlineSelectionRegistry,
              child: _MarkdownSelectionAutoScrollScope(
                register: _registerSelectionAutoScrollRegion,
                unregister: _unregisterSelectionAutoScrollRegion,
                child: _MarkdownSourceSelectionVisualScope(
                  sourceRange: _sourceSelectionVisualActive
                      ? _sourceSelectionRange
                      : null,
                  plainRange:
                      _sourceSelectionVisualActive ? _selectionRange : null,
                  selectionColor: widget.selectionColor,
                  child: _SelectableRegionStatusListener(
                    onStatusChanged: _handleSelectableRegionStatusChanged,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleInlineSelectionChanged() {
    if (!mounted) {
      return;
    }
    if (!_selectionPointerActive &&
        !_selectionCreatedByPointer &&
        !_frameworkSelectionChanging) {
      return;
    }
    final _MarkdownInlineSelectionAggregate? selection =
        _inlineSelectionRegistry.selection;
    if (selection == null) {
      return;
    }
    if (_selectionRangeLocked && _deferViewportFreezeUntilPointerUp) {
      return;
    }
    if (_selectionRangeLocked &&
        !_selectionPointerActive &&
        !_frameworkSelectionChanging) {
      return;
    }
    _selectionCreatedByPointer =
        _selectionCreatedByPointer || _selectionPointerActive;
    _syncSelectionFromInlineRegistry(selection);
  }

  void _syncSelectionFromFramework(String plainText) {
    final _MarkdownInlineSelectionAggregate? inlineSelection =
        (_selectionPointerActive ||
                _selectionCreatedByPointer ||
                _frameworkSelectionChanging)
            ? _inlineSelectionRegistry.selection
            : null;
    if (inlineSelection != null) {
      _syncSelectionFromInlineRegistry(inlineSelection);
      return;
    }
    _syncSelectionFromPlainText(plainText);
  }

  void _syncSelectionFromInlineRegistry(
    _MarkdownInlineSelectionAggregate selection,
  ) {
    final _MarkdownInlineSelectionAggregate resolvedSelection =
        _stabilizedSelectionForActiveDrag(selection);
    final _MarkdownSourceSelectionRange? sourceRange =
        widget.projection.sourceRangeForPlainRange(
      resolvedSelection.compactRange,
      plainSeparator: '',
    );
    if (sourceRange == null) {
      _syncSelectionFromPlainText(_selectedContent?.plainText ?? '');
      return;
    }
    final String plainText =
        widget.projection.plainTextForRange(resolvedSelection.displayRange);
    _applySelectionSnapshot(
      plainRange: resolvedSelection.displayRange,
      compactRange: resolvedSelection.compactRange,
      sourceRange: sourceRange,
      plainText: plainText,
    );
  }

  _MarkdownInlineSelectionAggregate _stabilizedSelectionForActiveDrag(
    _MarkdownInlineSelectionAggregate selection,
  ) {
    final _MarkdownInlineSelectionDragUpdate? update = _lastSelectionDragUpdate;
    if (update == null ||
        (!_selectionPointerActive &&
            !_frameworkSelectionChanging &&
            !_selectionCreatedByPointer)) {
      return selection;
    }
    final _MarkdownSelectionDragAnchor anchor =
        _selectionDragAnchor ??= _createSelectionDragAnchor(selection, update);
    final int displayMax = widget.projection.fullPlainText.length;
    final int compactMax = widget.projection.compactPlainText.length;
    final _MarkdownSelectionRange displayRange = _orderedSelectionRange(
      anchor.displayOffset,
      update.displayOffset,
      max: displayMax,
    );
    final _MarkdownSelectionRange compactRange = _orderedSelectionRange(
      anchor.compactOffset,
      update.compactOffset,
      max: compactMax,
    );
    if (displayRange.start >= displayRange.end ||
        compactRange.start >= compactRange.end) {
      return selection;
    }
    return _MarkdownInlineSelectionAggregate(
      displayRange: displayRange,
      compactRange: compactRange,
    );
  }

  _MarkdownSelectionDragAnchor _createSelectionDragAnchor(
    _MarkdownInlineSelectionAggregate selection,
    _MarkdownInlineSelectionDragUpdate update,
  ) {
    final _MarkdownSelectionRange? previousDisplayRange = _selectionRange;
    final _MarkdownSelectionRange? previousCompactRange =
        _selectionCompactRange;
    if (!_selectionPointerActive &&
        previousDisplayRange != null &&
        previousCompactRange != null) {
      return update.isEnd
          ? _MarkdownSelectionDragAnchor(
              displayOffset: previousDisplayRange.start,
              compactOffset: previousCompactRange.start,
            )
          : _MarkdownSelectionDragAnchor(
              displayOffset: previousDisplayRange.end,
              compactOffset: previousCompactRange.end,
            );
    }

    final Offset? pointerDown = _selectionPointerDownGlobalPosition;
    final bool draggingForward = pointerDown == null ||
        update.globalPosition.dy > pointerDown.dy ||
        (update.globalPosition.dy == pointerDown.dy &&
            update.globalPosition.dx >= pointerDown.dx);
    return draggingForward
        ? _MarkdownSelectionDragAnchor(
            displayOffset: selection.displayRange.start,
            compactOffset: selection.compactRange.start,
          )
        : _MarkdownSelectionDragAnchor(
            displayOffset: selection.displayRange.end,
            compactOffset: selection.compactRange.end,
          );
  }

  _MarkdownSelectionRange _orderedSelectionRange(
    int anchor,
    int extent, {
    required int max,
  }) {
    final int resolvedAnchor = anchor.clamp(0, max);
    final int resolvedExtent = extent.clamp(0, max);
    if (resolvedAnchor <= resolvedExtent) {
      return _MarkdownSelectionRange(
        start: resolvedAnchor,
        end: resolvedExtent,
      );
    }
    return _MarkdownSelectionRange(
      start: resolvedExtent,
      end: resolvedAnchor,
    );
  }

  void _syncSelectionFromPlainText(String plainText) {
    final String selectedPlainText = plainText.replaceAll('\r', '');
    final _MarkdownSelectionRange? plainRange =
        widget.projection.findRangeForSelectedPlainText(
      selectedPlainText,
      preferredStart: _selectionRange?.start,
    );
    final _MarkdownSourceSelectionRange? sourceRange =
        widget.projection.sourceRangeForSelectedPlainText(
      selectedPlainText,
      preferredPlainStart: plainRange?.start ?? _selectionRange?.start,
    );
    _applySelectionSnapshot(
      plainRange: plainRange,
      compactRange: plainRange,
      sourceRange: sourceRange,
      plainText: plainRange == null
          ? selectedPlainText
          : widget.projection.plainTextForRange(plainRange),
    );
  }

  void _applySelectionSnapshot({
    required _MarkdownSelectionRange? plainRange,
    required _MarkdownSelectionRange? compactRange,
    required _MarkdownSourceSelectionRange? sourceRange,
    required String plainText,
  }) {
    final bool visualActive = widget.useSourceSelectionVisual &&
        plainRange != null &&
        sourceRange != null;
    if (_selectionRange == plainRange &&
        _selectionCompactRange == compactRange &&
        _sourceSelectionRange == sourceRange &&
        _lastSelectedPlainText == plainText &&
        _sourceSelectionVisualActive == visualActive) {
      return;
    }

    void apply() {
      _selectionRange = plainRange;
      _selectionCompactRange = compactRange;
      _sourceSelectionRange = sourceRange;
      _lastSelectedPlainText = plainText;
      _sourceSelectionVisualActive = visualActive;
      _selectionEpoch += 1;
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
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
            rangePayload.markdownText.isNotEmpty &&
            rangePayload.plainText == _lastSelectedPlainText &&
            markdownText.length > rangePayload.markdownText.length) {
          return rangePayload;
        }
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
    if (_selectionAutoScrollMutatingViewport) {
      return;
    }
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
    if (_selectionAutoScrollMutatingViewport) {
      return;
    }
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
        if (_scrollPosition?.isScrollingNotifier.value == true &&
            !_selectionAutoScrollMutatingViewport) {
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
        _ignoreFrameworkDragUpdatesUntilFinalized = false;
        _stopSelectionAutoScroll(clearDragPosition: true);
        if (widget.lockFinalizedSelectionVisual) {
          _scheduleFinalizedSelectionVisualLock();
        }
        break;
    }
  }

  void _clearSelectionCache({bool notify = false}) {
    void clear() {
      _selectedContent = null;
      _selectionRange = null;
      _selectionCompactRange = null;
      _sourceSelectionRange = null;
      _selectionDragAnchor = null;
      _lastSelectionDragUpdate = null;
      _selectionPointerDownGlobalPosition = null;
      _lastSelectedPlainText = '';
      _selectionRangeLocked = false;
      _suppressFrameworkSelectionClear = false;
      _sourceSelectionVisualActive = false;
      _frameworkSelectionClearScheduled = false;
      _selectionCreatedByPointer = false;
      _deferViewportFreezeUntilPointerUp = false;
      _frameworkSelectionChanging = false;
      _ignoreFrameworkDragUpdatesUntilFinalized = false;
      _hasPointerHitTestDragUpdate = false;
      _selectionEpoch += 1;
      _lastScrollPixels = _scrollPosition?.pixels;
      _stopSelectionAutoScroll(clearDragPosition: true);
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
    _resolvePendingSelectionSnapshot();
    if (_sourceSelectionRange == null) {
      return;
    }
    if (_selectionPointerActive) {
      _selectionRangeLocked = true;
      _deferViewportFreezeUntilPointerUp = true;
      _setSourceSelectionVisualActive(true);
      return;
    }
    _selectionRangeLocked = true;
    if (deferClear) {
      _setSourceSelectionVisualActive(true);
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

  void _scheduleFinalizedSelectionVisualLock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted ||
            _selectionPointerActive ||
            _sourceSelectionRange == null ||
            _selectionRange == null ||
            _lastSelectedPlainText.isEmpty) {
          return;
        }
        _freezeSelectionForViewportMutation(deferClear: true);
      });
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isPrimarySelectionPointer(event)) {
      return;
    }
    if (_selectionRangeLocked && _sourceSelectionRange != null) {
      _clearSelectionCache(notify: _sourceSelectionVisualActive);
    }
    _selectionPointerActive = true;
    _activeSelectionPointer = event.pointer;
    _selectionCreatedByPointer = true;
    _ignoreFrameworkDragUpdatesUntilFinalized = false;
    _hasPointerHitTestDragUpdate = false;
    _selectionDragAnchor = null;
    _lastSelectionDragUpdate = null;
    _selectionPointerDownGlobalPosition = event.position;
    _handleSelectionDragPositionChanged(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activeSelectionPointer != event.pointer) {
      return;
    }
    final _MarkdownInlineSelectionDragUpdate? dragUpdate =
        _inlineSelectionRegistry.dragUpdateForGlobalPosition(event.position);
    if (dragUpdate != null) {
      _handleInlineSelectionDragUpdate(
        dragUpdate,
        fromPointerHitTest: true,
      );
      return;
    }
    _handleSelectionDragPositionChanged(event.position);
  }

  void _handlePointerFinished(PointerEvent event) {
    if (_activeSelectionPointer != event.pointer) {
      return;
    }
    _activeSelectionPointer = null;
    _selectionPointerActive = false;
    _ignoreFrameworkDragUpdatesUntilFinalized = true;
    _stopSelectionAutoScroll(clearDragPosition: true);
    _selectionPointerDownGlobalPosition = null;
    if (_deferViewportFreezeUntilPointerUp) {
      _deferViewportFreezeUntilPointerUp = false;
      _freezeSelectionForViewportMutation(deferClear: true);
      return;
    }
    if (widget.lockFinalizedSelectionVisual) {
      _scheduleFinalizedSelectionVisualLock();
    }
  }

  bool _shouldFreezeForProjectionChange(
    _MarkdownSelectionProjection oldProjection,
  ) {
    if (oldProjection.fullMarkdownText == widget.projection.fullMarkdownText) {
      return false;
    }
    if (_selectionPointerActive &&
        !_deferViewportFreezeUntilPointerUp &&
        (_scrollPosition?.isScrollingNotifier.value != true ||
            _selectionAutoScrollMutatingViewport)) {
      return false;
    }
    return _sourceSelectionRange != null ||
        _selectionRange != null ||
        (_selectedContent?.plainText.isNotEmpty ?? false);
  }

  void _resolvePendingSelectionSnapshot() {
    if (_sourceSelectionRange != null) {
      return;
    }
    final String selectedPlainText =
        (_selectedContent?.plainText ?? '').replaceAll('\r', '');
    if (selectedPlainText.isEmpty) {
      return;
    }
    _syncSelectionFromPlainText(selectedPlainText);
  }

  void _handleInlineSelectionDragUpdate(
    _MarkdownInlineSelectionDragUpdate update, {
    bool fromPointerHitTest = false,
  }) {
    if (!fromPointerHitTest &&
        _selectionPointerActive &&
        _hasPointerHitTestDragUpdate) {
      return;
    }
    if (_ignoreFrameworkDragUpdatesUntilFinalized && !_selectionPointerActive) {
      return;
    }
    _hasPointerHitTestDragUpdate =
        _hasPointerHitTestDragUpdate || fromPointerHitTest;
    _lastSelectionDragUpdate = update;
    _handleSelectionDragPositionChanged(update.globalPosition);
    _syncSelectionFromActiveDragUpdate(update);
  }

  void _syncSelectionFromActiveDragUpdate(
    _MarkdownInlineSelectionDragUpdate update,
  ) {
    if (!_selectionPointerActive &&
        !_frameworkSelectionChanging &&
        !_selectionCreatedByPointer) {
      return;
    }
    final _MarkdownInlineSelectionAggregate? selection =
        _inlineSelectionRegistry.selection ??
            _selectionAggregateFromDragAnchor(update);
    if (selection == null) {
      return;
    }
    _selectionCreatedByPointer =
        _selectionCreatedByPointer || _selectionPointerActive;
    _syncSelectionFromInlineRegistry(selection);
  }

  _MarkdownInlineSelectionAggregate? _selectionAggregateFromDragAnchor(
    _MarkdownInlineSelectionDragUpdate update,
  ) {
    final _MarkdownSelectionDragAnchor? anchor = _selectionDragAnchor;
    if (anchor == null) {
      return null;
    }
    final _MarkdownSelectionRange displayRange = _orderedSelectionRange(
      anchor.displayOffset,
      update.displayOffset,
      max: widget.projection.fullPlainText.length,
    );
    final _MarkdownSelectionRange compactRange = _orderedSelectionRange(
      anchor.compactOffset,
      update.compactOffset,
      max: widget.projection.compactPlainText.length,
    );
    if (displayRange.start >= displayRange.end ||
        compactRange.start >= compactRange.end) {
      return null;
    }
    return _MarkdownInlineSelectionAggregate(
      displayRange: displayRange,
      compactRange: compactRange,
    );
  }

  void _detachScrollPosition() {
    _stopSelectionAutoScroll(clearDragPosition: false);
    _scrollPosition?.isScrollingNotifier.removeListener(_handleScrollActivity);
    _scrollPosition?.removeListener(_handleScrollOffsetChanged);
    _lastScrollPixels = null;
  }

  bool _isPrimarySelectionPointer(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton) != 0;
  }

  void _handleSelectionDragPositionChanged(Offset globalPosition) {
    if (!mounted) {
      return;
    }
    _lastSelectionDragGlobalPosition = globalPosition;
    if (!_hasSelectionAutoScrollTarget(globalPosition)) {
      _stopSelectionAutoScroll(clearDragPosition: false);
      return;
    }
    if (_selectionAutoScrollTimer != null) {
      return;
    }
    _selectionAutoScrollTimer = Timer.periodic(
      _selectionAutoScrollTick,
      (_) => _tickSelectionAutoScroll(),
    );
  }

  void _tickSelectionAutoScroll() {
    if (!mounted) {
      _stopSelectionAutoScroll(clearDragPosition: true);
      return;
    }
    final Offset? globalPosition = _lastSelectionDragGlobalPosition;
    if (globalPosition == null) {
      _stopSelectionAutoScroll(clearDragPosition: true);
      return;
    }
    bool scrolled = false;
    final double verticalVelocity =
        _selectionAutoScrollVelocityForPrimary(globalPosition);
    final ScrollPosition? primaryPosition = _scrollPosition;
    if (primaryPosition != null) {
      scrolled = _applySelectionAutoScrollDelta(
            primaryPosition,
            verticalVelocity,
            trackPrimaryScrollOffset: true,
          ) ||
          scrolled;
    }
    for (final _MarkdownSelectionAutoScrollRegion region
        in _selectionAutoScrollRegions.toList(growable: false)) {
      final ScrollController controller = region.controller;
      if (!controller.hasClients) {
        continue;
      }
      final double velocity =
          _selectionAutoScrollVelocityForRegion(region, globalPosition);
      scrolled = _applySelectionAutoScrollDelta(
            controller.position,
            velocity,
            trackPrimaryScrollOffset: false,
          ) ||
          scrolled;
    }
    if (!scrolled && !_hasSelectionAutoScrollTarget(globalPosition)) {
      _stopSelectionAutoScroll(clearDragPosition: false);
    }
  }

  bool _hasSelectionAutoScrollTarget(Offset globalPosition) {
    final double verticalVelocity =
        _selectionAutoScrollVelocityForPrimary(globalPosition);
    if (verticalVelocity != 0 &&
        _canScrollPositionInDirection(_scrollPosition, verticalVelocity)) {
      return true;
    }
    for (final _MarkdownSelectionAutoScrollRegion region
        in _selectionAutoScrollRegions) {
      final ScrollController controller = region.controller;
      if (!controller.hasClients) {
        continue;
      }
      final double velocity =
          _selectionAutoScrollVelocityForRegion(region, globalPosition);
      if (velocity != 0 &&
          _canScrollPositionInDirection(controller.position, velocity)) {
        return true;
      }
    }
    return false;
  }

  bool _applySelectionAutoScrollDelta(
    ScrollPosition position,
    double velocity, {
    required bool trackPrimaryScrollOffset,
  }) {
    if (velocity == 0 || !_canScrollPositionInDirection(position, velocity)) {
      return false;
    }
    final double delta =
        velocity * _selectionAutoScrollTick.inMicroseconds / 1000000;
    final double current = position.pixels;
    final double target = (current + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - current).abs() < 0.001) {
      return false;
    }
    _selectionAutoScrollMutatingViewport = true;
    try {
      position.jumpTo(target);
      if (trackPrimaryScrollOffset) {
        _lastScrollPixels = position.pixels;
      }
    } finally {
      _selectionAutoScrollMutatingViewport = false;
    }
    return true;
  }

  double _selectionAutoScrollVelocityForPrimary(Offset globalPosition) {
    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    final ScrollPosition? position = scrollable?.position ?? _scrollPosition;
    if (scrollable == null ||
        position == null ||
        !position.hasContentDimensions ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return 0;
    }
    final RenderObject? renderObject = scrollable.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 0;
    }
    final Rect viewport =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return _selectionAutoScrollVelocityForRect(
      globalPosition,
      viewport,
      Axis.vertical,
    );
  }

  double _selectionAutoScrollVelocityForRegion(
    _MarkdownSelectionAutoScrollRegion region,
    Offset globalPosition,
  ) {
    final ScrollController controller = region.controller;
    if (!controller.hasClients ||
        !_isScrollablePositionUsable(controller.position)) {
      return 0;
    }
    final BuildContext? context = region.key.currentContext;
    final RenderObject? renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 0;
    }
    final Rect viewport =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return _selectionAutoScrollVelocityForRect(
      globalPosition,
      viewport,
      region.axis,
    );
  }

  double _selectionAutoScrollVelocityForRect(
    Offset globalPosition,
    Rect viewport,
    Axis axis,
  ) {
    if (axis == Axis.horizontal &&
        (globalPosition.dy < viewport.top ||
            globalPosition.dy > viewport.bottom)) {
      return 0;
    }
    if (axis == Axis.vertical &&
        (globalPosition.dx < viewport.left ||
            globalPosition.dx > viewport.right)) {
      return 0;
    }
    final double leadingDistance = axis == Axis.horizontal
        ? globalPosition.dx - viewport.left
        : globalPosition.dy - viewport.top;
    if (leadingDistance < _selectionAutoScrollEdgeExtent) {
      final double clampedDistance = leadingDistance <= 0 ? 0 : leadingDistance;
      final double intensity =
          1 - clampedDistance / _selectionAutoScrollEdgeExtent;
      return -_selectionAutoScrollMaxVelocity * intensity;
    }
    final double trailingDistance = axis == Axis.horizontal
        ? viewport.right - globalPosition.dx
        : viewport.bottom - globalPosition.dy;
    if (trailingDistance < _selectionAutoScrollEdgeExtent) {
      final double clampedDistance =
          trailingDistance <= 0 ? 0 : trailingDistance;
      final double intensity =
          1 - clampedDistance / _selectionAutoScrollEdgeExtent;
      return _selectionAutoScrollMaxVelocity * intensity;
    }
    return 0;
  }

  bool _isScrollablePositionUsable(ScrollPosition position) {
    return position.hasPixels &&
        position.hasContentDimensions &&
        position.maxScrollExtent > position.minScrollExtent;
  }

  bool _canScrollPositionInDirection(
    ScrollPosition? position,
    double velocity,
  ) {
    if (position == null || !_isScrollablePositionUsable(position)) {
      return false;
    }
    const double boundaryEpsilon = 0.001;
    if (velocity < 0) {
      return position.pixels > position.minScrollExtent + boundaryEpsilon;
    }
    return position.pixels < position.maxScrollExtent - boundaryEpsilon;
  }

  void _registerSelectionAutoScrollRegion(
    _MarkdownSelectionAutoScrollRegion region,
  ) {
    _selectionAutoScrollRegions.add(region);
    final Offset? dragPosition = _lastSelectionDragGlobalPosition;
    if (dragPosition != null) {
      _handleSelectionDragPositionChanged(dragPosition);
    }
  }

  void _unregisterSelectionAutoScrollRegion(
    _MarkdownSelectionAutoScrollRegion region,
  ) {
    _selectionAutoScrollRegions.remove(region);
  }

  void _stopSelectionAutoScroll({required bool clearDragPosition}) {
    _selectionAutoScrollTimer?.cancel();
    _selectionAutoScrollTimer = null;
    _selectionAutoScrollMutatingViewport = false;
    if (clearDragPosition) {
      _lastSelectionDragGlobalPosition = null;
    }
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

typedef _MarkdownSelectionAutoScrollRegionCallback = void Function(
  _MarkdownSelectionAutoScrollRegion region,
);

class _MarkdownSelectionAutoScrollScope extends InheritedWidget {
  const _MarkdownSelectionAutoScrollScope({
    required this.register,
    required this.unregister,
    required super.child,
  });

  final _MarkdownSelectionAutoScrollRegionCallback register;
  final _MarkdownSelectionAutoScrollRegionCallback unregister;

  static _MarkdownSelectionAutoScrollScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        _MarkdownSelectionAutoScrollScope>();
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownSelectionAutoScrollScope oldWidget,
  ) {
    return register != oldWidget.register || unregister != oldWidget.unregister;
  }
}

class _MarkdownSelectionAutoScrollRegion {
  const _MarkdownSelectionAutoScrollRegion({
    required this.key,
    required this.controller,
    required this.axis,
  });

  final GlobalKey key;
  final ScrollController controller;
  final Axis axis;
}

class _MarkdownSelectionAutoScrollRegionHost extends StatefulWidget {
  const _MarkdownSelectionAutoScrollRegionHost({
    required this.axis,
    required this.builder,
  });

  final Axis axis;
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<_MarkdownSelectionAutoScrollRegionHost> createState() =>
      _MarkdownSelectionAutoScrollRegionHostState();
}

class _MarkdownSelectionAutoScrollRegionHostState
    extends State<_MarkdownSelectionAutoScrollRegionHost> {
  final GlobalKey _key = GlobalKey();
  late final ScrollController _controller = ScrollController();
  late _MarkdownSelectionAutoScrollRegion _region =
      _MarkdownSelectionAutoScrollRegion(
    key: _key,
    controller: _controller,
    axis: widget.axis,
  );
  _MarkdownSelectionAutoScrollScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _MarkdownSelectionAutoScrollScope? nextScope =
        _MarkdownSelectionAutoScrollScope.maybeOf(context);
    if (nextScope == _scope) {
      return;
    }
    _scope?.unregister(_region);
    _scope = nextScope;
    _scope?.register(_region);
  }

  @override
  void didUpdateWidget(
    covariant _MarkdownSelectionAutoScrollRegionHost oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.axis == widget.axis) {
      return;
    }
    _scope?.unregister(_region);
    _region = _MarkdownSelectionAutoScrollRegion(
      key: _key,
      controller: _controller,
      axis: widget.axis,
    );
    _scope?.register(_region);
  }

  @override
  void dispose() {
    _scope?.unregister(_region);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.builder(context, _controller),
    );
  }
}

class _MarkdownInlineSelectionRegistryScope extends InheritedWidget {
  const _MarkdownInlineSelectionRegistryScope({
    required this.registry,
    required super.child,
  });

  final _MarkdownInlineSelectionRegistry registry;

  static _MarkdownInlineSelectionRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
            _MarkdownInlineSelectionRegistryScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownInlineSelectionRegistryScope oldWidget,
  ) {
    return registry != oldWidget.registry;
  }
}

class _MarkdownInlineSelectionRegistry extends ChangeNotifier {
  final Map<Selectable, _MarkdownInlineSelectionSnapshot> _selections =
      <Selectable, _MarkdownInlineSelectionSnapshot>{};
  final Set<_RenderSelectableInlineTextProxy> _selectables =
      <_RenderSelectableInlineTextProxy>{};
  final List<ValueChanged<_MarkdownInlineSelectionDragUpdate>>
      _dragUpdateListeners =
      <ValueChanged<_MarkdownInlineSelectionDragUpdate>>[];

  _MarkdownInlineSelectionAggregate? get selection {
    if (_selections.isEmpty) {
      return null;
    }
    int? displayStart;
    int? displayEnd;
    int? compactStart;
    int? compactEnd;
    for (final _MarkdownInlineSelectionSnapshot snapshot
        in _selections.values) {
      displayStart = displayStart == null
          ? snapshot.displayRange.start
          : (displayStart < snapshot.displayRange.start
              ? displayStart
              : snapshot.displayRange.start);
      displayEnd = displayEnd == null
          ? snapshot.displayRange.end
          : (displayEnd > snapshot.displayRange.end
              ? displayEnd
              : snapshot.displayRange.end);
      compactStart = compactStart == null
          ? snapshot.compactRange.start
          : (compactStart < snapshot.compactRange.start
              ? compactStart
              : snapshot.compactRange.start);
      compactEnd = compactEnd == null
          ? snapshot.compactRange.end
          : (compactEnd > snapshot.compactRange.end
              ? compactEnd
              : snapshot.compactRange.end);
    }
    if (displayStart == null ||
        displayEnd == null ||
        compactStart == null ||
        compactEnd == null ||
        displayStart >= displayEnd ||
        compactStart >= compactEnd) {
      return null;
    }
    return _MarkdownInlineSelectionAggregate(
      displayRange: _MarkdownSelectionRange(
        start: displayStart,
        end: displayEnd,
      ),
      compactRange: _MarkdownSelectionRange(
        start: compactStart,
        end: compactEnd,
      ),
    );
  }

  void update(
    Selectable selectable, {
    required _MarkdownSelectionRange displayRange,
    required _MarkdownSelectionRange compactRange,
  }) {
    final _MarkdownInlineSelectionSnapshot next =
        _MarkdownInlineSelectionSnapshot(
      displayRange: displayRange,
      compactRange: compactRange,
    );
    if (_selections[selectable] == next) {
      return;
    }
    _selections[selectable] = next;
    notifyListeners();
  }

  void clear(Selectable selectable, {bool notify = true}) {
    if (_selections.remove(selectable) == null) {
      return;
    }
    if (notify) {
      notifyListeners();
    }
  }

  void registerSelectable(_RenderSelectableInlineTextProxy selectable) {
    _selectables.add(selectable);
  }

  void unregisterSelectable(_RenderSelectableInlineTextProxy selectable) {
    _selectables.remove(selectable);
  }

  _MarkdownInlineSelectionDragUpdate? dragUpdateForGlobalPosition(
    Offset globalPosition,
  ) {
    _RenderSelectableInlineTextProxy? best;
    double bestDistance = double.infinity;
    bool bestContains = false;
    for (final _RenderSelectableInlineTextProxy selectable
        in _selectables.toList(growable: false)) {
      if (!selectable.attached ||
          !selectable.hasSize ||
          selectable.plainText.isEmpty) {
        continue;
      }
      final Rect rect = selectable.localToGlobal(Offset.zero) & selectable.size;
      final bool contains = rect.inflate(4).contains(globalPosition);
      final double distance =
          contains ? 0 : _distanceFromPointToRect(globalPosition, rect);
      if (best == null ||
          (contains && !bestContains) ||
          (contains == bestContains && distance < bestDistance)) {
        best = selectable;
        bestContains = contains;
        bestDistance = distance;
      }
    }
    if (best == null || (!bestContains && bestDistance > 72 * 72)) {
      return null;
    }
    final Offset localPosition = best.globalToLocal(globalPosition);
    final int offset = best._positionForLocalOffset(localPosition);
    return _MarkdownInlineSelectionDragUpdate(
      globalPosition: globalPosition,
      displayOffset: best.absolutePlainTextStart + offset,
      compactOffset: best.compactPlainTextStart + offset,
      isEnd: true,
    );
  }

  double _distanceFromPointToRect(Offset point, Rect rect) {
    final double dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
            ? point.dx - rect.right
            : 0;
    final double dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
            ? point.dy - rect.bottom
            : 0;
    return dx * dx + dy * dy;
  }

  void addDragUpdateListener(
    ValueChanged<_MarkdownInlineSelectionDragUpdate> listener,
  ) {
    _dragUpdateListeners.add(listener);
  }

  void removeDragUpdateListener(
    ValueChanged<_MarkdownInlineSelectionDragUpdate> listener,
  ) {
    _dragUpdateListeners.remove(listener);
  }

  void reportDragUpdate(_MarkdownInlineSelectionDragUpdate update) {
    final List<ValueChanged<_MarkdownInlineSelectionDragUpdate>> listeners =
        List<ValueChanged<_MarkdownInlineSelectionDragUpdate>>.of(
      _dragUpdateListeners,
    );
    for (final ValueChanged<_MarkdownInlineSelectionDragUpdate> listener
        in listeners) {
      listener(update);
    }
  }

  @override
  void dispose() {
    _selectables.clear();
    _dragUpdateListeners.clear();
    super.dispose();
  }
}

class _MarkdownSelectionDragAnchor {
  const _MarkdownSelectionDragAnchor({
    required this.displayOffset,
    required this.compactOffset,
  });

  final int displayOffset;
  final int compactOffset;
}

class _MarkdownInlineSelectionDragUpdate {
  const _MarkdownInlineSelectionDragUpdate({
    required this.globalPosition,
    required this.displayOffset,
    required this.compactOffset,
    required this.isEnd,
  });

  final Offset globalPosition;
  final int displayOffset;
  final int compactOffset;
  final bool isEnd;
}

class _MarkdownInlineSelectionSnapshot {
  const _MarkdownInlineSelectionSnapshot({
    required this.displayRange,
    required this.compactRange,
  });

  final _MarkdownSelectionRange displayRange;
  final _MarkdownSelectionRange compactRange;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownInlineSelectionSnapshot &&
        other.displayRange == displayRange &&
        other.compactRange == compactRange;
  }

  @override
  int get hashCode => Object.hash(displayRange, compactRange);
}

class _MarkdownInlineSelectionAggregate {
  const _MarkdownInlineSelectionAggregate({
    required this.displayRange,
    required this.compactRange,
  });

  final _MarkdownSelectionRange displayRange;
  final _MarkdownSelectionRange compactRange;
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
