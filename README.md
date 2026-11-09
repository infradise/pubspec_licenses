# pubspec_licenses

[![Pub Version](https://img.shields.io/pub/v/pubspec_licenses)](https://pub.dev/packages/pubspec_licenses)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)](https://pub.dev/packages/pubspec_licenses)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/infradise/pubspec_licenses/blob/main/LICENSE)

Zero-dependency Dart library and CLI to extract OSS licenses and SPDX identifiers from `pubspec.lock`. Drop-in replacement for `dart_pubspec_licenses`.

---

## Why `pubspec_licenses`?

`dart_pubspec_licenses` v3.x depends on `pana` to detect SPDX license identifiers, which transitively locks `analyzer` versions and pulls in 15+ heavy packages into your dependency tree (`analyzer`, `pana`, `test`, `test_core`, `coverage`, `frontend_server_client`, `webkit_inspection_protocol`, `shelf_static`, `shelf_packages_handler`, `cli_config`, `source_maps`, `source_map_stack_trace`, `node_preamble`, `retry`, `safe_url_check`).

When Flutter or Dart upgrades, `analyzer` version constraints inside `pana` frequently cause `pub get` version solving failures across projects and CI pipelines.

`pubspec_licenses` eliminates **all** external runtime and transitive dependencies (`dependencies: {}`) by implementing YAML/lockfile parsing, cross-platform path resolution, and SPDX license detection directly on the Dart standard library (`dart:io`, `dart:convert`, `dart:async`, `dart:core`).

### Dependency Tree Comparison (`dart pub deps`)

```text
# dart_pubspec_licenses v3.2.0
dart_pubspec_licenses 3.2.0
├── args 2.7.0
├── json_annotation 4.11.0
├── pana 0.22.20 -> analyzer, test, test_core, coverage, frontend_server_client,
│                   webkit_inspection_protocol, shelf_static, shelf_packages_handler,
│                   cli_config, source_maps, source_map_stack_trace, node_preamble,
│                   retry, safe_url_check, ... (60+ transitive packages)
├── path 1.9.0
└── yaml 3.1.3

# pubspec_licenses v1.0.0
Dart SDK 3.x
pubspec_licenses 1.0.0
(0 dependencies)
```

---

## Features

- **100% Zero Runtime & Transitive Dependencies**: Built exclusively with pure Dart SDK libraries (`dart:io`, `dart:convert`, `dart:async`, `dart:core`).
- **1:1 Drop-in Replacement for `dart_pubspec_licenses` v3.2.0**: Preserves exact `ProjectStructure`, `Package`, `LimitConcurrency`, and `listDependencies` API signatures, plus provides both `package:pubspec_licenses/pubspec_licenses.dart` and `package:pubspec_licenses/dart_pubspec_licenses.dart` barrel exports.
- **Built-in Pure-Dart SPDX License Detector**: Detects single and multi-license files (`MIT`, `MIT-0`, `BSD-3-Clause`, `BSD-2-Clause`, `BSD-4-Clause`, `BSD-1-Clause`, `0BSD`, `Apache-2.0`, `ISC`, `MPL-2.0`, `GPL-3.0-only`, `GPL-3.0-or-later`, `GPL-2.0-only`, `LGPL-3.0-only`, `LGPL-2.1-only`, `AGPL-3.0-only`, `EPL-2.0`, `EPL-1.0`, `Unlicense`, `CC0-1.0`, `CC-BY-4.0`, `Zlib`, `BSL-1.0`, `OFL-1.1`, `Unicode-DFS-2016`, `WTFPL`, and explicit `SPDX-License-Identifier:` tags).
- **Complete Package Source Coverage**: Resolves `hosted`, `git`, `path`, and `sdk` (Flutter/Dart SDK) packages, Pub workspaces (`workspace:`), `.dart_tool/package_config.json` fallback resolution, and multi-block SDK license splitting (`splitSdkLicenses: true`).

---

## Migration from `dart_pubspec_licenses`

### 1. Update `pubspec.yaml`

```yaml
dev_dependencies:
  # Replace dart_pubspec_licenses with pubspec_licenses:
  pubspec_licenses: ^1.0.0
```

*(Or place under `dependencies:` if your application imports `pubspec_licenses` at runtime.)*

### 2. Update Import (1-Line Change)

```dart
// Option A: Primary barrel
import 'package:pubspec_licenses/pubspec_licenses.dart';

// Option B: Compatibility barrel
import 'package:pubspec_licenses/dart_pubspec_licenses.dart';
```

All existing calls to `listDependencies(pubspecYamlPath: ...)` or `listDependencies(pubspecLockPath: ...)`, `ProjectStructure`, and `Package` work without any code changes.

### 3. CLI Code Generation

```sh
# Replaces: dart run dart_pubspec_licenses:generate
dart run pubspec_licenses:generate
```

---

## Library Usage

```dart
import 'package:pubspec_licenses/pubspec_licenses.dart';

Future<void> main() async {
  // Resolve using either pubspecYamlPath (v3.2.0 style) or pubspecLockPath:
  final project = await listDependencies(
    pubspecYamlPath: 'pubspec.yaml',
    splitSdkLicenses: false,
  );

  print('Root package: ${project.package.name} (${project.package.version})');
  print('Total dependencies: ${project.allDependencies.length}');

  for (final pkg in project.allDependencies) {
    final spdx = pkg.spdxIdentifiers.isEmpty
        ? 'UNKNOWN'
        : pkg.spdxIdentifiers.join(', ');
    print('- ${pkg.name} ${pkg.version ?? ""} [$spdx]');
  }
}
```

### Direct SPDX Detection

```dart
import 'package:pubspec_licenses/pubspec_licenses.dart';

void main() {
  final ids = detectSpdxIdentifiers('''
    Apache License
    Version 2.0, January 2004
    http://www.apache.org/licenses/
  ''');
  print(ids); // [Apache-2.0]
}
```

---

## CLI Usage

Both `pubspec_licenses` and `generate` executables are provided:

```sh
# Generate lib/oss_licenses.dart (default behavior, drop-in for dart_pubspec_licenses:generate)
dart run pubspec_licenses:generate

# Generate Dart license file at a custom path
dart run pubspec_licenses:generate -o lib/src/oss_licenses.dart

# Print human-readable dependency license summary to stdout
dart run pubspec_licenses:generate -s

# Output formatted JSON license metadata to stdout
dart run pubspec_licenses:generate --json -o -

# Write JSON license metadata to a file
dart run pubspec_licenses:generate -o assets/oss_licenses.json
```

### CLI Options

| Flag | Description |
| :--- | :--- |
| `-o, --output <path>` | Output file path (defaults to `lib/oss_licenses.dart`; use `-` for `stdout`; infers JSON if `.json` and Dart if `.dart`) |
| `-p, --project-root <dir>` | Project root directory containing `pubspec.yaml` / `pubspec.lock` |
| `--pubspec-lock <path>` | Explicit path to `pubspec.lock` (defaults to `./pubspec.lock`) |
| `--flutter-dir <path>` | Path to Flutter SDK root directory (or uses `FLUTTER_ROOT`) |
| `--pub-cache-dir <path>` | Path to Pub cache directory (or uses `PUB_CACHE`) |
| `-i, --ignore <pkgs>` | Comma-separated or repeatable list of package names to exclude |
| `-j, --json` | Output license metadata in JSON format |
| `--dart` | Output license metadata as a Dart source file (`oss_licenses.dart` format) |
| `-s, --summary` | Print human-readable dependency license summary to `stdout` |
| `--split-sdk-licenses` | Split bundled SDK licenses (`sky_engine`, etc.) into component entries |
| `--no-dev-dependencies` | Exclude direct `dev_dependencies` from output |
| `-h, --help` | Show CLI usage information |

---

## Acknowledgements & Attribution

This package is inspired by and designed for drop-in compatibility with [`dart_pubspec_licenses`](https://github.com/espresso3389/flutter_oss_licenses/tree/master/packages/dart_pubspec_licenses), part of the [`flutter_oss_licenses`](https://github.com/espresso3389/flutter_oss_licenses) project created by [Takashi Kawasaki (espresso3389)](https://github.com/espresso3389).

`pubspec_licenses` is an independent, clean-room zero-dependency implementation engineered to preserve full API compatibility with `dart_pubspec_licenses` v3.2.0 while removing the external `pana`, `analyzer`, `yaml`, `path`, and `args` dependency chain.

---

## License

Licensed under the Apache License, Version 2.0.
Copyright 2026 Infradise Inc. See [LICENSE](LICENSE) for full details.
