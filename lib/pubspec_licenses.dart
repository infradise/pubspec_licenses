/// A zero-dependency library for extracting OSS license metadata and SPDX
/// identifiers from Dart and Flutter packages.
///
/// Drop-in replacement for `dart_pubspec_licenses` v3.2.0 without `pana` or
/// `analyzer` dependencies.
library;

export 'src/generate.dart';
export 'src/license_crawler.dart';
export 'src/limit_concurrency.dart';
export 'src/mini_yaml_parser.dart';
export 'src/package.dart';
export 'src/path_utils.dart';
export 'src/project_structure.dart';
export 'src/spdx_detector.dart';
