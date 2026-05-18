# Publishing Checklist (pub.dev)

This file documents the release flow for `animated_streaming_markdown`.

## 1. Preconditions

- Ensure working tree is clean.
- Ensure Git user/email is configured.
- Ensure you are authenticated for pub.dev:

```bash
dart pub login
```

## 2. Versioning

- Update `pubspec.yaml` version.
- Update the matching iOS and macOS podspec versions.
- Add a matching entry in `CHANGELOG.md`.

## 3. Quality Gates

Run before publish:

```bash
dart format .
dart analyze
flutter test
cd example && flutter build web --base-href /demo/chat/ --output ../website/static/demo/chat
cd ../website && npm ci && npm run build
flutter pub publish --dry-run
```

Build and verify the Tree-sitter WASM asset before every release. The generated
files are committed and published with the package so app developers do not need
to add scripts, copy assets, or change web configuration:

```bash
tool/build_wasm.sh
tool/verify_wasm_assets.sh
```

`tool/verify_wasm_assets.sh` compares the generated asset manifest against the
current `packages/tree-sitter`, `packages/tree-sitter-markdown`, and `src`
source/header files. If those inputs change, rebuild and commit the WASM assets.

Published versions support Flutter web without consumer-side configuration. Do
not bundle local `.env` files in the example web build; cloud API keys should be
entered at runtime or provided with local `--dart-define` values during
development only.

For release CI on a platform where the bundled native library should be
available, require the native parser gate:

```bash
REQUIRE_STREAMING_MARKDOWN_NATIVE=true flutter test
```

Run the parser benchmark demo before publishing performance-sensitive changes:

```bash
cd example
flutter run -d macos lib/src/demos/parser_benchmark_demo.dart
```

Record the section count, iteration count, native availability, and median
times in the release notes when parser or renderer performance changes.

## 4. Publish

When dry-run has no warnings/errors:

```bash
flutter pub publish
```

## 5. Post Publish

- Tag release in Git.
- Push commit and tag.
- Create release notes from `CHANGELOG.md`.
