#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS_FILE="$ROOT_DIR/assets/wasm/streaming_markdown_wasm.js"
WASM_FILE="$ROOT_DIR/assets/wasm/streaming_markdown_wasm.wasm"
MANIFEST_FILE="$ROOT_DIR/assets/wasm/streaming_markdown_wasm.sha256"

# shellcheck source=tool/wasm_sources.sh
source "$ROOT_DIR/tool/wasm_sources.sh"

missing=0
for file in "$JS_FILE" "$WASM_FILE" "$MANIFEST_FILE"; do
  if [[ ! -s "$file" ]]; then
    echo "missing required web parser asset: ${file#$ROOT_DIR/}" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "Run tool/build_wasm.sh with Emscripten before publishing." >&2
  exit 1
fi

manifest_value() {
  local key="$1"
  local value
  value="$(
    awk -F= -v target="$key" '
      $1 == target {
        print substr($0, index($0, "=") + 1)
        exit
      }
    ' "$MANIFEST_FILE" | tr -d '\r'
  )"
  if [[ -z "$value" ]]; then
    echo "invalid web parser manifest: missing $key in ${MANIFEST_FILE#$ROOT_DIR/}" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

expected_source_sha="$(manifest_value source_sha256)"
expected_js_sha="$(manifest_value js_sha256)"
expected_wasm_sha="$(manifest_value wasm_sha256)"

actual_source_sha="$(streaming_markdown_wasm_source_digest "$ROOT_DIR")"
actual_js_sha="$(streaming_markdown_sha256 "$JS_FILE")"
actual_wasm_sha="$(streaming_markdown_sha256 "$WASM_FILE")"

stale=0
if [[ "$expected_source_sha" != "$actual_source_sha" ]]; then
  echo "stale web parser assets: source tree digest changed." >&2
  echo "  expected: $expected_source_sha" >&2
  echo "  actual:   $actual_source_sha" >&2
  stale=1
fi
if [[ "$expected_js_sha" != "$actual_js_sha" ]]; then
  echo "stale web parser assets: JS asset hash does not match manifest." >&2
  stale=1
fi
if [[ "$expected_wasm_sha" != "$actual_wasm_sha" ]]; then
  echo "stale web parser assets: WASM asset hash does not match manifest." >&2
  stale=1
fi

if [[ "$stale" -ne 0 ]]; then
  echo "Run tool/build_wasm.sh with Emscripten and commit the generated assets." >&2
  exit 1
fi

echo "WASM parser assets are present and up to date."
