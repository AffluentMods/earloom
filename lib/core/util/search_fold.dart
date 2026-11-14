// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Folds text for searching and sorting: lower case, common Latin accents
/// removed, whitespace collapsed. "Émile Zola" and "emile  zola" fold to the
/// same string, so a search for either finds both.
String foldForSearch(String value) {
  final lower = value.toLowerCase();
  final out = StringBuffer();
  var lastWasSpace = true;
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final mapped = _accents[char] ?? char;
    final isSpace = mapped.trim().isEmpty;
    if (isSpace) {
      if (!lastWasSpace) out.write(' ');
      lastWasSpace = true;
    } else {
      out.write(mapped);
      lastWasSpace = false;
    }
  }
  return out.toString().trimRight();
}

const _accents = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', //
  'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i', //
  'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'œ': 'oe', //
  'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'þ': 'th', 'ð': 'd',
};
