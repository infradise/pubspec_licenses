import 'package.dart';

/// Represents the structure of a Dart/Flutter project with its dependencies.
///
/// Contains the main [package] information and all resolved [allDependencies],
/// along with the path to the `pubspec.lock` file.
class ProjectStructure {
  /// Creates a [ProjectStructure] instance.
  const ProjectStructure({
    required this.package,
    required this.allDependencies,
    this.pubspecLockPath = '',
  });

  /// The main package of the project.
  final Package package;

  /// All dependencies including transitive ones.
  final List<Package> allDependencies;

  /// The path to the `pubspec.lock` file used to resolve dependencies.
  final String pubspecLockPath;

  /// Direct runtime dependencies of the root [package].
  List<Package> get dependencies => package.dependencies;

  /// Direct dev dependencies of the root [package].
  List<Package> get devDependencies => package.devDependencies;

  /// Converts the project structure to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    final directNames = package.dependencies.map((d) => d.name).toSet();
    return <String, dynamic>{
      'package': package.toJson(isDirectDependency: false),
      'pubspecLockPath': pubspecLockPath,
      'allDependencies': allDependencies
          .map(
              (d) => d.toJson(isDirectDependency: directNames.contains(d.name)))
          .toList(),
    };
  }
}
