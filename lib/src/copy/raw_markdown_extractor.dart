part of '../render/view.dart';

String _extractSelectedRawMarkdown({
  required _MarkdownSelectionProjection projection,
  required String selectedPlainText,
}) {
  return projection.markdownForSelectedPlainText(
    selectedPlainText.replaceAll('\r', ''),
  );
}
