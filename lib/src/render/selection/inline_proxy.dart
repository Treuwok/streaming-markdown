part of '../view.dart';

class _SelectableInlineTextProxy extends SingleChildRenderObjectWidget {
  const _SelectableInlineTextProxy({
    required this.plainText,
    required this.absolutePlainTextStart,
    required this.compactPlainTextStart,
    required this.text,
    required this.textDirection,
    required this.textScaler,
    required this.registrar,
    required this.selectionRegistry,
    required super.child,
  });

  final String plainText;
  final int absolutePlainTextStart;
  final int compactPlainTextStart;
  final TextSpan text;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final SelectionRegistrar? registrar;
  final _MarkdownInlineSelectionRegistry? selectionRegistry;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSelectableInlineTextProxy(
      plainText: plainText,
      absolutePlainTextStart: absolutePlainTextStart,
      compactPlainTextStart: compactPlainTextStart,
      text: text,
      textDirection: textDirection,
      textScaler: textScaler,
      registrar: registrar,
      selectionRegistry: selectionRegistry,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSelectableInlineTextProxy renderObject,
  ) {
    renderObject
      ..plainText = plainText
      ..absolutePlainTextStart = absolutePlainTextStart
      ..compactPlainTextStart = compactPlainTextStart
      ..text = text
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..registrar = registrar
      ..selectionRegistry = selectionRegistry;
  }
}

class _InlineSourceSelectionBackdrop extends SingleChildRenderObjectWidget {
  const _InlineSourceSelectionBackdrop({
    required this.range,
    required this.selectedText,
    required this.text,
    required this.textDirection,
    required this.textScaler,
    required this.selectionColor,
    required super.child,
  });

  final _MarkdownSelectionRange? range;
  final String selectedText;
  final TextSpan text;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Color? selectionColor;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderInlineSourceSelectionBackdrop(
      range: range,
      text: text,
      textDirection: textDirection,
      textScaler: textScaler,
      selectionColor: selectionColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderInlineSourceSelectionBackdrop renderObject,
  ) {
    renderObject
      ..range = range
      ..text = text
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..selectionColor = selectionColor;
  }
}

class _RenderInlineSourceSelectionBackdrop extends RenderProxyBox {
  _RenderInlineSourceSelectionBackdrop({
    required _MarkdownSelectionRange? range,
    required TextSpan text,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Color? selectionColor,
  })  : _range = range,
        _selectionColor = selectionColor {
    _textPainter
      ..text = text
      ..textDirection = textDirection
      ..textScaler = textScaler;
  }

  final TextPainter _textPainter = TextPainter();

  _MarkdownSelectionRange? get range => _range;
  _MarkdownSelectionRange? _range;
  set range(_MarkdownSelectionRange? value) {
    if (_range == value) {
      return;
    }
    _range = value;
    markNeedsPaint();
  }

  TextSpan get text => _textPainter.text! as TextSpan;
  set text(TextSpan value) {
    if (_textPainter.text == value) {
      return;
    }
    _textPainter.text = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  TextDirection get textDirection => _textPainter.textDirection!;
  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) {
      return;
    }
    _textPainter.textDirection = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  TextScaler get textScaler => _textPainter.textScaler;
  set textScaler(TextScaler value) {
    if (_textPainter.textScaler == value) {
      return;
    }
    _textPainter.textScaler = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  Color? get selectionColor => _selectionColor;
  Color? _selectionColor;
  set selectionColor(Color? value) {
    if (_selectionColor == value) {
      return;
    }
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    _layoutText();
  }

  void _layoutText() {
    final double maxWidth =
        size.width.isFinite ? size.width : constraints.maxWidth;
    _textPainter.layout(
      maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintSelection(context, offset);
    super.paint(context, offset);
  }

  void _paintSelection(PaintingContext context, Offset offset) {
    final _MarkdownSelectionRange? localRange = range;
    final Color? color = selectionColor;
    if (localRange == null ||
        color == null ||
        localRange.start >= localRange.end) {
      return;
    }
    if (_textPainter.width == 0 && hasSize) {
      _layoutText();
    }
    final List<TextBox> boxes = _textPainter.getBoxesForSelection(
      TextSelection(
        baseOffset: localRange.start,
        extentOffset: localRange.end,
      ),
    );
    if (boxes.isEmpty) {
      return;
    }
    final Paint paint = Paint()..color = color;
    for (final Rect rect in _mergeSelectionRects(boxes)) {
      context.canvas.drawRect(rect.shift(offset), paint);
    }
  }

  List<Rect> _mergeSelectionRects(List<TextBox> boxes) {
    final List<Rect> rects = boxes
        .map((TextBox box) => box.toRect())
        .where((Rect rect) => !rect.isEmpty)
        .toList(growable: false)
      ..sort((Rect a, Rect b) {
        final int byTop = a.top.compareTo(b.top);
        return byTop == 0 ? a.left.compareTo(b.left) : byTop;
      });
    final List<Rect> merged = <Rect>[];
    for (final Rect rect in rects) {
      if (merged.isEmpty) {
        merged.add(rect);
        continue;
      }
      final Rect previous = merged.last;
      final double previousCenter = previous.top + previous.height / 2;
      final double rectCenter = rect.top + rect.height / 2;
      final bool sameLine =
          (previousCenter - rectCenter).abs() <= previous.height / 2 + 1;
      if (sameLine) {
        merged[merged.length - 1] = Rect.fromLTRB(
          previous.left < rect.left ? previous.left : rect.left,
          previous.top < rect.top ? previous.top : rect.top,
          previous.right > rect.right ? previous.right : rect.right,
          previous.bottom > rect.bottom ? previous.bottom : rect.bottom,
        );
      } else {
        merged.add(rect);
      }
    }
    return merged;
  }
}

class _RenderSelectableInlineTextProxy extends RenderProxyBox
    implements Selectable {
  _RenderSelectableInlineTextProxy({
    required String plainText,
    required int absolutePlainTextStart,
    required int compactPlainTextStart,
    required TextSpan text,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required SelectionRegistrar? registrar,
    required _MarkdownInlineSelectionRegistry? selectionRegistry,
  })  : _plainText = plainText,
        _absolutePlainTextStart = absolutePlainTextStart,
        _compactPlainTextStart = compactPlainTextStart,
        _registrar = registrar,
        _selectionRegistry = selectionRegistry {
    _textPainter
      ..text = text
      ..textDirection = textDirection
      ..textScaler = textScaler;
    _updateSelectionRegistrarSubscription();
  }

  final TextPainter _textPainter = TextPainter();
  final List<VoidCallback> _listeners = <VoidCallback>[];

  String _plainText;
  int _absolutePlainTextStart;
  int _compactPlainTextStart;
  TextSpan get text => _textPainter.text! as TextSpan;
  set text(TextSpan value) {
    if (_textPainter.text == value) {
      return;
    }
    _textPainter.text = value;
    _textPainter.markNeedsLayout();
    _clearSelection(notify: false);
    markNeedsLayout();
  }

  String get plainText => _plainText;
  set plainText(String value) {
    if (_plainText == value) {
      return;
    }
    _plainText = value;
    _clearSelection(notify: false);
    _updateSelectionRegistrarSubscription();
    markNeedsLayout();
  }

  int get absolutePlainTextStart => _absolutePlainTextStart;
  set absolutePlainTextStart(int value) {
    if (_absolutePlainTextStart == value) {
      return;
    }
    _absolutePlainTextStart = value;
    _updateSelectionRegistry();
  }

  int get compactPlainTextStart => _compactPlainTextStart;
  set compactPlainTextStart(int value) {
    if (_compactPlainTextStart == value) {
      return;
    }
    _compactPlainTextStart = value;
    _updateSelectionRegistry();
  }

  TextDirection get textDirection => _textPainter.textDirection!;
  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) {
      return;
    }
    _textPainter.textDirection = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  TextScaler get textScaler => _textPainter.textScaler;
  set textScaler(TextScaler value) {
    if (_textPainter.textScaler == value) {
      return;
    }
    _textPainter.textScaler = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  SelectionRegistrar? get registrar => _registrar;
  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (_registrar == value) {
      return;
    }
    _removeSelectionRegistrarSubscription();
    _registrar = value;
    _updateSelectionRegistrarSubscription();
  }

  _MarkdownInlineSelectionRegistry? get selectionRegistry => _selectionRegistry;
  _MarkdownInlineSelectionRegistry? _selectionRegistry;
  set selectionRegistry(_MarkdownInlineSelectionRegistry? value) {
    if (_selectionRegistry == value) {
      return;
    }
    _selectionRegistry?.clear(this, notify: false);
    _selectionRegistry = value;
    _updateSelectionRegistry();
  }

  bool _subscribedToSelectionRegistrar = false;
  int? _selectionStart;
  int? _selectionEnd;
  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;
  SelectionGeometry _selectionGeometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateSelectionRegistrarSubscription();
  }

  @override
  void detach() {
    _selectionRegistry?.clear(this, notify: false);
    _removeSelectionRegistrarSubscription();
    super.detach();
  }

  @override
  void dispose() {
    _selectionRegistry?.clear(this, notify: false);
    _removeSelectionRegistrarSubscription();
    _listeners.clear();
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    _layoutText();
    _updateSelectionGeometry();
    _updateSelectionRegistrarSubscription();
  }

  void _layoutText() {
    final double maxWidth =
        size.width.isFinite ? size.width : constraints.maxWidth;
    _textPainter.layout(
      maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _pushHandleLayer(
      context,
      offset,
      _startHandleLayerLink,
      _selectionGeometry.startSelectionPoint,
    );
    _pushHandleLayer(
      context,
      offset,
      _endHandleLayerLink,
      _selectionGeometry.endSelectionPoint,
    );
  }

  void _pushHandleLayer(
    PaintingContext context,
    Offset paintOffset,
    LayerLink? link,
    SelectionPoint? point,
  ) {
    if (link == null || point == null) {
      return;
    }
    context.pushLayer(
      LeaderLayer(link: link, offset: paintOffset + point.localPosition),
      (PaintingContext context, Offset offset) {},
      Offset.zero,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifySelectionListeners() {
    final List<VoidCallback> localListeners = List<VoidCallback>.of(_listeners);
    for (final VoidCallback listener in localListeners) {
      listener();
    }
  }

  @override
  SelectionGeometry get value => _selectionGeometry;

  void _updateSelectionGeometry() {
    final SelectionGeometry next = _computeSelectionGeometry();
    if (next == _selectionGeometry) {
      return;
    }
    _selectionGeometry = next;
    _updateSelectionRegistry();
    _notifySelectionListeners();
    markNeedsPaint();
  }

  void _updateSelectionRegistry() {
    final _MarkdownInlineSelectionRegistry? registry = _selectionRegistry;
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (registry == null ||
        start == null ||
        end == null ||
        start == end ||
        plainText.isEmpty) {
      registry?.clear(this);
      return;
    }
    final int localStart = (start < end ? start : end).clamp(
      0,
      plainText.length,
    );
    final int localEnd = (start < end ? end : start).clamp(
      localStart,
      plainText.length,
    );
    if (localStart >= localEnd) {
      registry.clear(this);
      return;
    }
    registry.update(
      this,
      displayRange: _MarkdownSelectionRange(
        start: absolutePlainTextStart + localStart,
        end: absolutePlainTextStart + localEnd,
      ),
      compactRange: _MarkdownSelectionRange(
        start: compactPlainTextStart + localStart,
        end: compactPlainTextStart + localEnd,
      ),
    );
  }

  SelectionGeometry _computeSelectionGeometry() {
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (plainText.isEmpty || start == null || end == null) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: plainText.isNotEmpty,
      );
    }

    final bool collapsed = start == end;
    final bool reversed = start > end;
    final int base = start.clamp(0, plainText.length);
    final int extent = end.clamp(0, plainText.length);
    final int rangeStart = base < extent ? base : extent;
    final int rangeEnd = base < extent ? extent : base;
    final Offset startOffset = _caretOffset(base);
    final Offset endOffset = _caretOffset(extent);
    final bool flipHandles = reversed != (textDirection == TextDirection.rtl);
    final TextSelectionHandleType startHandleType;
    final TextSelectionHandleType endHandleType;
    if (collapsed) {
      startHandleType = TextSelectionHandleType.collapsed;
      endHandleType = TextSelectionHandleType.collapsed;
    } else if (flipHandles) {
      startHandleType = TextSelectionHandleType.right;
      endHandleType = TextSelectionHandleType.left;
    } else {
      startHandleType = TextSelectionHandleType.left;
      endHandleType = TextSelectionHandleType.right;
    }
    final List<Rect> selectionRects = <Rect>[];
    if (!collapsed) {
      final TextSelection selection = TextSelection(
        baseOffset: rangeStart,
        extentOffset: rangeEnd,
      );
      for (final TextBox box in _textPainter.getBoxesForSelection(selection)) {
        selectionRects.add(box.toRect());
      }
    }
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startOffset,
        lineHeight: _textPainter.preferredLineHeight,
        handleType: startHandleType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endOffset,
        lineHeight: _textPainter.preferredLineHeight,
        handleType: endHandleType,
      ),
      selectionRects: selectionRects,
      status:
          collapsed ? SelectionStatus.collapsed : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  Offset _caretOffset(int offset) {
    return _textPainter.getOffsetForCaret(
      TextPosition(offset: offset.clamp(0, plainText.length)),
      Rect.fromLTWH(0, 0, 1, _textPainter.preferredLineHeight),
    );
  }

  @override
  SelectedContent? getSelectedContent() {
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (start == null || end == null || start == end || plainText.isEmpty) {
      return null;
    }
    final int rangeStart = start < end ? start : end;
    final int rangeEnd = start < end ? end : start;
    return SelectedContent(
      plainText: plainText.substring(
        rangeStart.clamp(0, plainText.length),
        rangeEnd.clamp(0, plainText.length),
      ),
    );
  }

  @override
  SelectedContentRange? getSelection() {
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (start == null || end == null) {
      return null;
    }
    return SelectedContentRange(startOffset: start, endOffset: end);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final int? oldStart = _selectionStart;
    final int? oldEnd = _selectionEnd;
    late final SelectionResult result;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final SelectionEdgeUpdateEvent edgeEvent =
            event as SelectionEdgeUpdateEvent;
        result = _updateSelectionEdge(
          edgeEvent.globalPosition,
          isEnd: event.type == SelectionEventType.endEdgeUpdate,
        );
      case SelectionEventType.clear:
        _clearSelection(notify: false);
        result = SelectionResult.none;
      case SelectionEventType.selectAll:
        _selectionStart = 0;
        _selectionEnd = plainText.length;
        result = SelectionResult.none;
      case SelectionEventType.selectWord:
        final SelectWordSelectionEvent wordEvent =
            event as SelectWordSelectionEvent;
        result = _selectWord(wordEvent.globalPosition);
      case SelectionEventType.selectParagraph:
        _selectionStart = 0;
        _selectionEnd = plainText.length;
        result = SelectionResult.end;
      case SelectionEventType.granularlyExtendSelection:
        final GranularlyExtendSelectionEvent extendEvent =
            event as GranularlyExtendSelectionEvent;
        result = _extendSelection(
          forward: extendEvent.forward,
          isEnd: extendEvent.isEnd,
          granularity: extendEvent.granularity,
        );
      case SelectionEventType.directionallyExtendSelection:
        final DirectionallyExtendSelectionEvent extendEvent =
            event as DirectionallyExtendSelectionEvent;
        result = _extendSelectionDirectionally(extendEvent);
    }
    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      _updateSelectionGeometry();
    }
    return result;
  }

  SelectionResult _updateSelectionEdge(Offset globalPosition,
      {required bool isEnd}) {
    final Offset localPosition = globalToLocal(globalPosition);
    final int offset = _positionForLocalOffset(localPosition);
    if (isEnd) {
      _selectionEnd = offset;
      _selectionStart ??= offset;
    } else {
      _selectionStart = offset;
      _selectionEnd ??= offset;
    }
    return _selectionResultForLocalPosition(localPosition);
  }

  int _positionForLocalOffset(Offset localPosition) {
    final Offset adjusted = SelectionUtils.adjustDragOffset(
      Offset.zero & size,
      localPosition,
      direction: textDirection,
    );
    final TextPosition position = _textPainter.getPositionForOffset(adjusted);
    return position.offset.clamp(0, plainText.length);
  }

  SelectionResult _selectionResultForLocalPosition(Offset localPosition) {
    if (plainText.isEmpty) {
      return SelectionResult.none;
    }
    return SelectionUtils.getResultBasedOnRect(
        Offset.zero & size, localPosition);
  }

  SelectionResult _selectWord(Offset globalPosition) {
    final Offset localPosition = globalToLocal(globalPosition);
    final int offset = _positionForLocalOffset(localPosition);
    final TextRange word =
        _textPainter.getWordBoundary(TextPosition(offset: offset));
    _selectionStart = word.start.clamp(0, plainText.length);
    _selectionEnd = word.end.clamp(_selectionStart!, plainText.length);
    return _selectionResultForLocalPosition(localPosition);
  }

  SelectionResult _extendSelection({
    required bool forward,
    required bool isEnd,
    required TextGranularity granularity,
  }) {
    final int step = switch (granularity) {
      TextGranularity.word => _wordStep(forward: forward, isEnd: isEnd),
      TextGranularity.document => plainText.length,
      _ => 1,
    };
    final int current = (isEnd ? _selectionEnd : _selectionStart) ??
        (forward ? 0 : plainText.length);
    final int next =
        (current + (forward ? step : -step)).clamp(0, plainText.length);
    if (isEnd) {
      _selectionEnd = next;
      _selectionStart ??= current;
    } else {
      _selectionStart = next;
      _selectionEnd ??= current;
    }
    return SelectionResult.end;
  }

  int _wordStep({required bool forward, required bool isEnd}) {
    final int current = (isEnd ? _selectionEnd : _selectionStart) ??
        (forward ? 0 : plainText.length);
    final TextRange word =
        _textPainter.getWordBoundary(TextPosition(offset: current));
    if (forward) {
      return (word.end - current).clamp(1, plainText.length);
    }
    return (current - word.start).clamp(1, plainText.length);
  }

  SelectionResult _extendSelectionDirectionally(
    DirectionallyExtendSelectionEvent event,
  ) {
    switch (event.direction) {
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.nextLine:
        return _extendSelection(
          forward: true,
          isEnd: event.isEnd,
          granularity: TextGranularity.character,
        );
      case SelectionExtendDirection.backward:
      case SelectionExtendDirection.previousLine:
        return _extendSelection(
          forward: false,
          isEnd: event.isEnd,
          granularity: TextGranularity.character,
        );
    }
  }

  void _clearSelection({required bool notify}) {
    _selectionStart = null;
    _selectionEnd = null;
    _selectionRegistry?.clear(this);
    if (notify) {
      _updateSelectionGeometry();
    }
  }

  @override
  int get contentLength => plainText.length;

  @override
  List<Rect> get boundingBoxes {
    if (!hasSize || plainText.isEmpty) {
      return <Rect>[Offset.zero & size];
    }
    final List<TextBox> boxes = _textPainter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plainText.length),
    );
    if (boxes.isEmpty) {
      return <Rect>[Offset.zero & size];
    }
    return boxes.map((TextBox box) => box.toRect()).toList(growable: false);
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandleLayerLink == startHandle &&
        _endHandleLayerLink == endHandle) {
      return;
    }
    _startHandleLayerLink = startHandle;
    _endHandleLayerLink = endHandle;
    if (attached) {
      markNeedsPaint();
    }
  }

  void _updateSelectionRegistrarSubscription() {
    final SelectionRegistrar? activeRegistrar = attached ? _registrar : null;
    final bool shouldRegister = plainText.isNotEmpty && activeRegistrar != null;
    if (_subscribedToSelectionRegistrar && !shouldRegister) {
      _registrar?.remove(this);
      _subscribedToSelectionRegistrar = false;
    } else if (!_subscribedToSelectionRegistrar && shouldRegister) {
      activeRegistrar.add(this);
      _subscribedToSelectionRegistrar = true;
    }
  }

  void _removeSelectionRegistrarSubscription() {
    if (!_subscribedToSelectionRegistrar) {
      return;
    }
    _registrar?.remove(this);
    _subscribedToSelectionRegistrar = false;
  }
}
