#!/usr/bin/env bash

streaming_markdown_sha256() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi

  echo "error: neither shasum nor sha256sum is available." >&2
  return 127
}

streaming_markdown_wasm_source_files() {
  local root_dir="$1"
  find \
    "$root_dir/packages/tree-sitter/lib/include" \
    "$root_dir/packages/tree-sitter/lib/src" \
    "$root_dir/packages/tree-sitter-markdown/tree-sitter-markdown/bindings/c" \
    "$root_dir/packages/tree-sitter-markdown/tree-sitter-markdown/src" \
    "$root_dir/packages/tree-sitter-markdown/tree-sitter-markdown-inline/bindings/c" \
    "$root_dir/packages/tree-sitter-markdown/tree-sitter-markdown-inline/src" \
    "$root_dir/src" \
    -type f \
    \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) \
    | LC_ALL=C sort
}

streaming_markdown_wasm_source_digest() {
  local root_dir="$1"
  streaming_markdown_wasm_source_files "$root_dir" \
    | while IFS= read -r file; do
        printf '%s  %s\n' "$(streaming_markdown_sha256 "$file")" "$file"
      done \
    | if command -v shasum >/dev/null 2>&1; then
        shasum -a 256
      else
        sha256sum
      fi \
    | awk '{print $1}'
}
