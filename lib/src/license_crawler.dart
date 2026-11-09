import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'limit_concurrency.dart';
import 'mini_yaml_parser.dart';
import 'package.dart';
import 'path_utils.dart' as path;
import 'spdx_detector.dart';

/// The Flutter SDK root directory path from `FLUTTER_ROOT` environment variable.
final String? flutterDir = Platform.environment['FLUTTER_ROOT'];

/// Attempts to guess the location of the pub cache directory.
///
/// Checks in the following order:
/// 1. `PUB_CACHE` environment variable
/// 2. Platform-specific default locations:
///    - Windows: `%APPDATA%\Pub\Cache` or `%LOCALAPPDATA%\Pub\Cache`
///    - macOS/Linux: `$HOME/.pub-cache`
///
/// Returns the path to the pub cache directory, or `null` if not found.
String? guessPubCacheDir() {
  var pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache != null &&
      pubCache.isNotEmpty &&
      Directory(pubCache).existsSync()) {
    return pubCache;
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      pubCache = path.join(appData, 'Pub', 'Cache');
      if (Directory(pubCache).existsSync()) return pubCache;
    }
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      pubCache = path.join(localAppData, 'Pub', 'Cache');
      if (Directory(pubCache).existsSync()) return pubCache;
    }
  }

  final homeDir =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDir != null && homeDir.isNotEmpty) {
    return path.join(homeDir, '.pub-cache');
  }
  return pubCache;
}

/// Attempts to determine the Flutter SDK root directory.
///
/// Checks in the following order:
/// 1. Explicit [flutterDirPath] parameter
/// 2. `FLUTTER_ROOT` environment variable
/// 3. `.dart_tool/package_config.json` entry for `flutter` or `sky_engine`
/// 4. Resolving `flutter` executable on `PATH`
String? guessFlutterDir({
  String? flutterDirPath,
  Map<String, String>? packageConfigPaths,
}) {
  if (flutterDirPath != null && flutterDirPath.isNotEmpty) {
    return flutterDirPath;
  }
  final envFlutter = Platform.environment['FLUTTER_ROOT'];
  if (envFlutter != null && envFlutter.isNotEmpty) {
    return envFlutter;
  }
  if (packageConfigPaths != null) {
    final flutterPkgPath = packageConfigPaths['flutter'];
    if (flutterPkgPath != null && flutterPkgPath.isNotEmpty) {
      // Typically <FLUTTER_ROOT>/packages/flutter
      final parent = path.dirname(flutterPkgPath);
      if (path.basename(parent) == 'packages') {
        return path.dirname(parent);
      }
    }
  }
  try {
    final result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>['flutter'],
    );
    if (result.exitCode == 0) {
      final firstLine = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (firstLine.isNotEmpty) {
        final resolvedBin = File(firstLine).resolveSymbolicLinksSync();
        final binDir = path.dirname(resolvedBin);
        if (path.basename(binDir) == 'bin') {
          return path.dirname(binDir);
        }
      }
    }
  } catch (_) {
    // Ignore process lookup errors in restricted environments
  }
  return null;
}

/// Finds the `pubspec.lock` file by traversing up the directory tree.
///
/// Starts from [from] directory and searches for `pubspec.lock`,
/// moving up to parent directories until found.
///
/// Returns the path to the `pubspec.lock` file.
///
/// Throws a [StateError] if `pubspec.lock` is not found in the directory hierarchy.
String findPubspecLockFromDirectory(Directory from) {
  var current = from.absolute;
  while (true) {
    final candidate = path.join(current.path, 'pubspec.lock');
    if (File(candidate).existsSync()) {
      return candidate;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not find pubspec.lock starting from ${from.path}',
      );
    }
    current = parent;
  }
}

/// Finds the `pubspec.lock` file for a given `pubspec.yaml` path.
///
/// Searches for `pubspec.lock` starting from the directory containing
/// the specified [pubspecYamlPath].
///
/// Returns the path to the `pubspec.lock` file.
String findPubspecLock(String pubspecYamlPath) {
  return findPubspecLockFromDirectory(Directory(path.dirname(pubspecYamlPath)));
}

/// Reads `.dart_tool/package_config.json` if present in [projectRootDir] and
/// returns a map of package name to its resolved root directory path.
Map<String, String> loadPackageConfigPaths(String projectRootDir) {
  final result = <String, String>{};
  final configFile = File(
    path.join(projectRootDir, '.dart_tool', 'package_config.json'),
  );
  if (!configFile.existsSync()) return result;

  try {
    final decoded = jsonDecode(configFile.readAsStringSync());
    if (decoded is! Map) return result;
    final packages = decoded['packages'];
    if (packages is! List) return result;

    final configDir = path.dirname(configFile.path);
    for (final entry in packages) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString();
      final rootUriStr = entry['rootUri']?.toString();
      if (name == null || rootUriStr == null) continue;

      String resolvedPath;
      if (rootUriStr.startsWith('file://')) {
        resolvedPath = Uri.parse(rootUriStr).toFilePath();
      } else {
        resolvedPath = path.normalize(path.join(configDir, rootUriStr));
      }
      result[name] = resolvedPath;
    }
  } catch (_) {
    // Ignore malformed package_config.json
  }
  return result;
}

/// Lists all dependencies for a project including transitive dependencies.
///
/// Supports both `pubspecLockPath` (direct path to `pubspec.lock`) and
/// `pubspecYamlPath` (path to `pubspec.yaml`, compatible with
/// `dart_pubspec_licenses` v3.2.0).
///
/// Parameters:
/// - [pubspecLockPath]: Path to the `pubspec.lock` file.
/// - [pubspecYamlPath]: Path to the `pubspec.yaml` file (optional if [pubspecLockPath] is provided).
/// - [flutterDirPath]: Optional override for the Flutter SDK root directory.
/// - [pubCacheDirPath]: Optional override for the Pub cache directory.
/// - [ignore]: Package names to exclude from results.
/// - [generateDevDependencies]: Whether to include dev dependencies.
/// - [maxConcurrency]: Maximum concurrent package loading operations.
/// - [splitSdkLicenses]: When `true`, splits `sky_engine` bundled licenses into
///   individual `sky_engine/<component>` [Package] entries.
///
/// Returns a [ProjectStructure] containing the main [Package] and [ProjectStructure.allDependencies].
Future<ProjectStructure> listDependencies({
  String? pubspecLockPath,
  String? pubspecYamlPath,
  String? flutterDirPath,
  String? pubCacheDirPath,
  List<String> ignore = const [],
  bool generateDevDependencies = true,
  int maxConcurrency = 10,
  bool splitSdkLicenses = false,
}) async {
  String resolvedYamlPath;
  String resolvedLockPath;

  if (pubspecYamlPath != null && pubspecYamlPath.isNotEmpty) {
    resolvedYamlPath = pubspecYamlPath;
    resolvedLockPath = (pubspecLockPath != null && pubspecLockPath.isNotEmpty)
        ? pubspecLockPath
        : findPubspecLock(resolvedYamlPath);
  } else if (pubspecLockPath != null && pubspecLockPath.isNotEmpty) {
    if (path.basename(pubspecLockPath) == 'pubspec.yaml') {
      resolvedYamlPath = pubspecLockPath;
      resolvedLockPath = findPubspecLock(resolvedYamlPath);
    } else if (Directory(pubspecLockPath).existsSync()) {
      resolvedYamlPath = path.join(pubspecLockPath, 'pubspec.yaml');
      resolvedLockPath =
          findPubspecLockFromDirectory(Directory(pubspecLockPath));
    } else {
      resolvedLockPath = pubspecLockPath;
      resolvedYamlPath = path.join(
        path.dirname(resolvedLockPath),
        'pubspec.yaml',
      );
    }
  } else {
    resolvedYamlPath = path.join(Directory.current.path, 'pubspec.yaml');
    resolvedLockPath = findPubspecLock(resolvedYamlPath);
  }

  final pubCacheDir = pubCacheDirPath ?? guessPubCacheDir();
  if (pubCacheDir == null) {
    throw StateError('Could not find pub cache directory');
  }

  final lockDir = path.dirname(resolvedLockPath);
  final yamlDir = path.dirname(resolvedYamlPath);
  final packageConfigPaths = <String, String>{
    ...loadPackageConfigPaths(lockDir),
    ...loadPackageConfigPaths(yamlDir),
  };

  final effectiveFlutterDir = guessFlutterDir(
    flutterDirPath: flutterDirPath,
    packageConfigPaths: packageConfigPaths,
  );

  var myPackage = await Package.fromDirectory(
    projectRoot: Directory(yamlDir),
    flutterDir: effectiveFlutterDir,
  );
  if (myPackage == null) {
    if (pubspecYamlPath != null) {
      throw StateError('Could not load package from $resolvedYamlPath');
    }
    // Fallback root package when only a standalone pubspec.lock exists
    myPackage = Package(
      directory: Directory(yamlDir),
      name: 'root',
      description: '',
      authors: const <String>[],
      isMarkdown: false,
      isSdk: false,
      dependencies: <Package>[],
      devDependencies: <Package>[],
    );
  }

  final lockFile = File(resolvedLockPath);
  if (!await lockFile.exists()) {
    throw StateError('Could not find pubspec.lock at $resolvedLockPath');
  }

  final pubspecLock = MiniYamlParser.parseMap(await lockFile.readAsString());
  final rawPackages = pubspecLock['packages'];
  final packagesMap = rawPackages is Map ? rawPackages : <dynamic, dynamic>{};

  final limitConcurrency = LimitConcurrency(maxConcurrency);
  final loadedPackages = await Future.wait(
    packagesMap.keys
        .map((k) => k.toString())
        .where((key) => !ignore.contains(key))
        .where((key) {
      if (generateDevDependencies) return true;
      final entry = packagesMap[key];
      if (entry is Map) {
        final depKind = entry['dependency']?.toString() ?? '';
        if (depKind == 'direct dev') return false;
      }
      return true;
    }).map(
      (packageName) => limitConcurrency.run(() async {
        final entry = packagesMap[packageName];
        if (entry is! Map) return null;
        return Package.fromPubspecLockPackageEntry(
          outerName: packageName,
          package: entry,
          pubCacheDirPath: pubCacheDir,
          flutterDir: effectiveFlutterDir,
          basePubspecYamlPath: resolvedYamlPath,
          packageConfigPaths: packageConfigPaths,
        );
      }),
    ),
  );

  final packagesByName = <String, Package>{
    for (final p in loadedPackages.whereType<Package>()) p.name: p,
  };

  // Pub workspace support
  final rootDirectory = Directory(lockDir);
  final rootPubspecYamlFile =
      File(path.join(rootDirectory.path, 'pubspec.yaml'));
  if (rootPubspecYamlFile.existsSync()) {
    final rootPubspecYaml = MiniYamlParser.parseMap(
      await rootPubspecYamlFile.readAsString(),
    );
    final workspace = rootPubspecYaml['workspace'];
    if (workspace is List) {
      for (final entry in workspace.whereType<String>()) {
        final pkg = await Package.fromDirectory(
          projectRoot: Directory(path.join(rootDirectory.path, entry)),
          flutterDir: effectiveFlutterDir,
        );
        if (pkg != null && !ignore.contains(pkg.name)) {
          packagesByName[pkg.name] = pkg;
        }
      }
    }
  }

  if (splitSdkLicenses) {
    _splitSdkLicenses(packagesByName);
  }

  for (final pkg in packagesByName.values) {
    pkg.updateDependencies(packagesByName);
  }

  myPackage.updateDependencies(packagesByName);
  packagesByName.removeWhere((key, _) => key == myPackage!.name);

  // Mark direct dependencies accurately based on root pubspec.yaml & lockfile
  final directDepNames = <String>{
    ...myPackage.dependencies.map((d) => d.name),
    if (generateDevDependencies)
      ...myPackage.devDependencies.map((d) => d.name),
  };
  for (final entry in packagesMap.entries) {
    final pkgName = entry.key.toString();
    final pkgData = entry.value;
    if (pkgData is Map) {
      final depType = pkgData['dependency']?.toString() ?? '';
      if (depType == 'direct main' ||
          (generateDevDependencies && depType == 'direct dev')) {
        directDepNames.add(pkgName);
      }
    }
  }

  final finalPackagesByName = <String, Package>{};
  for (final entry in packagesByName.entries) {
    final pkg = entry.value;
    final isDirect = directDepNames.contains(pkg.name);
    if (pkg.isDirectDependency != isDirect) {
      finalPackagesByName[entry.key] = pkg.copyWith(
        isDirectDependency: isDirect,
      );
    } else {
      finalPackagesByName[entry.key] = pkg;
    }
  }

  // Re-wire references to point to updated Package instances
  for (final pkg in finalPackagesByName.values) {
    pkg.updateDependencies(finalPackagesByName);
  }
  myPackage.updateDependencies(finalPackagesByName);

  return ProjectStructure(
    package: myPackage,
    allDependencies: finalPackagesByName.values.toList(),
    pubspecLockPath: resolvedLockPath,
  );
}

final String _sdkLicenseSeparator = '-' * 80;
final RegExp _sdkLicenseSeparatorPattern = RegExp(
  r'(?:^|\n)[ \t]*(?:-{80,}|={80,})[ \t]*(?:\n|$)',
);

void _splitSdkLicenses(Map<String, Package> packagesByName) {
  final targets = <String>[];
  if (packagesByName.containsKey('sky_engine')) {
    targets.add('sky_engine');
  } else {
    for (final entry in packagesByName.entries) {
      if (entry.value.isSdk &&
          entry.value.license != null &&
          _sdkLicenseSeparatorPattern.hasMatch(entry.value.license!)) {
        targets.add(entry.key);
      }
    }
  }

  for (final targetKey in targets) {
    final sdkPkg = packagesByName[targetKey];
    if (sdkPkg == null || sdkPkg.license == null) continue;

    final parts = sdkPkg.license!.split(_sdkLicenseSeparatorPattern);
    if (parts.length <= 1) continue;

    packagesByName.remove(targetKey);

    final licensesByComponent = <String, List<String>>{};
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final firstLine = trimmed
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (firstLine.isEmpty || RegExp(r'^[-=]+$').hasMatch(firstLine)) continue;
      licensesByComponent.putIfAbsent(firstLine, () => <String>[]).add(trimmed);
    }

    for (final entry in licensesByComponent.entries) {
      final component = entry.key;
      final name = '$targetKey/$component';
      final combinedLicense = entry.value.join('\n\n$_sdkLicenseSeparator\n\n');

      packagesByName[name] = Package(
        directory: sdkPkg.directory,
        name: name,
        description: '${sdkPkg.description} - $component',
        authors: sdkPkg.authors,
        isMarkdown: sdkPkg.isMarkdown,
        isSdk: true,
        isDirectDependency: sdkPkg.isDirectDependency,
        dependencies: <Package>[],
        devDependencies: <Package>[],
        homepage: sdkPkg.homepage,
        repository: sdkPkg.repository,
        version: sdkPkg.version,
        license: combinedLicense,
        spdxIdentifiers: detectSpdxIdentifiers(combinedLicense),
      );
    }
  }
}
