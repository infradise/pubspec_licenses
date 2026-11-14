/// Pure Dart SPDX license identifier detection engine.
///
/// Replaces `package:pana` for detecting SPDX license identifiers from raw
/// `LICENSE` file contents with zero external dependencies.
library;

final RegExp _spdxTagRegex = RegExp(
  r'SPDX-License-Identifier:\s*([^\r\n]+)',
  caseSensitive: false,
);

final RegExp _sectionDividerRegex = RegExp(
  r'(?:^|\n)[ \t]*(?:-{3,}|={3,}|\*{3,})[ \t]*(?:\n|$)',
);

/// Detects one or more SPDX license identifiers from [licenseText].
///
/// Returns a deduplicated list of detected SPDX identifiers in order of
/// discovery, or an empty list `[]` if [licenseText] is empty or unrecognized
/// (matching `dart_pubspec_licenses` v3.2.0 and `pana` behavior).
List<String> detectSpdxIdentifiers(String licenseText) {
  if (licenseText.trim().isEmpty) {
    return <String>[];
  }

  final found = <String>[];
  void addId(String id) {
    if (id.isNotEmpty && !found.contains(id)) {
      found.add(id);
    }
  }

  // 1. Check explicit SPDX-License-Identifier tags first.
  for (final match in _spdxTagRegex.allMatches(licenseText)) {
    final rawExpr = match.group(1)?.trim() ?? '';
    for (final token in _extractIdsFromSpdxExpression(rawExpr)) {
      addId(token);
    }
  }

  // Check if the document as a whole is MPL-2.0 so that Setext underlines
  // inside MPL-2.0 (=== / ---) do not cause Section 1.12 ("Secondary License")
  // to be misclassified as a standalone AGPL/GPL/LGPL license.
  final fullNorm = _normalizeText(licenseText);
  final isMpl2Document = ((fullNorm.contains('mozilla public license') &&
              (fullNorm.contains('version 2.0') ||
                  fullNorm.contains('v. 2.0'))) ||
          fullNorm.contains('mozilla.org/mpl/2.0')) &&
      fullNorm.contains('secondary license');

  // 2. Split multi-license files by horizontal dividers (---, ===, ***) and
  // analyze each section independently.
  final sections = licenseText.split(_sectionDividerRegex);
  for (final section in sections) {
    for (final id in _detectInSection(
      section,
      suppressSecondaryGplInMpl: isMpl2Document,
    )) {
      addId(id);
    }
  }

  // 3. Also run detection on the full text in case a divider appeared inside a
  // single license header/title block.
  if (found.isEmpty) {
    for (final id in _detectInSection(
      licenseText,
      suppressSecondaryGplInMpl: isMpl2Document,
    )) {
      addId(id);
    }
  }

  return found;
}

List<String> _extractIdsFromSpdxExpression(String expression) {
  var cleaned = expression
      .replaceAll('*/', '')
      .replaceAll('-->', '')
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .trim();
  final hashIdx = cleaned.indexOf('#');
  if (hashIdx != -1) {
    cleaned = cleaned.substring(0, hashIdx).trim();
  }

  final tokens = cleaned.split(RegExp(r'\s+'));
  final result = <String>[];
  for (var token in tokens) {
    token = token.replaceAll(RegExp(r'^[,;]+|[,;.]+$'), '');
    if (token.isEmpty) continue;
    final upper = token.toUpperCase();
    if (upper == 'AND' || upper == 'OR' || upper == 'WITH') continue;
    result.add(token);
  }
  return result;
}

List<String> _detectInSection(
  String section, {
  bool suppressSecondaryGplInMpl = false,
}) {
  final norm = _normalizeText(section);
  if (norm.isEmpty) return const <String>[];

  final detected = <String>[];

  // Unicode-DFS-2016 (check before MIT since Unicode license shares a similar grant opening)
  final isUnicode = norm.contains('unicode inc. license agreement') ||
      norm.contains('unicode inc license agreement') ||
      norm.contains('unicode data files include all data files');
  if (isUnicode) {
    detected.add('Unicode-DFS-2016');
  }

  // MIT-0 vs MIT License
  if (!isUnicode) {
    if (norm.contains(
          'permission is hereby granted free of charge to any person obtaining a copy',
        ) &&
        norm.contains('without restriction including without limitation')) {
      if (norm.contains('mit no attribution') ||
          (!norm.contains(
                'the above copyright notice and this permission notice',
              ) &&
              norm.contains('mit-0'))) {
        detected.add('MIT-0');
      } else {
        detected.add('MIT');
      }
    } else if (norm.contains('mit license') &&
        norm.contains(
          'furnished to do so subject to the following conditions',
        )) {
      detected.add('MIT');
    }
  }

  // BSD family (BSD-4-Clause, BSD-3-Clause, BSD-2-Clause, BSD-1-Clause)
  if (norm.contains(
    'redistribution and use in source and binary forms with or without modification are permitted',
  )) {
    final hasClause4 = norm.contains(
      'all advertising materials mentioning features or use of this software must display',
    );
    final hasClause3 = norm.contains(
          'may be used to endorse or promote products derived from',
        ) ||
        norm.contains(
          'may not be used to endorse or promote products derived from',
        ) ||
        norm.contains(
          'nor the names of its contributors may be used to endorse',
        );
    final hasClause2 = norm.contains(
      'redistributions in binary form must reproduce the above copyright notice',
    );

    if (hasClause4) {
      detected.add('BSD-4-Clause');
    } else if (hasClause3) {
      detected.add('BSD-3-Clause');
    } else if (hasClause2) {
      detected.add('BSD-2-Clause');
    } else if (norm.contains(
      'redistributions of source code must retain the above copyright notice',
    )) {
      detected.add('BSD-1-Clause');
    }
  }

  // Apache-2.0
  if ((norm.contains('apache license') && norm.contains('version 2.0')) ||
      norm.contains('apache.org/licenses/license-2.0') ||
      norm.contains('licensed under the apache license version 2.0')) {
    detected.add('Apache-2.0');
  }

  // ISC vs 0BSD
  if (norm.contains('permission to use copy modify and') &&
      norm.contains(
        'distribute this software for any purpose with or without fee is hereby granted',
      )) {
    if (norm.contains(
      'provided that the above copyright notice and this permission notice appear',
    )) {
      detected.add('ISC');
    } else {
      detected.add('0BSD');
    }
  }

  // MPL-2.0
  final isMpl2Section = (norm.contains('mozilla public license') &&
          (norm.contains('version 2.0') || norm.contains('v. 2.0'))) ||
      norm.contains('mozilla.org/mpl/2.0');
  if (isMpl2Section) {
    detected.add('MPL-2.0');
  }

  // Strip MPL-2.0 Section 1.12 "Secondary License" definition clause before
  // checking GPL/LGPL/AGPL so it never triggers a false positive.
  final gplNorm = norm.replaceAll(
    RegExp(
      r'secondary license\s+means either the gnu general public license.*?(?:later versions of those licenses|\.)',
    ),
    '',
  );
  final isOnlyMplSecondaryDefinition =
      (suppressSecondaryGplInMpl || isMpl2Section) &&
          !gplNorm.contains(
            'everyone is permitted to copy and distribute verbatim copies',
          ) &&
          !gplNorm.contains('under the terms of the gnu');

  // AGPL / LGPL / GPL
  if (!isOnlyMplSecondaryDefinition) {
    if (gplNorm.contains('gnu affero general public license')) {
      if (gplNorm.contains(
            'either version 3 of the license or at your option any later version',
          ) &&
          !gplNorm.contains('version 3 19 november 2007')) {
        detected.add('AGPL-3.0-or-later');
      } else {
        detected.add('AGPL-3.0-only');
      }
    } else if (gplNorm.contains('gnu lesser general public license') ||
        gplNorm.contains('gnu library general public license')) {
      if (gplNorm.contains('version 3') || gplNorm.contains('29 june 2007')) {
        detected.add('LGPL-3.0-only');
      } else if (gplNorm.contains('version 2.1') ||
          gplNorm.contains('february 1999')) {
        detected.add('LGPL-2.1-only');
      }
    } else if (gplNorm.contains('gnu general public license')) {
      if (gplNorm.contains('version 3 29 june 2007')) {
        detected.add('GPL-3.0-only');
      } else if (gplNorm.contains(
        'either version 3 of the license or at your option any later version',
      )) {
        detected.add('GPL-3.0-or-later');
      } else if (gplNorm.contains('version 3')) {
        detected.add('GPL-3.0-only');
      } else if (gplNorm.contains('version 2 june 1991') ||
          gplNorm.contains('version 2')) {
        detected.add('GPL-2.0-only');
      }
    }
  }

  // EPL-2.0 / EPL-1.0
  if (norm.contains('eclipse public license')) {
    if (norm.contains('v 2.0') ||
        norm.contains('version 2.0') ||
        norm.contains('epl-2.0')) {
      detected.add('EPL-2.0');
    } else if (norm.contains('v 1.0') ||
        norm.contains('version 1.0') ||
        norm.contains('epl-1.0')) {
      detected.add('EPL-1.0');
    }
  }

  // Unlicense
  if (norm.contains(
        'this is free and unencumbered software released into the public domain',
      ) ||
      norm.contains('unlicense.org')) {
    detected.add('Unlicense');
  }

  // CC0-1.0 & CC-BY-4.0
  if (norm.contains('cc0 1.0 universal') ||
      norm.contains('creativecommons.org/publicdomain/zero/1.0')) {
    detected.add('CC0-1.0');
  } else if (norm.contains('creative commons attribution 4.0 international') ||
      norm.contains('creativecommons.org/licenses/by/4.0')) {
    detected.add('CC-BY-4.0');
  }

  // Zlib
  if (norm.contains('the origin of this software must not be misrepresented') &&
      norm.contains('altered source versions must be plainly marked as such') &&
      norm.contains(
        'this notice may not be removed or altered from any source distribution',
      )) {
    detected.add('Zlib');
  }

  // BSL-1.0 (Boost Software License 1.0)
  if ((norm.contains('boost software license') &&
          norm.contains('version 1.0')) ||
      norm.contains(
        'permission is hereby granted free of charge to any person or organization obtaining a copy of the software and accompanying documentation covered by this license',
      )) {
    detected.add('BSL-1.0');
  }

  // OFL-1.1 (SIL Open Font License 1.1)
  if ((norm.contains('sil open font license') &&
          norm.contains('version 1.1')) ||
      (norm.contains('open font license') &&
          norm.contains(
            'no modified version of the font software may use the reserved font name',
          ))) {
    detected.add('OFL-1.1');
  }

  // WTFPL
  if (norm.contains('do what the fuck you want to public license')) {
    detected.add('WTFPL');
  }

  return detected;
}

String _normalizeText(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'^\s*//+', multiLine: true), ' ')
      .replaceAll(RegExp(r'[,;:()"' "'" r'\[\]{}*#<>`~]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
