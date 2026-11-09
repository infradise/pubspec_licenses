import 'dart:convert';

/// Top-level convenience function matching `package:yaml`'s `loadYaml`
/// signature for zero-dependency drop-in usage.
dynamic loadYaml(String source) => MiniYamlParser.parse(source);

/// A zero-dependency YAML subset parser tailored for `pubspec.yaml`,
/// `pubspec.lock`, and JSON/YAML configuration files.
class MiniYamlParser {
  const MiniYamlParser._();

  /// Parses [source] into standard Dart collections (`Map<String, dynamic>`,
  /// `List<dynamic>`) and primitives (`String`, `int`, `double`, `bool`,
  /// `null`).
  static dynamic parse(String source) {
    var cleaned = source;
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1);
    }
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final trimmed = cleaned.trim();
    if (trimmed.isEmpty) return null;

    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        return _parseFlowValue(trimmed);
      }
    }

    final rawLines = cleaned.split('\n');
    final state = _YamlParseState(rawLines);
    state.skipBlankAndComments();
    if (state.isAtEnd) return null;

    return state.parseNode(state.currentIndent);
  }

  /// Parses [source] and returns it as a `Map<String, dynamic>`.
  /// Returns an empty map if the source is empty or not a map.
  static Map<String, dynamic> parseMap(String source) {
    final result = parse(source);
    if (result is Map<String, dynamic>) return result;
    if (result is Map) {
      return result.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}

class _YamlParseState {
  _YamlParseState(this.lines);

  final List<String> lines;
  int index = 0;

  bool get isAtEnd => index >= lines.length;

  int get currentIndent => isAtEnd ? 0 : _countIndent(lines[index]);

  void skipBlankAndComments() {
    while (!isAtEnd) {
      final raw = lines[index];
      final stripped = _stripComment(raw).trim();
      if (stripped.isEmpty || stripped == '---' || stripped == '...') {
        index++;
        continue;
      }
      break;
    }
  }

  dynamic parseNode(int minIndent) {
    skipBlankAndComments();
    if (isAtEnd) return null;

    final line = _stripComment(lines[index]);
    final indent = _countIndent(line);
    if (indent < minIndent) return null;

    final content = line.substring(indent).trimRight();
    if (_isSequenceItem(content)) {
      return parseSequence(indent);
    }
    if (_findMappingColon(content) != -1) {
      return parseMapping(indent);
    }

    index++;
    return _parseScalarWithContinuation(content, indent);
  }

  List<dynamic> parseSequence(int seqIndent) {
    final list = <dynamic>[];
    while (!isAtEnd) {
      skipBlankAndComments();
      if (isAtEnd) break;

      final rawLine = lines[index];
      final line = _stripComment(rawLine);
      final indent = _countIndent(line);
      if (indent < seqIndent) break;
      if (indent > seqIndent) break;

      final content = line.substring(indent).trimRight();
      if (!_isSequenceItem(content)) break;

      index++;
      final afterDash =
          content.length > 1 ? content.substring(1).trimLeft() : '';
      final itemBaseIndent = indent +
          1 +
          (content.length > 1 ? _countIndent(content.substring(1)) : 1);

      if (afterDash.isEmpty) {
        skipBlankAndComments();
        if (!isAtEnd && _countIndent(_stripComment(lines[index])) > indent) {
          list.add(parseNode(_countIndent(_stripComment(lines[index]))));
        } else {
          list.add(null);
        }
        continue;
      }

      if ((afterDash.startsWith('{') || afterDash.startsWith('[')) &&
          _isFlowStart(afterDash)) {
        final flowText = _collectMultiLineFlow(afterDash);
        list.add(_parseFlowValue(flowText));
        continue;
      }

      final blockScalar = _tryParseBlockScalarHeader(afterDash, indent);
      if (blockScalar != null) {
        list.add(blockScalar);
        continue;
      }

      final colonIdx = _findMappingColon(afterDash);
      if (colonIdx != -1) {
        final itemMap = <String, dynamic>{};
        _parseMappingEntryInto(itemMap, afterDash, colonIdx, itemBaseIndent);
        while (!isAtEnd) {
          skipBlankAndComments();
          if (isAtEnd) break;
          final nextLine = _stripComment(lines[index]);
          final nextIndent = _countIndent(nextLine);
          if (nextIndent < itemBaseIndent) break;
          final nextContent = nextLine.substring(nextIndent).trimRight();
          if (_isSequenceItem(nextContent)) break;
          final nextColon = _findMappingColon(nextContent);
          if (nextColon == -1) break;
          index++;
          _parseMappingEntryInto(itemMap, nextContent, nextColon, nextIndent);
        }
        list.add(itemMap);
        continue;
      }

      list.add(_parseScalarWithContinuation(afterDash, indent));
    }
    return list;
  }

  Map<String, dynamic> parseMapping(int mapIndent) {
    final map = <String, dynamic>{};
    while (!isAtEnd) {
      skipBlankAndComments();
      if (isAtEnd) break;

      final rawLine = lines[index];
      final line = _stripComment(rawLine);
      final indent = _countIndent(line);
      if (indent < mapIndent) break;
      if (indent > mapIndent) {
        // Unexpected extra indent outside a value; skip safely to avoid infinite loop.
        index++;
        continue;
      }

      final content = line.substring(indent).trimRight();
      if (_isSequenceItem(content)) break;

      final colonIdx = _findMappingColon(content);
      if (colonIdx == -1) break;

      index++;
      _parseMappingEntryInto(map, content, colonIdx, indent);
    }
    return map;
  }

  void _parseMappingEntryInto(
    Map<String, dynamic> map,
    String content,
    int colonIdx,
    int keyIndent,
  ) {
    final rawKey = content.substring(0, colonIdx).trim();
    final key = _unquoteString(rawKey);
    final rawValue = content.substring(colonIdx + 1).trim();

    if (rawValue.isEmpty) {
      skipBlankAndComments();
      if (isAtEnd) {
        map[key] = null;
        return;
      }
      final nextLine = _stripComment(lines[index]);
      final nextIndent = _countIndent(nextLine);
      final nextContent = nextLine.substring(nextIndent).trimRight();

      if (nextIndent > keyIndent) {
        map[key] = parseNode(nextIndent);
      } else if (nextIndent == keyIndent && _isSequenceItem(nextContent)) {
        map[key] = parseSequence(nextIndent);
      } else {
        map[key] = null;
      }
      return;
    }

    final blockScalar = _tryParseBlockScalarHeader(rawValue, keyIndent);
    if (blockScalar != null) {
      map[key] = blockScalar;
      return;
    }

    if ((rawValue.startsWith('{') || rawValue.startsWith('[')) &&
        _isFlowStart(rawValue)) {
      final flowText = _collectMultiLineFlow(rawValue);
      map[key] = _parseFlowValue(flowText);
      return;
    }

    map[key] = _parseScalarWithContinuation(rawValue, keyIndent);
  }

  String _collectMultiLineFlow(String initial) {
    var accumulated = initial;
    while (!_isBalancedFlow(accumulated) && !isAtEnd) {
      final nextRaw = _stripComment(lines[index]).trim();
      index++;
      if (nextRaw.isNotEmpty) {
        accumulated = '$accumulated $nextRaw';
      }
    }
    return accumulated;
  }

  String? _tryParseBlockScalarHeader(String rawValue, int parentIndent) {
    if (!rawValue.startsWith('|') && !rawValue.startsWith('>')) {
      return null;
    }
    final style = rawValue[0];
    final rest = rawValue.substring(1).trim();
    String chomp = 'clip';
    if (rest.isNotEmpty) {
      if (rest == '-' || rest == '+') {
        chomp = rest;
      } else if (RegExp(r'^[+-]?\d+[+-]?$').hasMatch(rest)) {
        if (rest.contains('-')) chomp = '-';
        if (rest.contains('+')) chomp = '+';
      } else {
        return null;
      }
    }

    final collectedLines = <String>[];
    int? blockIndent;

    while (!isAtEnd) {
      final rawLine = lines[index];
      if (rawLine.trim().isEmpty) {
        collectedLines.add('');
        index++;
        continue;
      }
      final indent = _countIndent(rawLine);
      if (blockIndent == null) {
        if (indent <= parentIndent) {
          break;
        }
        blockIndent = indent;
      }
      if (indent < blockIndent) {
        break;
      }
      collectedLines.add(rawLine.substring(blockIndent));
      index++;
    }

    // Trim trailing blank lines unless chomp == '+'
    var trailingNewlines = 0;
    while (collectedLines.isNotEmpty && collectedLines.last.isEmpty) {
      collectedLines.removeLast();
      trailingNewlines++;
    }

    if (collectedLines.isEmpty) {
      return chomp == '+' && trailingNewlines > 0
          ? '\n' * trailingNewlines
          : '';
    }

    String body;
    if (style == '|') {
      body = collectedLines.join('\n');
    } else {
      // Folded '>' style
      final buffer = StringBuffer();
      for (var i = 0; i < collectedLines.length; i++) {
        final line = collectedLines[i];
        if (i == 0) {
          buffer.write(line);
        } else if (line.isEmpty) {
          buffer.write('\n');
        } else if (collectedLines[i - 1].isEmpty) {
          buffer.write(line);
        } else if (line.startsWith(' ') ||
            collectedLines[i - 1].startsWith(' ')) {
          buffer.write('\n$line');
        } else {
          buffer.write(' $line');
        }
      }
      body = buffer.toString();
    }

    if (chomp == '-') {
      return body;
    } else if (chomp == '+') {
      return '$body\n${'\n' * trailingNewlines}';
    } else {
      // For pubspec fields like description, returning the clean body (or single
      // trailing newline when multi-paragraph) avoids unwanted trailing newline
      // artifacts while keeping multiline block content intact.
      return body;
    }
  }

  dynamic _parseScalarWithContinuation(String firstLine, int parentIndent) {
    final trimmed = firstLine.trim();
    if ((trimmed.startsWith('"') &&
            trimmed.endsWith('"') &&
            trimmed.length >= 2) ||
        (trimmed.startsWith("'") &&
            trimmed.endsWith("'") &&
            trimmed.length >= 2)) {
      return _parseScalar(trimmed);
    }

    // Handle multi-line quoted string if opening quote is not closed on first line
    if ((trimmed.startsWith('"') && !_isClosedQuote(trimmed, '"')) ||
        (trimmed.startsWith("'") && !_isClosedQuote(trimmed, "'"))) {
      final quoteChar = trimmed[0];
      final buffer = StringBuffer(trimmed);
      while (!isAtEnd && !_isClosedQuote(buffer.toString(), quoteChar)) {
        final nextRaw = lines[index].trim();
        index++;
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(nextRaw);
      }
      return _parseScalar(buffer.toString());
    }

    // Check for multi-line plain scalar continuation lines
    final parts = <String>[trimmed];
    while (!isAtEnd) {
      final nextRaw = lines[index];
      final nextStripped = _stripComment(nextRaw);
      if (nextStripped.trim().isEmpty) break;
      final nextIndent = _countIndent(nextStripped);
      if (nextIndent <= parentIndent) break;
      final nextContent = nextStripped.substring(nextIndent).trim();
      if (_isSequenceItem(nextContent) ||
          _findMappingColon(nextContent) != -1) {
        break;
      }
      parts.add(nextContent);
      index++;
    }

    if (parts.length == 1) {
      return _parseScalar(parts.first);
    }
    return parts.join(' ');
  }
}

int _countIndent(String line) {
  var count = 0;
  while (count < line.length && line[count] == ' ') {
    count++;
  }
  return count;
}

bool _isSequenceItem(String content) {
  if (!content.startsWith('-')) return false;
  if (content.length == 1) return true;
  final second = content[1];
  return second == ' ' || second == '\t';
}

int _findMappingColon(String content) {
  bool inSingle = false;
  bool inDouble = false;
  int braceDepth = 0;
  int bracketDepth = 0;

  for (var i = 0; i < content.length; i++) {
    final ch = content[i];
    if (inSingle) {
      if (ch == "'") {
        if (i + 1 < content.length && content[i + 1] == "'") {
          i++;
        } else {
          inSingle = false;
        }
      }
      continue;
    }
    if (inDouble) {
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }

    if (ch == "'") {
      inSingle = true;
    } else if (ch == '"') {
      inDouble = true;
    } else if (ch == '{') {
      braceDepth++;
    } else if (ch == '}') {
      if (braceDepth > 0) braceDepth--;
    } else if (ch == '[') {
      bracketDepth++;
    } else if (ch == ']') {
      if (bracketDepth > 0) bracketDepth--;
    } else if (ch == ':' && braceDepth == 0 && bracketDepth == 0) {
      if (i + 1 == content.length ||
          content[i + 1] == ' ' ||
          content[i + 1] == '\t') {
        return i;
      }
    }
  }
  return -1;
}

String _stripComment(String line) {
  bool inSingle = false;
  bool inDouble = false;

  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inSingle) {
      if (ch == "'") {
        if (i + 1 < line.length && line[i + 1] == "'") {
          i++;
        } else {
          inSingle = false;
        }
      }
      continue;
    }
    if (inDouble) {
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }

    if (ch == "'") {
      inSingle = true;
    } else if (ch == '"') {
      inDouble = true;
    } else if (ch == '#') {
      if (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t') {
        return line.substring(0, i);
      }
    }
  }
  return line;
}

bool _isClosedQuote(String text, String quote) {
  if (text.length < 2 || !text.startsWith(quote)) return false;
  if (quote == "'") {
    var i = 1;
    while (i < text.length) {
      if (text[i] == "'") {
        if (i + 1 < text.length && text[i + 1] == "'") {
          i += 2;
          continue;
        }
        return i == text.length - 1;
      }
      i++;
    }
    return false;
  } else {
    var i = 1;
    while (i < text.length) {
      if (text[i] == r'\') {
        i += 2;
        continue;
      }
      if (text[i] == '"') {
        return i == text.length - 1;
      }
      i++;
    }
    return false;
  }
}

bool _isFlowStart(String text) {
  return text.startsWith('{') || text.startsWith('[');
}

bool _isBalancedFlow(String text) {
  bool inSingle = false;
  bool inDouble = false;
  int braces = 0;
  int brackets = 0;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inSingle) {
      if (ch == "'") {
        if (i + 1 < text.length && text[i + 1] == "'") {
          i++;
        } else {
          inSingle = false;
        }
      }
      continue;
    }
    if (inDouble) {
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (ch == "'") {
      inSingle = true;
    } else if (ch == '"') {
      inDouble = true;
    } else if (ch == '{') {
      braces++;
    } else if (ch == '}') {
      braces--;
    } else if (ch == '[') {
      brackets++;
    } else if (ch == ']') {
      brackets--;
    }
  }
  return braces <= 0 && brackets <= 0 && !inSingle && !inDouble;
}

dynamic _parseFlowValue(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return <String, dynamic>{};
    final parts = _splitFlowElements(inner);
    final map = <String, dynamic>{};
    for (final part in parts) {
      final entryText = part.trim();
      if (entryText.isEmpty) continue;
      final colonIdx = _findFlowColon(entryText);
      if (colonIdx == -1) continue;
      final k = _unquoteString(entryText.substring(0, colonIdx).trim());
      final v = _parseFlowValue(entryText.substring(colonIdx + 1).trim());
      map[k] = v;
    }
    return map;
  }
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return <dynamic>[];
    final parts = _splitFlowElements(inner);
    final list = <dynamic>[];
    for (final part in parts) {
      final itemText = part.trim();
      if (itemText.isEmpty) continue;
      list.add(_parseFlowValue(itemText));
    }
    return list;
  }
  return _parseScalar(trimmed);
}

int _findFlowColon(String text) {
  bool inSingle = false;
  bool inDouble = false;
  int braces = 0;
  int brackets = 0;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inSingle) {
      if (ch == "'") {
        if (i + 1 < text.length && text[i + 1] == "'") {
          i++;
        } else {
          inSingle = false;
        }
      }
      continue;
    }
    if (inDouble) {
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (ch == "'") {
      inSingle = true;
    } else if (ch == '"') {
      inDouble = true;
    } else if (ch == '{') {
      braces++;
    } else if (ch == '}') {
      braces--;
    } else if (ch == '[') {
      brackets++;
    } else if (ch == ']') {
      brackets--;
    } else if (ch == ':' && braces == 0 && brackets == 0) {
      return i;
    }
  }
  return -1;
}

List<String> _splitFlowElements(String inner) {
  final result = <String>[];
  bool inSingle = false;
  bool inDouble = false;
  int braces = 0;
  int brackets = 0;
  var start = 0;

  for (var i = 0; i < inner.length; i++) {
    final ch = inner[i];
    if (inSingle) {
      if (ch == "'") {
        if (i + 1 < inner.length && inner[i + 1] == "'") {
          i++;
        } else {
          inSingle = false;
        }
      }
      continue;
    }
    if (inDouble) {
      if (ch == r'\') {
        i++;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (ch == "'") {
      inSingle = true;
    } else if (ch == '"') {
      inDouble = true;
    } else if (ch == '{') {
      braces++;
    } else if (ch == '}') {
      braces--;
    } else if (ch == '[') {
      brackets++;
    } else if (ch == ']') {
      brackets--;
    } else if (ch == ',' && braces == 0 && brackets == 0) {
      result.add(inner.substring(start, i));
      start = i + 1;
    }
  }
  if (start <= inner.length) {
    final tail = inner.substring(start);
    if (tail.trim().isNotEmpty) {
      result.add(tail);
    }
  }
  return result;
}

dynamic _parseScalar(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == 'null' || s == 'Null' || s == 'NULL' || s == '~') {
    return null;
  }
  if (s == 'true' || s == 'True' || s == 'TRUE') {
    return true;
  }
  if (s == 'false' || s == 'False' || s == 'FALSE') {
    return false;
  }

  if ((s.startsWith('"') && s.endsWith('"') && s.length >= 2) ||
      (s.startsWith("'") && s.endsWith("'") && s.length >= 2)) {
    return _unquoteString(s);
  }

  final intVal = int.tryParse(s);
  if (intVal != null) return intVal;

  final doubleVal = double.tryParse(s);
  if (doubleVal != null) return doubleVal;

  return s;
}

String _unquoteString(String s) {
  if (s.length < 2) return s;
  if (s.startsWith("'") && s.endsWith("'")) {
    return s.substring(1, s.length - 1).replaceAll("''", "'");
  }
  if (s.startsWith('"') && s.endsWith('"')) {
    final inner = s.substring(1, s.length - 1);
    final buffer = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      final ch = inner[i];
      if (ch == r'\' && i + 1 < inner.length) {
        i++;
        final next = inner[i];
        switch (next) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case '"':
            buffer.write('"');
          case r'\':
            buffer.write(r'\');
          case '/':
            buffer.write('/');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case 'u':
            if (i + 4 < inner.length) {
              final hex = inner.substring(i + 1, i + 5);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) {
                buffer.writeCharCode(code);
                i += 4;
              } else {
                buffer.write(r'\u');
              }
            } else {
              buffer.write(r'\u');
            }
          default:
            buffer.write(next);
        }
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }
  return s;
}
