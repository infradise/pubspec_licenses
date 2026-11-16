import 'dart:io';

import 'mini_yaml_parser.dart';
import 'path_utils.dart' as path;
import 'spdx_detector.dart';

export 'project_structure.dart';

/// Represents a Dart/Flutter package with its metadata and license information.
///
/// This class encapsulates all relevant information about a package including:
/// - Basic metadata ([name], [description], [version])
/// - Repository information ([homepage], [repository])
/// - License content, format, and detected [spdxIdentifiers]
/// - [dependencies] and [devDependencies]
/// - Whether it's an SDK package ([isSdk]) or direct dependency ([isDirectDependency])
class Package {
  /// Creates a [Package] instance.
  const Package({
    this.directory,
    required this.name,
    this.description = '',
    this.authors = const [],
    this.isMarkdown = false,
    this.isSdk = false,
    this.isDirectDependency = false,
    this.dependencies = const [],
    this.devDependencies = const [],
    this.pubspec,
    this.homepage,
    this.repository,
    this.version,
    this.license,
    this.spdxIdentifiers = const [],
  });

  /// Creates a [Package] instance from a serialized [Map].
  factory Package.fromMap(Map<dynamic, dynamic> map) {
    final rawAuthors = map['authors'];
    final authorsList = rawAuthors is List
        ? rawAuthors.map((e) => e.toString()).toList()
        : <String>[];

    final rawSpdx = map['spdxIdentifiers'];
    final spdxList = rawSpdx is List
        ? rawSpdx.map((e) => e.toString()).toList()
        : <String>[];

    final rawDeps = map['dependencies'];
    final depsList = rawDeps is List
        ? rawDeps.whereType<Map>().map<Package>(Package.fromMap).toList()
        : <Package>[];

    final rawDevDeps = map['devDependencies'];
    final devDepsList = rawDevDeps is List
        ? rawDevDeps.whereType<Map>().map<Package>(Package.fromMap).toList()
        : <Package>[];

    final dirPath = map['directory'];
    final dir = dirPath is String && dirPath.isNotEmpty
        ? Directory(dirPath)
        : (dirPath is Directory ? dirPath : null);

    final licenseText = map['license'] as String?;

    return Package(
      directory: dir,
      pubspec: map['pubspec'] as Map?,
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      homepage: map['homepage'] as String?,
      repository: map['repository'] as String?,
      authors: authorsList,
      version: map['version']?.toString(),
      license: licenseText,
      spdxIdentifiers: spdxList.isNotEmpty
          ? spdxList
          : (licenseText != null
              ? detectSpdxIdentifiers(licenseText)
              : <String>[]),
      isMarkdown: (map['isMarkdown'] as bool?) ?? false,
      isSdk: (map['isSdk'] as bool?) ?? false,
      isDirectDependency: (map['isDirectDependency'] as bool?) ?? false,
      dependencies: depsList,
      devDependencies: devDepsList,
    );
  }

  /// Creates a [Package] instance from a JSON map.
  factory Package.fromJson(Map<String, dynamic> json) => Package.fromMap(json);

  /// The directory where the package is located.
  final Directory? directory;

  /// The parsed `pubspec.yaml` content as a [Map].
  final Map? pubspec;

  /// The name of the package.
  final String name;

  /// A brief description of the package.
  final String description;

  /// The homepage URL, if available.
  final String? homepage;

  /// The repository URL, if available.
  final String? repository;

  /// List of authors as specified in `pubspec.yaml`.
  ///
  /// This can be empty if no authors are specified.
  final List<String> authors;

  /// The package version, if available.
  final String? version;

  /// The full text of the license, if available.
  final String? license;

  /// The [SPDX](https://spdx.org/licenses/) license identifiers, if detected.
  final List<String> spdxIdentifiers;

  /// Whether the license file is in Markdown format.
  final bool isMarkdown;

  /// Whether the package is included in the SDK or not.
  final bool isSdk;

  /// Whether the package is a direct dependency of the root project.
  final bool isDirectDependency;

  /// Direct dependencies.
  final List<Package> dependencies;

  /// Direct dev dependencies.
  final List<Package> devDependencies;

  /// Gets the path to the package's `pubspec.yaml` file.
  String get pubspecYamlPath => getFilePath('pubspec.yaml');

  /// Gets the full path for a file within the package directory.
  ///
  /// [name] is the file name relative to the package root.
  String getFilePath(String name) => path.join(directory?.path ?? '', name);

  /// Returns a copy of this [Package] with updated fields.
  Package copyWith({
    Directory? directory,
    Map? pubspec,
    String? name,
    String? description,
    String? homepage,
    String? repository,
    List<String>? authors,
    String? version,
    String? license,
    List<String>? spdxIdentifiers,
    bool? isMarkdown,
    bool? isSdk,
    bool? isDirectDependency,
    List<Package>? dependencies,
    List<Package>? devDependencies,
  }) {
    return Package(
      directory: directory ?? this.directory,
      pubspec: pubspec ?? this.pubspec,
      name: name ?? this.name,
      description: description ?? this.description,
      homepage: homepage ?? this.homepage,
      repository: repository ?? this.repository,
      authors: authors ?? this.authors,
      version: version ?? this.version,
      license: license ?? this.license,
      spdxIdentifiers: spdxIdentifiers ?? this.spdxIdentifiers,
      isMarkdown: isMarkdown ?? this.isMarkdown,
      isSdk: isSdk ?? this.isSdk,
      isDirectDependency: isDirectDependency ?? this.isDirectDependency,
      dependencies: dependencies ?? this.dependencies,
      devDependencies: devDependencies ?? this.devDependencies,
    );
  }

  /// Converts the package information to a JSON-serializable map.
  ///
  /// Returns a map containing essential package metadata excluding
  /// internal properties like [directory] and [pubspec].
  Map<String, dynamic> toJson({bool? isDirectDependency}) => <String, dynamic>{
        'name': name,
        'description': description,
        'homepage': homepage,
        'repository': repository,
        'authors': authors,
        'version': version,
        'license': license,
        'spdxIdentifiers': spdxIdentifiers,
        'isMarkdown': isMarkdown,
        'isSdk': isSdk,
        'isDirectDependency': isDirectDependency ?? this.isDirectDependency,
      };

  /// Creates a [Package] instance from a `pubspec.lock` package entry.
  ///
  /// [package] is the package entry from `pubspec.lock`.
  /// [pubCacheDirPath] is the path to the pub cache directory.
  /// [flutterDir] is the Flutter SDK directory path.
  /// [basePubspecYamlPath] is used to resolve relative path dependencies.
  /// [outerName] can override the package name from the entry.
  /// [packageConfigPaths] is an optional map of package names to resolved root
  /// directory paths from `.dart_tool/package_config.json`.
  ///
  /// Returns a [Package] instance or `null` if the package cannot be loaded.
  static Future<Package?> fromPubspecLockPackageEntry({
    required Map package,
    required String pubCacheDirPath,
    required String? flutterDir,
    required String basePubspecYamlPath,
    String? outerName,
    Map<String, String>? packageConfigPaths,
  }) async {
    Directory? directory;
    var isSdk = false;
    outerName ??= package['name']?.toString();
    if (outerName == null) return null;

    final dependencyType = package['dependency']?.toString() ?? '';
    final isDirect = dependencyType.startsWith('direct ');

    final source = package['source']?.toString();
    final desc = package['description'];
    if (source == 'hosted') {
      final url =
          (desc is Map ? desc['url']?.toString() : null) ?? 'https://pub.dev';
      final host = removePrefix(url);
      final name =
          (desc is Map ? desc['name']?.toString() : desc?.toString()) ??
              outerName;
      final version = package['version']?.toString() ?? '';
      directory = Directory(
        path.join(
          pubCacheDirPath,
          'hosted',
          host.replaceAll('/', '%47'),
          '$name-$version',
        ),
      );
    } else if (source == 'git') {
      final url =
          (desc is Map ? desc['url']?.toString() : desc?.toString()) ?? '';
      final repo = gitRepoName(url);
      final commit =
          (desc is Map ? desc['resolved-ref']?.toString() : '') ?? '';
      final subPath = (desc is Map ? desc['path']?.toString() : null) ?? '.';
      directory = Directory(
        path.normalize(
          path.join(pubCacheDirPath, 'git', '$repo-$commit', subPath),
        ),
      );
    } else if (source == 'sdk') {
      isSdk = true;
      if (flutterDir != null && flutterDir.isNotEmpty) {
        directory = Directory(path.join(flutterDir, 'packages', outerName));
        if (!directory.existsSync()) {
          directory = Directory(
            path.join(flutterDir, 'bin', 'cache', 'pkg', outerName),
          );
        }
      }
    } else if (source == 'path') {
      final rawPath =
          (desc is Map ? desc['path']?.toString() : desc?.toString()) ?? '';
      directory = Directory(
        path.absolute(path.dirname(basePubspecYamlPath), rawPath),
      );
    } else {
      return null;
    }

    if ((directory == null || !directory.existsSync()) &&
        packageConfigPaths != null &&
        packageConfigPaths.containsKey(outerName)) {
      directory = Directory(packageConfigPaths[outerName]!);
    }

    if (directory == null) {
      return null;
    }

    return await fromDirectory(
      projectRoot: directory,
      outerName: outerName,
      isSdk: isSdk,
      isDirectDependency: isDirect,
      flutterDir: flutterDir,
    );
  }

  /// Creates a [Package] instance from a directory containing a Dart package.
  ///
  /// [projectRoot] is the root directory of the package.
  /// [outerName] can override the package name from `pubspec.yaml`.
  /// [isSdk] indicates whether this is an SDK package.
  /// [isDirectDependency] indicates whether this is a direct dependency.
  /// [flutterDir] is the Flutter SDK directory path for SDK packages.
  ///
  /// Returns a [Package] instance or `null` if the package cannot be loaded
  /// (e.g., missing required fields in `pubspec.yaml`).
  static Future<Package?> fromDirectory({
    required Directory projectRoot,
    String? outerName,
    bool isSdk = false,
    bool isDirectDependency = false,
    String? flutterDir,
  }) async {
    String? license;
    var isMarkdown = false;

    if (outerName == 'flutter' &&
        flutterDir != null &&
        File(path.join(flutterDir, 'LICENSE')).existsSync()) {
      license = await File(path.join(flutterDir, 'LICENSE')).readAsString();
    } else {
      final loadedLicense = await _readPackageLicense(projectRoot);
      if (loadedLicense != null) {
        license = loadedLicense.content;
        isMarkdown = loadedLicense.isMarkdown;
      }
    }

    final spdxIds = <String>[];
    if (license != null) {
      final normalizedLicense = license
          .trim()
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'[ \t]+\n'), '\n');
      if (normalizedLicense.isEmpty) {
        license = null;
      } else {
        license = normalizedLicense;
        spdxIds.addAll(detectSpdxIdentifiers(license));
      }
    }

    Map<String, dynamic> yaml;
    try {
      final pubspecFile = File(path.join(projectRoot.path, 'pubspec.yaml'));
      if (await pubspecFile.exists()) {
        yaml = MiniYamlParser.parseMap(await pubspecFile.readAsString());
      } else {
        yaml = <String, dynamic>{};
      }
    } catch (_) {
      yaml = <String, dynamic>{};
    }

    final name = yaml['name'] ?? (isSdk ? outerName : null);
    final description = yaml['description'] ?? (isSdk ? '' : null);
    if (name is! String || description is! String) {
      return null;
    }

    final version = outerName == 'flutter' && flutterDir != null
        ? (await getFlutterVersionFromDirectory(flutterDir) ??
            yaml['version']?.toString())
        : yaml['version']?.toString();

    final rawAuthors = yaml['authors'];
    final List<String> authors;
    if (rawAuthors is List) {
      authors = rawAuthors.map((e) => e.toString()).toList();
    } else if (yaml['author'] != null) {
      authors = <String>[yaml['author'].toString()];
    } else {
      authors = <String>[];
    }

    return Package(
      directory: projectRoot,
      pubspec: yaml,
      name: name,
      description: description,
      homepage: yaml['homepage']?.toString(),
      repository: yaml['repository']?.toString(),
      authors: authors,
      version: version?.trim(),
      license: license,
      spdxIdentifiers: spdxIds,
      isMarkdown: isMarkdown,
      isSdk: isSdk,
      isDirectDependency: isDirectDependency,
      dependencies: <Package>[],
      devDependencies: <Package>[],
    );
  }

  static Future<_LoadedLicense?> _readPackageLicense(
      Directory projectRoot) async {
    const candidates = <(String, bool)>[
      ('LICENSE', false),
      ('LICENSE.md', true),
      ('LICENSE.txt', false),
      ('LICENCE', false),
      ('LICENCE.md', true),
      ('LICENCE.txt', false),
      ('COPYING', false),
      ('COPYING.md', true),
      ('COPYING.txt', false),
      ('UNLICENSE', false),
      ('UNLICENSE.md', true),
      ('UNLICENSE.txt', false),
      ('license', false),
      ('license.md', true),
      ('license.txt', false),
      ('licence', false),
      ('licence.md', true),
      ('licence.txt', false),
      ('unlicense', false),
    ];

    for (final (fileName, markdown) in candidates) {
      final file = File(path.join(projectRoot.path, fileName));
      if (await file.exists()) {
        try {
          final text = await file.readAsString();
          return _LoadedLicense(text, markdown);
        } catch (_) {
          // Continue to next candidate
        }
      }
    }

    // Case-insensitive directory scan fallback on case-sensitive filesystems
    if (await projectRoot.exists()) {
      try {
        final fallbackPattern = RegExp(
          r'^(licen[cs]e|copying|unlicense)(\.(md|markdown|txt))?$',
          caseSensitive: false,
        );
        final matchedFiles = projectRoot
            .listSync()
            .whereType<File>()
            .where((f) => fallbackPattern.hasMatch(path.basename(f.path)))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in matchedFiles) {
          try {
            final lower = file.path.toLowerCase();
            final isMd = lower.endsWith('.md') || lower.endsWith('.markdown');
            return _LoadedLicense(await file.readAsString(), isMd);
          } catch (_) {
            // Continue
          }
        }
      } catch (_) {
        // Ignore directory listing errors
      }
    }

    // Check LICENSES/ directory if present
    final licensesDir = Directory(path.join(projectRoot.path, 'LICENSES'));
    if (await licensesDir.exists()) {
      try {
        final entries = licensesDir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (entries.isNotEmpty) {
          final parts = <String>[];
          var allMarkdown = true;
          for (final entry in entries) {
            final content = (await entry.readAsString()).trim();
            if (content.isNotEmpty) {
              parts.add(content);
              if (!entry.path.toLowerCase().endsWith('.md')) {
                allMarkdown = false;
              }
            }
          }
          if (parts.isNotEmpty) {
            return _LoadedLicense(parts.join('\n\n---\n\n'), allMarkdown);
          }
        }
      } catch (_) {
        // Ignore directory read errors
      }
    }

    return null;
  }

  /// Updates the [dependencies] and [devDependencies] lists based on `pubspec.yaml`.
  ///
  /// [allPackages] is a map of all available packages by name, used to
  /// resolve dependency references from the pubspec.
  void updateDependencies(Map<String, Package> allPackages) {
    dependencies
      ..clear()
      ..addAll(_getDependenciesFor('dependencies', allPackages));
    devDependencies
      ..clear()
      ..addAll(_getDependenciesFor('dev_dependencies', allPackages));
  }

  List<Package> _getDependenciesFor(
    String depType,
    Map<String, Package> allPackages,
  ) {
    final deps = <Package>[];
    final section = pubspec?[depType];
    if (section is Map) {
      for (final rawKey in section.keys) {
        final depName = rawKey.toString();
        final dep = allPackages[depName];
        if (dep != null) {
          deps.add(dep);
        }
      }
    }
    return deps;
  }

  /// Retrieves the Flutter SDK version from the specified Flutter directory.
  ///
  /// [flutterDir] is the path to the Flutter SDK directory.
  /// Returns the Flutter version as a string, or `null` if it cannot be determined.
  static Future<String?> getFlutterVersionFromDirectory(
      String flutterDir) async {
    try {
      final versionFile = File(
        path.join(flutterDir, 'bin', 'cache', 'flutter.version.json'),
      );
      if (await versionFile.exists()) {
        final versionJson =
            MiniYamlParser.parse(await versionFile.readAsString());
        if (versionJson is Map && versionJson['flutterVersion'] is String) {
          return (versionJson['flutterVersion'] as String).trim();
        }
      }
      final legacyVersionFile = File(path.join(flutterDir, 'version'));
      if (await legacyVersionFile.exists()) {
        final content = (await legacyVersionFile.readAsString()).trim();
        if (content.isNotEmpty) return content;
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }
}

class _LoadedLicense {
  const _LoadedLicense(this.content, this.isMarkdown);
  final String content;
  final bool isMarkdown;
}

/// Removes the protocol prefix from a URL.
///
/// Strips `https://` or `http://` from the beginning of [url].
String removePrefix(String url) {
  if (url.startsWith('https://')) return url.substring(8);
  if (url.startsWith('http://')) return url.substring(7);
  return url;
}

/// Extracts the repository name from a Git URL.
///
/// Takes a Git [url] and extracts the repository name,
/// removing the `.git` extension if present.
String gitRepoName(String url) {
  final slashIndex = url.lastIndexOf('/');
  final colonIndex = url.lastIndexOf(':');
  final splitIndex = slashIndex > colonIndex ? slashIndex : colonIndex;
  final name = splitIndex >= 0 ? url.substring(splitIndex + 1) : url;
  return name.endsWith('.git') ? name.substring(0, name.length - 4) : name;
}
