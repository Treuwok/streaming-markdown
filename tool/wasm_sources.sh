#!/usr/bin/env bash

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
        shasum -a 256 "$file"
      done \
    | shasum -a 256 \
    | awk '{print $1}'
}
