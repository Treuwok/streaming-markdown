#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/wasm"
BUILD_DIR="$ROOT_DIR/.dart_tool/streaming_markdown_wasm"
MANIFEST_FILE="$OUT_DIR/streaming_markdown_wasm.sha256"
EMCC_BIN="${EMCC:-emcc}"
EMXX_BIN="${EMXX:-em++}"

# shellcheck source=tool/wasm_sources.sh
source "$ROOT_DIR/tool/wasm_sources.sh"

if ! command -v "$EMCC_BIN" >/dev/null 2>&1; then
  echo "error: emcc was not found. Install and activate Emscripten, then rerun:" >&2
  echo "  tool/build_wasm.sh" >&2
  exit 127
fi

if ! command -v "$EMXX_BIN" >/dev/null 2>&1; then
  echo "error: em++ was not found. Install and activate Emscripten, then rerun:" >&2
  echo "  tool/build_wasm.sh" >&2
  exit 127
fi

mkdir -p "$OUT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

COMMON_FLAGS=(
  -O3
  -I"$ROOT_DIR/packages/tree-sitter/lib/include"
  -I"$ROOT_DIR/packages/tree-sitter/lib/src"
)

C_SOURCES=(
  "$ROOT_DIR/packages/tree-sitter/lib/src/alloc.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/get_changed_ranges.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/language.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/lexer.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/node.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/parser.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/point.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/query.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/stack.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/subtree.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/tree.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/tree_cursor.c"
  "$ROOT_DIR/packages/tree-sitter/lib/src/wasm_store.c"
  "$ROOT_DIR/packages/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"
  "$ROOT_DIR/packages/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"
  "$ROOT_DIR/packages/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"
  "$ROOT_DIR/packages/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"
  "$ROOT_DIR/src/streaming_markdown.c"
)

CPP_SOURCES=(
  "$ROOT_DIR/src/streaming_markdown_incremental.cpp"
  "$ROOT_DIR/src/streaming_markdown_rope.cpp"
  "$ROOT_DIR/src/streaming_markdown_ts_parser.cpp"
  "$ROOT_DIR/src/streaming_markdown_web.cpp"
)

OBJECTS=()

for source in "${C_SOURCES[@]}"; do
  object="$BUILD_DIR/$(basename "$source" .c)_$(printf '%s' "$source" | if command -v shasum >/dev/null 2>&1; then shasum; else sha256sum; fi | cut -d' ' -f1).o"
  "$EMCC_BIN" "${COMMON_FLAGS[@]}" -c "$source" -o "$object"
  OBJECTS+=("$object")
done

for source in "${CPP_SOURCES[@]}"; do
  object="$BUILD_DIR/$(basename "$source" .cpp).o"
  "$EMXX_BIN" "${COMMON_FLAGS[@]}" -std=c++17 -fno-exceptions -fno-rtti -c "$source" -o "$object"
  OBJECTS+=("$object")
done

"$EMXX_BIN" \
  -O3 \
  "${OBJECTS[@]}" \
  -s WASM=1 \
  -s MODULARIZE=1 \
  -s EXPORT_NAME=createStreamingMarkdownWasmModule \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s ENVIRONMENT=web,worker \
  -s EXPORTED_RUNTIME_METHODS='["cwrap","UTF8ToString"]' \
  -s EXPORTED_FUNCTIONS='["_streaming_markdown_web_parse_blocks_json","_streaming_markdown_web_parse_inlines_json","_streaming_markdown_web_block_nodes_json"]' \
  -o "$OUT_DIR/streaming_markdown_wasm.js"

echo "Wrote $OUT_DIR/streaming_markdown_wasm.js"
echo "Wrote $OUT_DIR/streaming_markdown_wasm.wasm"

SOURCE_SHA="$(streaming_markdown_wasm_source_digest "$ROOT_DIR")"
JS_SHA="$(streaming_markdown_sha256 "$OUT_DIR/streaming_markdown_wasm.js")"
WASM_SHA="$(streaming_markdown_sha256 "$OUT_DIR/streaming_markdown_wasm.wasm")"
{
  echo "source_sha256=$SOURCE_SHA"
  echo "js_sha256=$JS_SHA"
  echo "wasm_sha256=$WASM_SHA"
} > "$MANIFEST_FILE"
echo "Wrote $MANIFEST_FILE"
