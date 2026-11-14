import 'dart:convert';
import 'dart:io';

import 'package:pubspec_licenses/dart_pubspec_licenses.dart' as compat;
import 'package:pubspec_licenses/pubspec_licenses.dart';

import '../bin/generate.dart' as generate_cli;
import '../bin/pubspec_licenses.dart' as main_cli;

int _passed = 0;
int _failed = 0;

Future<void> _test(String name, Future<void> Function() body) async {
  try {
    await body();
    _passed++;
    stdout.writeln('  [PASS] $name');
  } catch (e, st) {
    _failed++;
    stderr.writeln('  [FAIL] $name');
    stderr.writeln('         $e');
    stderr.writeln('         $st');
  }
}

void _expectEqual(Object? actual, Object? expected, [String? reason]) {
  if (actual != expected) {
    throw AssertionError(
      'Expected: $expected\n  Actual: $actual${reason != null ? '\n  Reason: $reason' : ''}',
    );
  }
}

void _expectListEqual<T>(List<T> actual, List<T> expected, [String? reason]) {
  if (actual.length != expected.length) {
    throw AssertionError(
      'List length mismatch. Expected $expected (${expected.length}), got $actual (${actual.length})${reason != null ? ' ($reason)' : ''}',
    );
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      throw AssertionError(
        'Element [$i] mismatch. Expected ${expected[i]}, got ${actual[i]} in $actual${reason != null ? ' ($reason)' : ''}',
      );
    }
  }
}

void _expectTrue(bool condition, [String? reason]) {
  if (!condition) {
    throw AssertionError('Expected true${reason != null ? ': $reason' : ''}');
  }
}

Future<void> main() async {
  stdout.writeln('=== pubspec_licenses Zero-Dependency Test Suite ===\n');

  stdout.writeln('1. PathUtils Tests');
  await _runPathUtilsTests();

  stdout.writeln('\n2. MiniYamlParser Edge-Case Tests');
  await _runMiniYamlParserTests();

  stdout.writeln('\n3. SpdxDetector Exhaustive Tests');
  await _runSpdxDetectorTests();

  stdout.writeln('\n4. API Parity, Models & Concurrency Tests');
  await _runApiParityAndModelTests();

  stdout.writeln('\n5. End-to-End Crawler, SDK Splitting & Real Cache Tests');
  await _runEndToEndTests();

  stdout.writeln('\n6. Real-World Pub Cache Corpus Stress Tests');
  await _runRealPubCacheCorpusTests();

  stdout.writeln(
    '\n===================================================\n'
    'Summary: $_passed passed, $_failed failed (Total: ${_passed + _failed})\n'
    '===================================================',
  );

  if (_failed > 0) {
    exitCode = 1;
  }
}

Future<void> _runPathUtilsTests() async {
  final sep = Platform.pathSeparator;

  await _test('1.1 join combines relative and nested segments', () async {
    _expectEqual(join('a', 'b', 'c'), 'a${sep}b${sep}c');
    _expectEqual(join('/usr/', '/local/', 'bin'), '/local/bin');
    _expectEqual(join('/usr/', 'local/', 'bin'), '/usr/local/bin');
    _expectEqual(join('a', '', 'b'), 'a${sep}b');
    _expectEqual(
      joinAll(<String>['p1', 'p2', 'p3', 'p4']),
      'p1${sep}p2${sep}p3${sep}p4',
    );
  });

  await _test('1.2 normalize resolves . and .. segments', () async {
    _expectEqual(normalize('a/b/../c/./d//e'), 'a${sep}c${sep}d${sep}e');
    _expectEqual(normalize('/a/b/../../c'), '${sep}c');
    _expectEqual(normalize('/../../a'), '${sep}a');
    _expectEqual(normalize('../a/b/../c'), '..${sep}a${sep}c');
    _expectEqual(normalize(''), '.');
    _expectEqual(normalize('.'), '.');
  });

  await _test('1.3 normalize handles Windows drive letters and UNC paths',
      () async {
    _expectEqual(
      normalize(r'C:\Users\dev\..\project\.\pubspec.yaml'),
      r'C:\Users\project\pubspec.yaml',
    );
    _expectEqual(normalize('C:'), 'C:.');
    _expectEqual(
      normalize(r'\\server\share\dir\..\file.txt'),
      r'\\server\share\file.txt',
    );
  });

  await _test(
      '1.4 dirname and basename extract parent and leaf on POSIX and Windows',
      () async {
    _expectEqual(dirname('/path/to/pubspec.yaml'), '/path/to');
    _expectEqual(basename('/path/to/pubspec.yaml'), 'pubspec.yaml');
    _expectEqual(dirname('pubspec.yaml'), '.');
    _expectEqual(basename('/a/b/c/'), 'c');
    _expectEqual(dirname('/a'), sep);
    _expectEqual(dirname('/'), sep);
    _expectEqual(dirname(r'C:\src\app\pubspec.lock'), r'C:\src\app');
    _expectEqual(basename(r'C:\src\app\pubspec.lock'), 'pubspec.lock');
  });

  await _test(
      '1.5 extension, basenameWithoutExtension, isAbsolute, and absolute',
      () async {
    _expectEqual(extension('oss_licenses.json'), '.json');
    _expectEqual(basenameWithoutExtension('oss_licenses.json'), 'oss_licenses');
    _expectEqual(extension('LICENSE'), '');
    _expectEqual(extension('.gitignore'), '');
    _expectTrue(isAbsolute('/usr/local'));
    _expectTrue(isAbsolute(r'C:\Windows\System32'));
    _expectTrue(isRelative('lib/src/package.dart'));
    _expectTrue(isAbsolute(absolute('relative/file.txt')));
  });
}

Future<void> _runMiniYamlParserTests() async {
  await _test(
      '2.1 parses complex pubspec.yaml with multiline scalars, inline maps, lists',
      () async {
    const yamlText = '''
name: sample_app
description: >-
  A multi-line folded description
  for testing MiniYamlParser.
version: 2.3.1+4
homepage: https://example.com/sample_app
repository: "https://github.com/example/sample_app"
authors:
  - Alice <alice@example.com>
  - "Bob <bob@example.com>"
topics: [license, oss, spdx]
environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.10.0"
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  local_pkg:
    path: ../local_pkg
  git_pkg:
    git:
      url: https://github.com/example/git_pkg.git
      ref: main
      path: packages/sub
dev_dependencies: {}
''';
    final map = MiniYamlParser.parseMap(yamlText);
    _expectEqual(map['name'], 'sample_app');
    _expectEqual(
      map['description'],
      'A multi-line folded description for testing MiniYamlParser.',
    );
    _expectEqual(map['version'], '2.3.1+4');
    _expectEqual(map['homepage'], 'https://example.com/sample_app');
    _expectEqual(map['repository'], 'https://github.com/example/sample_app');
    _expectListEqual(
      (map['authors'] as List).cast<String>(),
      <String>['Alice <alice@example.com>', 'Bob <bob@example.com>'],
    );
    _expectListEqual(
      (map['topics'] as List).cast<String>(),
      <String>['license', 'oss', 'spdx'],
    );
    final env = map['environment'] as Map;
    _expectEqual(env['sdk'], '>=3.0.0 <4.0.0');
    final deps = map['dependencies'] as Map;
    _expectEqual((deps['flutter'] as Map)['sdk'], 'flutter');
    _expectEqual(deps['http'], '^1.2.0');
    _expectEqual((deps['local_pkg'] as Map)['path'], '../local_pkg');
    final gitMap = (deps['git_pkg'] as Map)['git'] as Map;
    _expectEqual(gitMap['url'], 'https://github.com/example/git_pkg.git');
    _expectEqual(gitMap['path'], 'packages/sub');
    _expectTrue((map['dev_dependencies'] as Map).isEmpty);
  });

  await _test('2.2 parses real-world pubspec.lock structure', () async {
    const lockText = '''
# Generated by pub
packages:
  collection:
    dependency: "direct main"
    description:
      name: collection
      sha256: "abc123456789"
      url: "https://pub.dev"
    source: hosted
    version: "1.18.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''';
    final parsed = MiniYamlParser.parseMap(lockText);
    final packages = parsed['packages'] as Map;
    final collection = packages['collection'] as Map;
    _expectEqual(collection['dependency'], 'direct main');
    _expectEqual(collection['source'], 'hosted');
    _expectEqual(collection['version'], '1.18.0');
    _expectEqual((collection['description'] as Map)['url'], 'https://pub.dev');
    _expectEqual((parsed['sdks'] as Map)['dart'], '>=3.0.0 <4.0.0');
  });

  await _test(
      '2.3 parses literal block scalars (|, |-, |+) and folded (> and >-)',
      () async {
    const yaml = '''
literal_clip: |
  Line 1
  Line 2

literal_strip: |-
  Strip 1
  Strip 2

folded_paragraphs: >
  First paragraph line A
  line B.

  Second paragraph.
''';
    final map = MiniYamlParser.parseMap(yaml);
    _expectEqual(map['literal_clip'], 'Line 1\nLine 2');
    _expectEqual(map['literal_strip'], 'Strip 1\nStrip 2');
    _expectEqual(
      map['folded_paragraphs'],
      'First paragraph line A line B.\nSecond paragraph.',
    );
  });

  await _test(
      '2.4 parses quoted strings with escaped characters and single-quote doubling',
      () async {
    const yaml = r'''
double_escaped: "Hello \"World\"\nNext\tTab\\Slash\u0041"
single_escaped: 'It''s a single-quoted string with # not a comment'
url_with_colon: https://pub.dev/packages/pubspec_licenses # trailing comment
''';
    final map = MiniYamlParser.parseMap(yaml);
    _expectEqual(map['double_escaped'], 'Hello "World"\nNext\tTab\\SlashA');
    _expectEqual(
      map['single_escaped'],
      "It's a single-quoted string with # not a comment",
    );
    _expectEqual(
      map['url_with_colon'],
      'https://pub.dev/packages/pubspec_licenses',
    );
  });

  await _test(
      '2.5 parses flow maps, flow lists, CRLF line endings, and UTF-8 BOM',
      () async {
    const yaml = '\uFEFFflow_map: {path: ../foo, relative: true, count: 42}\r\n'
        'flow_list: [alpha, "beta, gamma", 123, false]\r\n'
        'empty_map: {}\r\n'
        'empty_list: []\r\n';
    final map = MiniYamlParser.parseMap(yaml);
    final flowMap = map['flow_map'] as Map;
    _expectEqual(flowMap['path'], '../foo');
    _expectEqual(flowMap['relative'], true);
    _expectEqual(flowMap['count'], 42);
    final flowList = map['flow_list'] as List;
    _expectListEqual(flowList, <dynamic>['alpha', 'beta, gamma', 123, false]);
    _expectTrue((map['empty_map'] as Map).isEmpty);
    _expectTrue((map['empty_list'] as List).isEmpty);
  });

  await _test(
      '2.6 parses primitives, nulls, sequences of maps, and JSON input via loadYaml',
      () async {
    const yaml = '''
---
int_val: 100
float_val: 3.14
bool_true: true
bool_false: FALSE
null_empty:
null_tilde: ~
items:
  - name: item1
    enabled: true
  - name: item2
    enabled: false
...
''';
    final map = loadYaml(yaml) as Map<String, dynamic>;
    _expectEqual(map['int_val'], 100);
    _expectEqual(map['float_val'], 3.14);
    _expectEqual(map['bool_true'], true);
    _expectEqual(map['bool_false'], false);
    _expectEqual(map['null_empty'], null);
    _expectEqual(map['null_tilde'], null);
    final items = map['items'] as List;
    _expectEqual(items.length, 2);
    _expectEqual((items[0] as Map)['name'], 'item1');
    _expectEqual((items[1] as Map)['enabled'], false);

    final jsonMap = loadYaml('{"flutterVersion": "3.24.0"}') as Map;
    _expectEqual(jsonMap['flutterVersion'], '3.24.0');
  });
}

Future<void> _runSpdxDetectorTests() async {
  await _test('3.1 detects MIT and MIT-0 licenses', () async {
    const mit = '''
MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
''';
    _expectListEqual(detectSpdxIdentifiers(mit), <String>['MIT']);

    const mit0 = '''
MIT No Attribution
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';
    _expectListEqual(detectSpdxIdentifiers(mit0), <String>['MIT-0']);
  });

  await _test(
      '3.2 detects BSD-3-Clause, BSD-2-Clause, BSD-4-Clause, BSD-1-Clause',
      () async {
    const bsd3 = '''
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.
''';
    _expectListEqual(detectSpdxIdentifiers(bsd3), <String>['BSD-3-Clause']);

    const bsd2 = '''
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation.
''';
    _expectListEqual(detectSpdxIdentifiers(bsd2), <String>['BSD-2-Clause']);

    const bsd4 = '''
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice.
3. All advertising materials mentioning features or use of this software
   must display the following acknowledgement: This product includes software.
4. Neither the name of the University nor the names of its contributors
   may be used to endorse or promote products derived from this software.
''';
    _expectListEqual(detectSpdxIdentifiers(bsd4), <String>['BSD-4-Clause']);

    const bsd1 = '''
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
''';
    _expectListEqual(detectSpdxIdentifiers(bsd1), <String>['BSD-1-Clause']);
  });

  await _test('3.3 detects Apache-2.0, ISC, and 0BSD', () async {
    const apache2 = '''
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/
''';
    _expectListEqual(detectSpdxIdentifiers(apache2), <String>['Apache-2.0']);

    const isc = '''
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.
''';
    _expectListEqual(detectSpdxIdentifiers(isc), <String>['ISC']);

    const zeroBsd = '''
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.
THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES.
''';
    _expectListEqual(detectSpdxIdentifiers(zeroBsd), <String>['0BSD']);
  });

  await _test('3.4 detects MPL-2.0 and GPL-3.0-only', () async {
    _expectListEqual(
      detectSpdxIdentifiers('Mozilla Public License Version 2.0'),
      <String>['MPL-2.0'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007'),
      <String>['GPL-3.0-only'],
    );
  });

  await _test('3.5 detects GPL-3.0-or-later and GPL-2.0-only', () async {
    _expectListEqual(
      detectSpdxIdentifiers(
        'GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.',
      ),
      <String>['GPL-3.0-or-later'],
    );
    _expectListEqual(
      detectSpdxIdentifiers('GNU GENERAL PUBLIC LICENSE Version 2, June 1991'),
      <String>['GPL-2.0-only'],
    );
  });

  await _test('3.6 detects LGPL-3.0-only, LGPL-2.1-only, and AGPL-3.0-only',
      () async {
    _expectListEqual(
      detectSpdxIdentifiers(
          'GNU Lesser General Public License Version 3, 29 June 2007'),
      <String>['LGPL-3.0-only'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'GNU Lesser General Public License Version 2.1, February 1999'),
      <String>['LGPL-2.1-only'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007'),
      <String>['AGPL-3.0-only'],
    );
  });

  await _test('3.7 detects EPL-2.0 and EPL-1.0', () async {
    _expectListEqual(
      detectSpdxIdentifiers('Eclipse Public License - v 2.0'),
      <String>['EPL-2.0'],
    );
    _expectListEqual(
      detectSpdxIdentifiers('Eclipse Public License - v 1.0'),
      <String>['EPL-1.0'],
    );
  });

  await _test('3.8 detects Unlicense, CC0-1.0, and CC-BY-4.0', () async {
    _expectListEqual(
      detectSpdxIdentifiers(
        'This is free and unencumbered software released into the public domain.',
      ),
      <String>['Unlicense'],
    );
    _expectListEqual(
      detectSpdxIdentifiers('CC0 1.0 Universal'),
      <String>['CC0-1.0'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'Creative Commons Attribution 4.0 International Public License'),
      <String>['CC-BY-4.0'],
    );
  });

  await _test('3.9 detects Zlib and BSL-1.0 (Boost Software License 1.0)',
      () async {
    _expectListEqual(
      detectSpdxIdentifiers(
        'The origin of this software must not be misrepresented; you must not claim that you wrote the original software. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software. This notice may not be removed or altered from any source distribution.',
      ),
      <String>['Zlib'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'Boost Software License - Version 1.0 - August 17th, 2003'),
      <String>['BSL-1.0'],
    );
  });

  await _test('3.10 detects OFL-1.1, Unicode-DFS-2016, and WTFPL', () async {
    _expectListEqual(
      detectSpdxIdentifiers(
          'SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007'),
      <String>['OFL-1.1'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'UNICODE, INC. LICENSE AGREEMENT - DATA FILES AND SOFTWARE'),
      <String>['Unicode-DFS-2016'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          'DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE Version 2'),
      <String>['WTFPL'],
    );
  });

  await _test(
      '3.11 detects explicit SPDX-License-Identifier headers (single and compound)',
      () async {
    _expectListEqual(
      detectSpdxIdentifiers('SPDX-License-Identifier: BSD-3-Clause'),
      <String>['BSD-3-Clause'],
    );
    _expectListEqual(
      detectSpdxIdentifiers(
          '// SPDX-License-Identifier: (MIT OR Apache-2.0) # comment'),
      <String>['MIT', 'Apache-2.0'],
    );
  });

  await _test('3.12 detects multi-license texts separated by ---', () async {
    const multiDash = '''
Apache License, Version 2.0
http://www.apache.org/licenses/LICENSE-2.0
--------------------------------------------------------------------------------
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
Neither the name of the project nor the names of its contributors may be used
to endorse or promote products derived from this software.
''';
    _expectListEqual(
      detectSpdxIdentifiers(multiDash),
      <String>['Apache-2.0', 'BSD-3-Clause'],
    );
  });

  await _test('3.13 detects multi-license texts separated by ====', () async {
    const multiEquals = '''
MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, without restriction,
including without limitation the rights to use, copy, modify.
================================================================================
Boost Software License - Version 1.0 - August 17th, 2003
''';
    _expectListEqual(
      detectSpdxIdentifiers(multiEquals),
      <String>['MIT', 'BSL-1.0'],
    );
  });

  await _test(
      '3.14 returns empty list [] for empty or whitespace license strings',
      () async {
    _expectListEqual(detectSpdxIdentifiers(''), <String>[]);
    _expectListEqual(detectSpdxIdentifiers('   \n\t  '), <String>[]);
  });

  await _test('3.15 returns empty list [] for custom/unrecognized license text',
      () async {
    _expectListEqual(
      detectSpdxIdentifiers(
          'All rights reserved. Proprietary internal software.'),
      <String>[],
    );
  });

  await _test(
      '3.16 MPL-2.0 with Section 1.12 "Secondary License" (GPL/LGPL/AGPL) detects strictly [MPL-2.0]',
      () async {
    const mpl2WithSecondary = '''
Mozilla Public License Version 2.0
==================================

1. Definitions
--------------

1.12. "Secondary License"
    means either the GNU General Public License, Version 2.0, the GNU
    Lesser General Public License, Version 2.1, the GNU Affero General
    Public License, Version 3.0, or any later versions of those
    licenses.

2. License Grants and Conditions
--------------------------------

Each Contributor hereby grants You a world-wide, royalty-free,
non-exclusive license under intellectual property rights.

Exhibit A - Source Code Form License Notice
-------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
''';
    _expectListEqual(
      detectSpdxIdentifiers(mpl2WithSecondary),
      <String>['MPL-2.0'],
    );
  });
}

Future<void> _runApiParityAndModelTests() async {
  await _test(
      '4.1 Package constructor, getters, toJson, fromMap, fromJson, copyWith parity',
      () async {
    final pkg = Package(
      directory: Directory('/tmp/demo_pkg'),
      pubspec: <String, dynamic>{'name': 'demo_pkg', 'version': '1.0.0'},
      name: 'demo_pkg',
      description: 'Demo package description',
      homepage: 'https://example.com',
      repository: 'https://github.com/example/demo_pkg',
      authors: const <String>['Author One'],
      version: '1.0.0',
      license: 'MIT License',
      spdxIdentifiers: const <String>['MIT'],
      isMarkdown: true,
      isSdk: false,
      isDirectDependency: true,
      dependencies: <Package>[],
      devDependencies: <Package>[],
    );

    final sep = Platform.pathSeparator;
    _expectEqual(pkg.pubspecYamlPath, '/tmp/demo_pkg${sep}pubspec.yaml');
    _expectEqual(
        pkg.getFilePath('LICENSE.md'), '/tmp/demo_pkg${sep}LICENSE.md');

    final json = pkg.toJson();
    _expectEqual(json['name'], 'demo_pkg');
    _expectEqual(json['description'], 'Demo package description');
    _expectEqual(json['homepage'], 'https://example.com');
    _expectEqual(json['repository'], 'https://github.com/example/demo_pkg');
    _expectListEqual(json['authors'] as List<String>, <String>['Author One']);
    _expectEqual(json['version'], '1.0.0');
    _expectEqual(json['license'], 'MIT License');
    _expectListEqual(json['spdxIdentifiers'] as List<String>, <String>['MIT']);
    _expectEqual(json['isMarkdown'], true);
    _expectEqual(json['isSdk'], false);
    _expectEqual(json['isDirectDependency'], true);

    final overrideJson = pkg.toJson(isDirectDependency: false);
    _expectEqual(overrideJson['isDirectDependency'], false);

    final fromJsonPkg = Package.fromJson(json);
    _expectEqual(fromJsonPkg.name, 'demo_pkg');
    _expectEqual(fromJsonPkg.isDirectDependency, true);
    _expectListEqual(fromJsonPkg.spdxIdentifiers, <String>['MIT']);

    final copied = pkg.copyWith(version: '2.0.0', isDirectDependency: false);
    _expectEqual(copied.version, '2.0.0');
    _expectEqual(copied.isDirectDependency, false);
    _expectEqual(copied.name, 'demo_pkg');
  });

  await _test('4.2 ProjectStructure fields, getters, and toJson parity',
      () async {
    final depPkg =
        Package(name: 'dep_a', description: 'Dep A', version: '0.1.0');
    final devDepPkg =
        Package(name: 'dev_b', description: 'Dev B', version: '0.2.0');
    final rootPkg = Package(
      name: 'root_app',
      description: 'Root',
      dependencies: <Package>[depPkg],
      devDependencies: <Package>[devDepPkg],
    );
    final structure = ProjectStructure(
      package: rootPkg,
      allDependencies: <Package>[depPkg, devDepPkg],
      pubspecLockPath: '/tmp/root_app/pubspec.lock',
    );

    _expectEqual(structure.package.name, 'root_app');
    _expectEqual(structure.pubspecLockPath, '/tmp/root_app/pubspec.lock');
    _expectEqual(structure.dependencies.length, 1);
    _expectEqual(structure.devDependencies.length, 1);
    final json = structure.toJson();
    _expectEqual((json['package'] as Map)['name'], 'root_app');
    _expectEqual((json['allDependencies'] as List).length, 2);
  });

  await _test(
      '4.3 removePrefix and gitRepoName helpers match dart_pubspec_licenses v3.2.0',
      () async {
    _expectEqual(removePrefix('https://pub.dev'), 'pub.dev');
    _expectEqual(removePrefix('http://pub.dartlang.org'), 'pub.dartlang.org');
    _expectEqual(removePrefix('custom.host'), 'custom.host');
    _expectEqual(
      gitRepoName('https://github.com/infradise/pubspec_licenses.git'),
      'pubspec_licenses',
    );
    _expectEqual(
      gitRepoName('https://github.com/infradise/pubspec_licenses'),
      'pubspec_licenses',
    );
    _expectEqual(
      gitRepoName('git@github.com:infradise/pubspec_licenses.git'),
      'pubspec_licenses',
    );
  });

  await _test('4.4 LimitConcurrency restricts active concurrent tasks',
      () async {
    final limiter = LimitConcurrency(2);
    var active = 0;
    var maxObserved = 0;

    final futures = List<Future<int>>.generate(8, (i) {
      return limiter.run(() async {
        active++;
        if (active > maxObserved) maxObserved = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return i * 2;
      });
    });

    final results = await Future.wait(futures);
    _expectEqual(maxObserved, 2);
    _expectListEqual(results, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
  });
}

String? _resolveHostedPubCachePath() {
  final env = Platform.environment;
  final pubCache = env['PUB_CACHE'];
  final baseDir = (pubCache != null && pubCache.isNotEmpty)
      ? pubCache
      : Platform.isWindows
          ? (env['LOCALAPPDATA'] != null
              ? join(env['LOCALAPPDATA']!, 'Pub', 'Cache')
              : null)
          : (env['HOME'] != null ? join(env['HOME']!, '.pub-cache') : null);
  if (baseDir == null) {
    return null;
  }
  return join(baseDir, 'hosted', 'pub.dev');
}

Future<void> _runEndToEndTests() async {
  await _test(
      '5.1 listDependencies resolves hosted, path, git, and sdk packages with full graph',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_e2e_');
    try {
      final appDir = Directory(join(tempRoot.path, 'app'))
        ..createSync(recursive: true);
      final pubCacheDir = Directory(join(tempRoot.path, 'pub-cache'))
        ..createSync(recursive: true);
      final flutterDir = Directory(join(tempRoot.path, 'flutter'))
        ..createSync(recursive: true);
      final localPkgDir = Directory(join(tempRoot.path, 'local_pkg'))
        ..createSync(recursive: true);

      // 1. Hosted package (foo_hosted -> depends on bar_transitive)
      final fooHostedDir = Directory(
        join(pubCacheDir.path, 'hosted', 'pub.dev', 'foo_hosted-1.2.3'),
      )..createSync(recursive: true);
      await File(join(fooHostedDir.path, 'pubspec.yaml')).writeAsString('''
name: foo_hosted
description: A hosted package
version: 1.2.3
homepage: https://example.com/foo
repository: https://github.com/example/foo
authors:
  - Foo Author
dependencies:
  bar_transitive: ^0.5.0
''');
      await File(join(fooHostedDir.path, 'LICENSE')).writeAsString('''
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''');

      // 2. Transitive hosted package (bar_transitive with LICENSE.md)
      final barHostedDir = Directory(
        join(pubCacheDir.path, 'hosted', 'pub.dev', 'bar_transitive-0.5.0'),
      )..createSync(recursive: true);
      await File(join(barHostedDir.path, 'pubspec.yaml')).writeAsString('''
name: bar_transitive
description: A transitive hosted package
version: 0.5.0
author: Single Author <single@example.com>
''');
      await File(join(barHostedDir.path, 'LICENSE.md')).writeAsString(
        '# License\r\n\r\nSPDX-License-Identifier: BSD-3-Clause\r\n',
      );

      // 3. Git package (git_pkg)
      final gitPkgDir = Directory(
        join(pubCacheDir.path, 'git', 'git_repo-deadbeef1234', 'packages',
            'sub'),
      )..createSync(recursive: true);
      await File(join(gitPkgDir.path, 'pubspec.yaml')).writeAsString('''
name: git_pkg
description: A git dependency package
version: 0.9.0
''');
      await File(join(gitPkgDir.path, 'COPYING')).writeAsString(
        'Mozilla Public License Version 2.0\nhttps://mozilla.org/MPL/2.0/\n',
      );

      // 4. Path package (local_pkg)
      await File(join(localPkgDir.path, 'pubspec.yaml')).writeAsString('''
name: local_pkg
description: A local path dependency
version: 0.1.0
''');
      await File(join(localPkgDir.path, 'LICENSE.txt')).writeAsString(
        'Apache License, Version 2.0\nhttp://www.apache.org/licenses/LICENSE-2.0\n',
      );

      // 5. SDK package (flutter)
      final flutterPkgDir =
          Directory(join(flutterDir.path, 'packages', 'flutter'))
            ..createSync(recursive: true);
      final flutterCacheDir = Directory(join(flutterDir.path, 'bin', 'cache'))
        ..createSync(recursive: true);
      await File(join(flutterCacheDir.path, 'flutter.version.json'))
          .writeAsString(
        '{"flutterVersion": "3.24.0"}',
      );
      await File(join(flutterDir.path, 'LICENSE')).writeAsString('''
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
Neither the name of Google nor the names of its contributors may be used to
endorse or promote products derived from this software.
''');
      await File(join(flutterPkgDir.path, 'pubspec.yaml')).writeAsString('''
name: flutter
description: Flutter SDK
''');

      // 6. Root app project
      final appPubspecPath = join(appDir.path, 'pubspec.yaml');
      final appLockPath = join(appDir.path, 'pubspec.lock');
      await File(appPubspecPath).writeAsString('''
name: my_app
description: Root application under test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
  foo_hosted: ^1.2.3
  git_pkg:
    git:
      url: https://github.com/example/git_repo.git
      path: packages/sub
dev_dependencies:
  local_pkg:
    path: ../local_pkg
''');

      await File(appLockPath).writeAsString('''
packages:
  bar_transitive:
    dependency: transitive
    description:
      name: bar_transitive
      url: "https://pub.dev"
    source: hosted
    version: "0.5.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  foo_hosted:
    dependency: "direct main"
    description:
      name: foo_hosted
      url: "https://pub.dev"
    source: hosted
    version: "1.2.3"
  git_pkg:
    dependency: "direct main"
    description:
      path: packages/sub
      ref: main
      resolved-ref: deadbeef1234
      url: "https://github.com/example/git_repo.git"
    source: git
    version: "0.9.0"
  local_pkg:
    dependency: "direct dev"
    description:
      path: "../local_pkg"
      relative: true
    source: path
    version: "0.1.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      final structure = await listDependencies(
        pubspecLockPath: appLockPath,
        flutterDirPath: flutterDir.path,
        pubCacheDirPath: pubCacheDir.path,
      );

      _expectEqual(structure.package.name, 'my_app');
      _expectEqual(structure.allDependencies.length, 5);
      _expectEqual(structure.package.dependencies.length, 3);
      _expectEqual(structure.package.devDependencies.length, 1);

      final byName = <String, Package>{
        for (final p in structure.allDependencies) p.name: p,
      };

      final foo = byName['foo_hosted']!;
      _expectEqual(foo.version, '1.2.3');
      _expectListEqual(foo.spdxIdentifiers, <String>['MIT']);
      _expectEqual(foo.isMarkdown, false);
      _expectEqual(foo.isDirectDependency, true);
      _expectEqual(foo.dependencies.first.name, 'bar_transitive');

      final bar = byName['bar_transitive']!;
      _expectEqual(bar.isMarkdown, true);
      _expectEqual(bar.isDirectDependency, false);
      _expectListEqual(
          bar.authors, <String>['Single Author <single@example.com>']);
      _expectListEqual(bar.spdxIdentifiers, <String>['BSD-3-Clause']);

      final gitPkg = byName['git_pkg']!;
      _expectEqual(gitPkg.version, '0.9.0');
      _expectListEqual(gitPkg.spdxIdentifiers, <String>['MPL-2.0']);

      final local = byName['local_pkg']!;
      _expectListEqual(local.spdxIdentifiers, <String>['Apache-2.0']);
      _expectEqual(local.isDirectDependency, true);

      final flutterPkg = byName['flutter']!;
      _expectEqual(flutterPkg.isSdk, true);
      _expectEqual(flutterPkg.version, '3.24.0');
      _expectListEqual(flutterPkg.spdxIdentifiers, <String>['BSD-3-Clause']);

      // Test compatibility barrel (dart_pubspec_licenses.dart) with ignore & generateDevDependencies: false
      final filteredStructure = await compat.listDependencies(
        pubspecYamlPath: appPubspecPath,
        flutterDirPath: flutterDir.path,
        pubCacheDirPath: pubCacheDir.path,
        ignore: const <String>['git_pkg'],
        generateDevDependencies: false,
      );
      _expectEqual(filteredStructure.allDependencies.length, 3);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.2 splitSdkLicenses: true splits Flutter-style 100-equal (====) and 80-dash (----) LICENSE blocks',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_sdk_split_');
    try {
      final appDir = Directory(join(tempRoot.path, 'app'))
        ..createSync(recursive: true);
      final pubCacheDir = Directory(join(tempRoot.path, 'pub-cache'))
        ..createSync(recursive: true);
      final flutterDir = Directory(join(tempRoot.path, 'flutter'))
        ..createSync(recursive: true);
      final skyEngineDir = Directory(
        join(flutterDir.path, 'bin', 'cache', 'pkg', 'sky_engine'),
      )..createSync(recursive: true);

      final sep100Equals = '=' * 100;
      await File(join(skyEngineDir.path, 'pubspec.yaml')).writeAsString('''
name: sky_engine
description: Dart SDK extensions for Flutter
version: 0.0.99
''');
      await File(join(skyEngineDir.path, 'LICENSE')).writeAsString('''
engine_core
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
Neither the name of Google nor the names of its contributors may be used to
endorse or promote products derived from this software.
$sep100Equals
harfbuzz
MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell.
$sep100Equals
zlib_component
The origin of this software must not be misrepresented; you must not claim that
you wrote the original software. Altered source versions must be plainly marked
as such, and must not be misrepresented as being the original software. This
notice may not be removed or altered from any source distribution.
''');

      final appPubspecPath = join(appDir.path, 'pubspec.yaml');
      final appLockPath = join(appDir.path, 'pubspec.lock');
      await File(appPubspecPath).writeAsString('''
name: sdk_split_app
description: App testing splitSdkLicenses
version: 1.0.0
''');
      await File(appLockPath).writeAsString('''
packages:
  sky_engine:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.99"
''');

      final structure = await listDependencies(
        pubspecLockPath: appLockPath,
        flutterDirPath: flutterDir.path,
        pubCacheDirPath: pubCacheDir.path,
        splitSdkLicenses: true,
      );

      final names = structure.allDependencies.map((p) => p.name).toList();
      _expectTrue(!names.contains('sky_engine'));
      _expectTrue(names.contains('sky_engine/engine_core'));
      _expectTrue(names.contains('sky_engine/harfbuzz'));
      _expectTrue(names.contains('sky_engine/zlib_component'));

      final byName = <String, Package>{
        for (final p in structure.allDependencies) p.name: p,
      };
      _expectListEqual(
        byName['sky_engine/engine_core']!.spdxIdentifiers,
        <String>['BSD-3-Clause'],
      );
      _expectListEqual(
        byName['sky_engine/harfbuzz']!.spdxIdentifiers,
        <String>['MIT'],
      );
      _expectListEqual(
        byName['sky_engine/zlib_component']!.spdxIdentifiers,
        <String>['Zlib'],
      );
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.3 resolves LICENSES/ directory and .dart_tool/package_config.json fallback',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_pkgcfg_');
    try {
      final appDir = Directory(join(tempRoot.path, 'app'))
        ..createSync(recursive: true);
      final customCachePkgDir =
          Directory(join(tempRoot.path, 'custom_store', 'multi_lic_pkg'))
            ..createSync(recursive: true);
      final licensesSubDir = Directory(join(customCachePkgDir.path, 'LICENSES'))
        ..createSync(recursive: true);

      await File(join(customCachePkgDir.path, 'pubspec.yaml')).writeAsString('''
name: multi_lic_pkg
description: Package with LICENSES directory
version: 2.0.0
''');
      await File(join(licensesSubDir.path, '01_MIT.txt')).writeAsString('''
MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, without restriction,
including without limitation the rights to use, copy, modify.
''');
      await File(join(licensesSubDir.path, '02_Apache.txt')).writeAsString('''
Apache License, Version 2.0
http://www.apache.org/licenses/LICENSE-2.0
''');

      final dartToolDir = Directory(join(appDir.path, '.dart_tool'))
        ..createSync(recursive: true);
      await File(join(dartToolDir.path, 'package_config.json')).writeAsString(
        jsonEncode(<String, dynamic>{
          'configVersion': 2,
          'packages': <Map<String, String>>[
            <String, String>{
              'name': 'multi_lic_pkg',
              'rootUri': Uri.file(customCachePkgDir.path).toString(),
              'packageUri': 'lib/',
            },
          ],
        }),
      );

      await File(join(appDir.path, 'pubspec.yaml')).writeAsString('''
name: cfg_app
description: App with package_config.json
version: 1.0.0
dependencies:
  multi_lic_pkg: ^2.0.0
''');
      await File(join(appDir.path, 'pubspec.lock')).writeAsString('''
packages:
  multi_lic_pkg:
    dependency: "direct main"
    description:
      name: multi_lic_pkg
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
''');

      final structure = await listDependencies(
        pubspecLockPath: join(appDir.path, 'pubspec.lock'),
        pubCacheDirPath: join(tempRoot.path, 'empty_pub_cache'),
      );

      _expectEqual(structure.allDependencies.length, 1);
      final pkg = structure.allDependencies.first;
      _expectEqual(pkg.name, 'multi_lic_pkg');
      _expectListEqual(pkg.spdxIdentifiers, <String>['MIT', 'Apache-2.0']);
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.4 CLI executables (pubspec_licenses and generate) output valid JSON and help',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_cli_');
    try {
      await File(join(tempRoot.path, 'pubspec.yaml')).writeAsString('''
name: cli_test_app
description: CLI test app
version: 1.0.0
''');
      await File(join(tempRoot.path, 'pubspec.lock')).writeAsString('''
packages: {}
''');

      final outJsonPath = join(tempRoot.path, 'out.json');
      final helpCode = await main_cli.main(<String>['--help']);
      _expectEqual(helpCode, 0);

      final genCode = await generate_cli.main(<String>[
        '--pubspec-lock',
        join(tempRoot.path, 'pubspec.lock'),
        '--json',
        '--output',
        outJsonPath,
      ]);
      _expectEqual(genCode, 0);

      final jsonContent = await File(outJsonPath).readAsString();
      final decoded = jsonDecode(jsonContent) as List<dynamic>;
      _expectEqual(decoded.length, 1);
      _expectEqual((decoded.first as Map)['name'], 'cli_test_app');
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.5 Real local pub-cache smoke test on dart_pubspec_licenses-3.2.0 and self',
      () async {
    // 1. Verify current repository (pubspec_licenses)
    final selfPkg = await Package.fromDirectory(projectRoot: Directory.current);
    _expectTrue(selfPkg != null, 'Self package should load');
    _expectEqual(selfPkg!.name, 'pubspec_licenses');
    final pubspecContent = await File(
      join(Directory.current.path, 'pubspec.yaml'),
    ).readAsString();
    final expectedVersion = RegExp(r'^version:\s*([^\s#]+)', multiLine: true)
        .firstMatch(pubspecContent)
        ?.group(1)
        ?.replaceAll('"', '')
        .replaceAll("'", '');
    _expectTrue(
      expectedVersion != null && expectedVersion.isNotEmpty,
      'pubspec.yaml should declare a version',
    );
    _expectEqual(selfPkg.version, expectedVersion);
    _expectListEqual(selfPkg.spdxIdentifiers, <String>['Apache-2.0']);

    // 2. Verify real dart_pubspec_licenses-3.2.0 in local pub-cache if present
    final hostedCachePath = _resolveHostedPubCachePath();
    final cachedDir = hostedCachePath != null
        ? Directory(join(hostedCachePath, 'dart_pubspec_licenses-3.2.0'))
        : null;
    if (cachedDir != null && cachedDir.existsSync()) {
      final cachedPkg = await Package.fromDirectory(projectRoot: cachedDir);
      _expectTrue(cachedPkg != null, 'dart_pubspec_licenses-3.2.0 should load');
      _expectEqual(cachedPkg!.name, 'dart_pubspec_licenses');
      _expectEqual(cachedPkg.version, '3.2.0');
      _expectEqual(cachedPkg.isMarkdown, false);
      _expectListEqual(cachedPkg.spdxIdentifiers, <String>['MIT']);
    }
  });

  await _test(
      '5.6 findPubspecLock traverses parent directories and throws if missing',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_find_');
    try {
      final subDir = Directory(join(tempRoot.path, 'packages', 'sub_pkg'))
        ..createSync(recursive: true);
      final lockPath = join(tempRoot.path, 'pubspec.lock');
      await File(lockPath).writeAsString('packages: {}\n');

      final found = findPubspecLock(join(subDir.path, 'pubspec.yaml'));
      _expectEqual(
        File(found).resolveSymbolicLinksSync(),
        File(lockPath).resolveSymbolicLinksSync(),
      );
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.7 Pub workspace (workspace: list in root pubspec.yaml) resolves member packages',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_ws_');
    try {
      final memberDir = Directory(join(tempRoot.path, 'pkgs', 'member_a'))
        ..createSync(recursive: true);
      await File(join(memberDir.path, 'pubspec.yaml')).writeAsString('''
name: member_a
description: Workspace member package A
version: 0.3.0
''');
      await File(join(memberDir.path, 'LICENSE')).writeAsString('''
SPDX-License-Identifier: ISC
''');

      await File(join(tempRoot.path, 'pubspec.yaml')).writeAsString('''
name: ws_root
description: Workspace root
version: 1.0.0
workspace:
  - pkgs/member_a
dependencies:
  member_a: ^0.3.0
''');
      await File(join(tempRoot.path, 'pubspec.lock')).writeAsString('''
packages: {}
''');

      final structure = await listDependencies(
        pubspecYamlPath: join(tempRoot.path, 'pubspec.yaml'),
        pubCacheDirPath: tempRoot.path,
      );
      _expectEqual(structure.allDependencies.length, 1);
      _expectEqual(structure.allDependencies.first.name, 'member_a');
      _expectListEqual(
        structure.allDependencies.first.spdxIdentifiers,
        <String>['ISC'],
      );
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.8 splitSdkLicenses: true also splits 80-dash (----) separated sections and merges duplicates',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_dash80_');
    try {
      final flutterDir = Directory(join(tempRoot.path, 'flutter'))
        ..createSync(recursive: true);
      final skyDir = Directory(join(flutterDir.path, 'packages', 'sky_engine'))
        ..createSync(recursive: true);
      final sep80Dash = '-' * 80;

      await File(join(skyDir.path, 'pubspec.yaml')).writeAsString('''
name: sky_engine
description: Sky Engine
version: 1.0.0
''');
      await File(join(skyDir.path, 'LICENSE')).writeAsString('''
skia
SPDX-License-Identifier: BSD-3-Clause
$sep80Dash
skia
SPDX-License-Identifier: MIT
$sep80Dash
boringssl
SPDX-License-Identifier: ISC
''');

      await File(join(tempRoot.path, 'pubspec.yaml')).writeAsString('''
name: dash_app
description: Dash split test
version: 1.0.0
''');
      await File(join(tempRoot.path, 'pubspec.lock')).writeAsString('''
packages:
  sky_engine:
    dependency: transitive
    description: flutter
    source: sdk
    version: "1.0.0"
''');

      final structure = await listDependencies(
        pubspecLockPath: join(tempRoot.path, 'pubspec.lock'),
        flutterDirPath: flutterDir.path,
        pubCacheDirPath: tempRoot.path,
        splitSdkLicenses: true,
      );

      final byName = <String, Package>{
        for (final p in structure.allDependencies) p.name: p,
      };
      _expectEqual(byName.length, 2);
      _expectListEqual(
        byName['sky_engine/skia']!.spdxIdentifiers,
        <String>['BSD-3-Clause', 'MIT'],
      );
      _expectListEqual(
        byName['sky_engine/boringssl']!.spdxIdentifiers,
        <String>['ISC'],
      );
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.9 CLI generate outputs valid Dart oss_licenses.dart code when output ends with .dart',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_dartgen_');
    try {
      await File(join(tempRoot.path, 'pubspec.yaml')).writeAsString('''
name: dartgen_app
description: App testing oss_licenses.dart generation
version: 1.2.0
''');
      await File(join(tempRoot.path, 'LICENSE')).writeAsString('''
SPDX-License-Identifier: Apache-2.0
''');
      await File(join(tempRoot.path, 'pubspec.lock')).writeAsString('''
packages: {}
''');

      final outDartPath = join(tempRoot.path, 'oss_licenses.dart');
      final code = await generate(<String>[
        '--pubspec-lock',
        join(tempRoot.path, 'pubspec.lock'),
        '-o',
        outDartPath,
      ]);
      _expectEqual(code, 0);

      final dartSource = await File(outDartPath).readAsString();
      _expectTrue(dartSource.contains('const thisPackage = _dartgen_app;'));
      _expectTrue(dartSource.contains('const allDependencies = <Package>['));
      _expectTrue(dartSource.contains("spdxIdentifiers: ['Apache-2.0']"));
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.10 CLI supports -p/--project-root, -i/--ignore, and --no-dev-dependencies',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_cliflags_');
    try {
      final appDir = Directory(join(tempRoot.path, 'app'))
        ..createSync(recursive: true);
      final pubCacheDir = Directory(join(tempRoot.path, 'pub-cache'))
        ..createSync(recursive: true);

      final mainPkgDir = Directory(
          join(pubCacheDir.path, 'hosted', 'pub.dev', 'main_dep-1.0.0'))
        ..createSync(recursive: true);
      await File(join(mainPkgDir.path, 'pubspec.yaml')).writeAsString('''
name: main_dep
description: Main dependency
version: 1.0.0
''');
      await File(join(mainPkgDir.path, 'LICENSE'))
          .writeAsString('SPDX-License-Identifier: MIT\n');

      final devPkgDir = Directory(
          join(pubCacheDir.path, 'hosted', 'pub.dev', 'dev_dep-1.0.0'))
        ..createSync(recursive: true);
      await File(join(devPkgDir.path, 'pubspec.yaml')).writeAsString('''
name: dev_dep
description: Dev dependency
version: 1.0.0
''');
      await File(join(devPkgDir.path, 'LICENSE'))
          .writeAsString('SPDX-License-Identifier: ISC\n');

      await File(join(appDir.path, 'pubspec.yaml')).writeAsString('''
name: flag_app
description: Flag test app
version: 1.0.0
dependencies:
  main_dep: ^1.0.0
dev_dependencies:
  dev_dep: ^1.0.0
''');
      await File(join(appDir.path, 'pubspec.lock')).writeAsString('''
packages:
  main_dep:
    dependency: "direct main"
    description:
      name: main_dep
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  dev_dep:
    dependency: "direct dev"
    description:
      name: dev_dep
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

      final outJson = join(tempRoot.path, 'filtered.json');
      final exitStatus = await generate(<String>[
        '-p',
        appDir.path,
        '--pub-cache-dir',
        pubCacheDir.path,
        '--no-dev-dependencies',
        '-i',
        'flag_app',
        '-j',
        '-o',
        outJson,
      ]);
      _expectEqual(exitStatus, 0);

      final parsed =
          jsonDecode(await File(outJson).readAsString()) as List<dynamic>;
      _expectEqual(parsed.length, 1);
      _expectEqual((parsed.first as Map)['name'], 'main_dep');
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });

  await _test(
      '5.11 CLI generate defaults to writing lib/oss_licenses.dart when -o and -j are omitted',
      () async {
    final tempRoot =
        await Directory.systemTemp.createTemp('pubspec_licenses_default_out_');
    try {
      final libDir = Directory(join(tempRoot.path, 'lib'))
        ..createSync(recursive: true);
      final pubCacheDir = Directory(join(tempRoot.path, 'pub-cache'))
        ..createSync(recursive: true);
      final feDir = Directory(
        join(pubCacheDir.path, 'hosted', 'pub.dev',
            '_fe_analyzer_shared-67.0.0'),
      )..createSync(recursive: true);
      await File(join(feDir.path, 'pubspec.yaml')).writeAsString('''
name: _fe_analyzer_shared
description: Shared analyzer logic
version: 67.0.0
''');
      await File(join(feDir.path, 'LICENSE'))
          .writeAsString('SPDX-License-Identifier: BSD-3-Clause\n');

      await File(join(tempRoot.path, 'pubspec.yaml')).writeAsString('''
name: default_out_app
description: App testing default lib/oss_licenses.dart generation
version: 1.0.0
dependencies:
  _fe_analyzer_shared: ^67.0.0
''');
      await File(join(tempRoot.path, 'pubspec.lock')).writeAsString('''
packages:
  _fe_analyzer_shared:
    dependency: "direct main"
    description:
      name: _fe_analyzer_shared
      url: "https://pub.dev"
    source: hosted
    version: "67.0.0"
''');

      final exitStatus = await generate_cli.main(<String>[
        '-p',
        tempRoot.path,
        '--pub-cache-dir',
        pubCacheDir.path,
      ]);
      _expectEqual(exitStatus, 0);

      final expectedFile = File(join(libDir.path, 'oss_licenses.dart'));
      _expectTrue(
        expectedFile.existsSync(),
        'Expected lib/oss_licenses.dart to be generated by default',
      );
      final content = await expectedFile.readAsString();
      _expectTrue(content.contains('const thisPackage = _default_out_app;'));
      _expectTrue(content.contains('const __fe_analyzer_shared = Package('));
      _expectTrue(!content.contains('homepage: null'));
    } finally {
      await tempRoot.delete(recursive: true);
    }
  });
}

Future<void> _runRealPubCacheCorpusTests() async {
  await _test(
      '6.1 Stress-tests MiniYamlParser, SpdxDetector, and Package.fromDirectory across ~/.pub-cache/hosted/pub.dev',
      () async {
    final hostedCachePath = _resolveHostedPubCachePath();
    final hostedDir =
        hostedCachePath != null ? Directory(hostedCachePath) : null;
    if (hostedDir == null || !hostedDir.existsSync()) {
      stdout.writeln(
        '    [INFO] Hosted pub-cache directory not present; skipping corpus scan.',
      );
      return;
    }

    final packageDirs = hostedDir
        .listSync()
        .whereType<Directory>()
        .where((d) => !basename(d.path).startsWith('.'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final maxToScan = packageDirs.length;
    var scannedCount = 0;
    var spdxDetectedCount = 0;
    final failures = <String>[];

    for (var i = 0; i < maxToScan; i++) {
      final dir = packageDirs[i];
      final pubspecFile = File(join(dir.path, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) continue;

      try {
        final rawYaml = await pubspecFile.readAsString();
        final parsed = MiniYamlParser.parseMap(rawYaml);
        final name = parsed['name']?.toString() ?? '';
        final version = parsed['version']?.toString() ?? '';

        if (name.isEmpty || version.isEmpty) {
          failures.add(
              '${basename(dir.path)}: empty name ("$name") or version ("$version")');
          continue;
        }

        final pkg = await Package.fromDirectory(projectRoot: dir);
        if (pkg == null) {
          // Some very old packages in pub-cache might omit description; verify if description exists
          if (parsed['description'] is String) {
            failures.add(
                '${basename(dir.path)}: Package.fromDirectory returned null despite valid description');
          }
          continue;
        }

        if (pkg.spdxIdentifiers.isNotEmpty) {
          spdxDetectedCount++;
        }
        if (pkg.name == 'dbus' &&
            pkg.spdxIdentifiers.contains('AGPL-3.0-only')) {
          failures.add(
              '${basename(dir.path)}: false positive AGPL-3.0-only on MPL-2.0');
        }
        scannedCount++;
      } catch (e) {
        failures.add('${basename(dir.path)}: $e');
      }
    }

    stdout.writeln(
      '    Scanned $scannedCount real packages in ~/.pub-cache with ${failures.length} failures ($spdxDetectedCount with detected SPDX IDs)',
    );
    if (failures.isNotEmpty) {
      throw AssertionError(
        'Corpus scan had ${failures.length} failures:\n  ${failures.take(15).join('\n  ')}',
      );
    }
    _expectTrue(scannedCount > 0,
        'Expected to scan at least 1 package in ~/.pub-cache');
  });
}
