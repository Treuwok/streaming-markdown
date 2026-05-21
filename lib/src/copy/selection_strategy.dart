/// Controls how selected markdown content is copied to the clipboard.
enum SelectionStrategy {
  /// Copy plain text with markdown formatting stripped.
  plain,

  /// Copy the original markdown source for the selected range.
  raw,

  /// Copy rich HTML with a plain-text fallback when supported.
  rich,
}
