## 1.1.0

- **Safe Dart Codegen String Escaping (`renderDartLicensesFile`)**: Escaped backslashes (`\` -> `\\`), carriage returns, NUL bytes, `$` interpolation tokens (`\$foo` no longer unescapes into live `$foo` interpolation), and trailing quotes before closing `'''` / `"""` delimiters, plus added identifier collision deduplication for split SDK components.
- **Transitive Dev-Dependency Graph Pruning (`--no-dev-dependencies`)**: Traversed the runtime dependency graph via BFS from root runtime `dependencies` (`direct main` / non-dev `direct overridden`) so `generateDevDependencies: false` excludes transitive dev-only packages (such as `test_api`, `fake_async`, `lints`, and `build_daemon`) in addition to `direct dev` entries.
- **Root Package `--ignore` Parity in Dart Codegen**: Stripped root package `license`, `description`, `homepage`, `repository`, `authors`, and `spdxIdentifiers` when the root package name is passed to `--ignore` (`-i`), preventing proprietary application terms from being emitted into `oss_licenses.dart` while keeping `thisPackage` API-compatible.
- **Dart 3.5+ Pub Workspace Sub-Package CLI Resolution**: Updated `generate` CLI to traverse upward via `findPubspecLockFromDirectory` and resolve lockfile relative `path` dependencies against the workspace `pubspec.lock` root directory.
- **YAML, License Filename & SPDX `WITH` Hardening**: Fixed `MiniYamlParser` multiline quoted scalar trailing `# comment` handling and indented plain-scalar `: ` continuations, added `LICENCE` / `UNLICENSE` and case-insensitive license filename discovery, and preserved SPDX `WITH` exception clauses (such as `Apache-2.0 WITH LLVM-exception`).

## 1.0.1

- Added explicit `library;` directive in `lib/src/spdx_detector.dart` to satisfy `dangling_library_doc_comments` under `lints_core` static analysis.
- Refined package overview documentation and updated version examples in `README.md`.
- Updated the zero-dependency test suite to resolve local `pub-cache` paths and package version dynamically, and normalized path separator assertions on Windows.
- Added multi-OS (`Linux`, `macOS`, `Windows`) and `pana` preflight verification workflow in GitHub Actions.

## 1.0.0

- Initial release of `pubspec_licenses`.
- **Zero-Dependency Architecture**: 100% pure Dart implementation (`dart:io`, `dart:convert`, `dart:async`, `dart:core`) with zero runtime or transitive dependencies (no `pana`, `analyzer`, `yaml`, `path`, or `args` lock-in).
- **1:1 Drop-in Replacement for `dart_pubspec_licenses` v3.2.0**:
  - Identical `ProjectStructure`, `Package`, `LimitConcurrency`, and `listDependencies` API signatures.
  - Provides both `package:pubspec_licenses/pubspec_licenses.dart` and compatibility `package:pubspec_licenses/dart_pubspec_licenses.dart` barrel exports.
- **CLI & Code Generation (`pubspec_licenses` & `pubspec_licenses:generate`)**:
  - Generates `lib/oss_licenses.dart` out of the box (`dart run pubspec_licenses:generate`).
  - Supports JSON export (`-j` / `--json`), human-readable console summary (`-s` / `--summary`), custom output paths (`-o`), package ignore lists (`-i`), `--split-sdk-licenses`, and `--no-dev-dependencies`.
- **Pure Dart Engines**:
  - `MiniYamlParser` (`loadYaml`) supporting block scalars, flow collections, and lockfiles.
  - `detectSpdxIdentifiers` supporting 25+ standard SPDX licenses, multi-license blocks, and `SPDX-License-Identifier` tags.
  - Cross-platform POSIX/Windows path utilities (`path_utils`).
