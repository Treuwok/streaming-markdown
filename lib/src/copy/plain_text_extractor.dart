part of '../render/view.dart';

String _extractSelectedPlainText({
  required _MarkdownSelectionProjection projection,
  required SelectedContent? selectedContent,
}) {
  final String selected =
      (selectedContent?.plainText ?? '').replaceAll('\r', '');
  if (selected.isEmpty) {
    return '';
  }
  return projection.plainTextForSelectedPlainText(selected);
}
