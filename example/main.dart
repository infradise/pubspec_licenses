import 'dart:io';

import 'package:pubspec_licenses/pubspec_licenses.dart';

Future<void> main() async {
  // Detect SPDX identifiers directly from license text:
  const sampleLicense = '''
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';

  final spdxIds = detectSpdxIdentifiers(sampleLicense);
  stdout.writeln('Detected SPDX identifiers: $spdxIds');

  // Crawl a project's pubspec.lock if present in the current directory:
  if (File('pubspec.lock').existsSync()) {
    final structure = await listDependencies(pubspecLockPath: 'pubspec.lock');
    stdout.writeln('Root package: ${structure.package.name}');
    for (final dep in structure.allDependencies) {
      stdout.writeln(' - ${dep.name} (${dep.version}): ${dep.spdxIdentifiers}');
    }
  }
}
