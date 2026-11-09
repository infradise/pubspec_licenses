import 'package:pubspec_licenses/src/generate.dart';

/// CLI entry point for drop-in `dart run pubspec_licenses:generate` compatibility.
Future<int> main(List<String> args) => generate(args);
