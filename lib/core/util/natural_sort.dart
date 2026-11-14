// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Compares strings the way people expect file and book names to sort:
/// runs of digits compare by value ("2" before "10"), everything else
/// case-insensitively. Ties fall back to the plain comparison so the order is
/// total and stable.
int compareNatural(String a, String b) {
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final startA = i, startB = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final byValue = _compareDigitRuns(a.substring(startA, i), b.substring(startB, j));
      if (byValue != 0) return byValue;
      continue;
    }
    final la = _lower(ca), lb = _lower(cb);
    if (la != lb) return la.compareTo(lb);
    i++;
    j++;
  }
  final byLength = (a.length - i).compareTo(b.length - j);
  if (byLength != 0) return byLength;
  return a.compareTo(b);
}

/// Pads every run of digits to a fixed width, so a plain (SQL) string sort of
/// the result is a natural sort: "book 2" -> "book 0000000002".
String padNumbers(String value, {int width = 10}) {
  return value.replaceAllMapped(RegExp(r'\d+'), (m) {
    final digits = m[0]!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return digits.length >= width ? digits : digits.padLeft(width, '0');
  });
}

int _compareDigitRuns(String a, String b) {
  final ta = a.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final tb = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (ta.length != tb.length) return ta.length.compareTo(tb.length);
  final byDigits = ta.compareTo(tb);
  if (byDigits != 0) return byDigits;
  // "01" and "1" are equal in value: fewer leading zeros first.
  return a.length.compareTo(b.length);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

int _lower(int c) => (c >= 0x41 && c <= 0x5A) ? c + 32 : String.fromCharCode(c).toLowerCase().codeUnitAt(0);
