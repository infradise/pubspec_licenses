import 'dart:io';

/// Pure Dart cross-platform path manipulation utilities.
///
/// Replaces `package:path` with zero external dependencies while supporting
/// POSIX (`/`) and Windows (`\`, drive letters, UNC) paths.

final RegExp _windowsDrivePrefix = RegExp(r'^[a-zA-Z]:[\\/]');
final RegExp _windowsDriveOnly = RegExp(r'^[a-zA-Z]:$');
final RegExp _uncPrefix = RegExp(r'^\\\\[^\\]+\\[^\\]+');
final RegExp _anySeparator = RegExp(r'[\\/]');

/// Returns the active path separator for [pathHint], defaulting to
/// [Platform.pathSeparator].
String _separatorFor(String pathHint) {
  if (Platform.isWindows) return r'\';
  if (_windowsDrivePrefix.hasMatch(pathHint) ||
      pathHint.startsWith(r'\\') ||
      (pathHint.contains(r'\') && !pathHint.contains('/'))) {
    return r'\';
  }
  return '/';
}

/// Returns `true` if [path] is an absolute path (POSIX `/`, Windows `C:\`,
/// `C:/`, or UNC `\\`).
bool isAbsolute(String path) {
  if (path.isEmpty) return false;
  if (path.startsWith('/') || path.startsWith(r'\')) return true;
  if (_windowsDrivePrefix.hasMatch(path)) return true;
  return false;
}

/// Returns `true` if [path] is a relative path.
bool isRelative(String path) => !isAbsolute(path);

/// Joins the given path parts into a single path using the appropriate platform
/// separator.
///
/// Just like `package:path`, if any subsequent part is an absolute path, it
/// replaces the preceding path.
String join(
  String part1, [
  String? part2,
  String? part3,
  String? part4,
  String? part5,
  String? part6,
  String? part7,
  String? part8,
]) {
  return joinAll(<String?>[
    part1,
    part2,
    part3,
    part4,
    part5,
    part6,
    part7,
    part8,
  ].whereType<String>());
}

/// Joins all [parts] into a single path string.
String joinAll(Iterable<String> parts) {
  final filtered = <String>[];
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (isAbsolute(part)) {
      filtered.clear();
    }
    filtered.add(part);
  }
  if (filtered.isEmpty) return '';

  final sep = _separatorFor(filtered.first);
  final buffer = StringBuffer();
  for (var i = 0; i < filtered.length; i++) {
    var segment = filtered[i];
    if (i > 0) {
      while (segment.startsWith('/') || segment.startsWith(r'\')) {
        segment = segment.substring(1);
      }
    }
    if (segment.isEmpty) continue;
    if (buffer.isNotEmpty) {
      final current = buffer.toString();
      if (!current.endsWith('/') && !current.endsWith(r'\')) {
        buffer.write(sep);
      }
    }
    buffer.write(segment);
  }
  return buffer.toString();
}

/// Normalizes [path], resolving `.` and `..` segments and removing redundant
/// separators.
String normalize(String path) {
  if (path.isEmpty) return '.';

  final sep = _separatorFor(path);
  String root = '';
  String remainder = path;

  if (_uncPrefix.hasMatch(path)) {
    final match = _uncPrefix.firstMatch(path)!;
    root = '${match.group(0)!}$sep';
    remainder = path.substring(match.end);
  } else if (_windowsDrivePrefix.hasMatch(path)) {
    root = '${path.substring(0, 2)}$sep';
    remainder = path.substring(3);
  } else if (_windowsDriveOnly.hasMatch(path)) {
    return '${path.substring(0, 2)}.';
  } else if (path.startsWith('/') || path.startsWith(r'\')) {
    root = sep;
    remainder = path.substring(1);
  }

  final isAbs = root.isNotEmpty;
  final rawSegments = remainder.split(_anySeparator);
  final stack = <String>[];

  for (final seg in rawSegments) {
    if (seg.isEmpty || seg == '.') {
      continue;
    }
    if (seg == '..') {
      if (stack.isNotEmpty && stack.last != '..') {
        stack.removeLast();
      } else if (!isAbs) {
        stack.add('..');
      }
    } else {
      stack.add(seg);
    }
  }

  if (isAbs) {
    return '$root${stack.join(sep)}';
  }
  if (stack.isEmpty) {
    return '.';
  }
  return stack.join(sep);
}

/// Gets the part of [path] before the last separator.
String dirname(String path) {
  if (path.isEmpty) return '.';

  final sep = _separatorFor(path);

  if (_uncPrefix.hasMatch(path)) {
    final match = _uncPrefix.firstMatch(path)!;
    final afterUnc =
        path.substring(match.end).replaceAll(RegExp(r'[\\/]+$'), '');
    if (afterUnc.isEmpty) {
      return match.group(0)!;
    }
  }

  if (_windowsDrivePrefix.hasMatch(path)) {
    final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
    if (trimmed.length <= 2) {
      return '${path.substring(0, 2)}$sep';
    }
    final lastSep = trimmed.lastIndexOf(_anySeparator);
    if (lastSep <= 2) {
      return '${path.substring(0, 2)}$sep';
    }
    return trimmed.substring(0, lastSep);
  }

  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (trimmed.isEmpty) {
    return sep;
  }

  final lastSep = trimmed.lastIndexOf(_anySeparator);
  if (lastSep == -1) {
    return '.';
  }
  if (lastSep == 0) {
    return sep;
  }
  final parent =
      trimmed.substring(0, lastSep).replaceAll(RegExp(r'[\\/]+$'), '');
  return parent.isEmpty ? sep : parent;
}

/// Gets the part of [path] after the last separator.
String basename(String path) {
  if (path.isEmpty) return '';

  if (_windowsDrivePrefix.hasMatch(path)) {
    final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
    if (trimmed.length <= 2) {
      return '${path.substring(0, 2)}${_separatorFor(path)}';
    }
    final lastSep = trimmed.lastIndexOf(_anySeparator);
    return trimmed.substring(lastSep + 1);
  }

  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (trimmed.isEmpty) {
    return _separatorFor(path);
  }

  final lastSep = trimmed.lastIndexOf(_anySeparator);
  if (lastSep == -1) {
    return trimmed;
  }
  return trimmed.substring(lastSep + 1);
}

/// Gets the file extension of [path] (including the leading `.`), or `''` if
/// it has no extension.
String extension(String path) {
  final base = basename(path);
  final dotIndex = base.lastIndexOf('.');
  if (dotIndex <= 0) return '';
  return base.substring(dotIndex);
}

/// Gets the [basename] of [path] without its file extension.
String basenameWithoutExtension(String path) {
  final base = basename(path);
  final dotIndex = base.lastIndexOf('.');
  if (dotIndex <= 0) return base;
  return base.substring(0, dotIndex);
}

/// Returns a normalized absolute path by joining [Directory.current.path] with
/// the given path parts if not already absolute.
String absolute(
  String part1, [
  String? part2,
  String? part3,
  String? part4,
]) {
  final joined = join(part1, part2, part3, part4);
  if (isAbsolute(joined)) {
    return normalize(joined);
  }
  return normalize(join(Directory.current.path, joined));
}
