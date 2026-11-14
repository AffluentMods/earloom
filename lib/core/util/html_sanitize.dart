// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Reduces server-provided HTML (descriptions, show notes) to a safe subset:
/// paragraphs, line breaks, bold, italic and links.
///
/// The result is not HTML: it is a small tree of plain text runs that the UI
/// draws as text. Scripts, styles, images, event handlers and every unknown
/// tag are dropped (their text kept, except for script and style), and only
/// http, https and mailto links survive. Nothing from the input is ever
/// interpreted as markup again, so there is nothing left to inject.
library;

/// A run of text with one style.
final class SafeRun {
  const SafeRun(this.text, {this.bold = false, this.italic = false, this.link});

  final String text;
  final bool bold;
  final bool italic;

  /// Only http, https or mailto.
  final Uri? link;

  @override
  String toString() =>
      'SafeRun($text${bold ? ', bold' : ''}${italic ? ', italic' : ''}${link == null ? '' : ', $link'})';
}

/// One paragraph: runs, where line breaks are `\n` inside the text.
final class SafeParagraph {
  const SafeParagraph(this.runs);
  final List<SafeRun> runs;

  String get text => runs.map((r) => r.text).join();
}

final class SafeHtml {
  const SafeHtml(this.paragraphs);

  static const empty = SafeHtml([]);

  final List<SafeParagraph> paragraphs;

  bool get isEmpty => paragraphs.isEmpty;

  /// Paragraphs separated by blank lines, for copying and plain previews.
  String get plainText => paragraphs.map((p) => p.text).join('\n\n');
}

/// Parses [input], HTML or plain text, into [SafeHtml]. Plain text (from
/// file tags) keeps its line breaks; blank lines start paragraphs.
SafeHtml sanitizeHtml(String? input) {
  if (input == null || input.trim().isEmpty) return SafeHtml.empty;
  if (!_looksLikeHtml.hasMatch(input)) return _plain(input);
  return _HtmlReducer(input).run();
}

final _looksLikeHtml = RegExp(r'<\s*/?\s*[a-zA-Z!]');

SafeHtml _plain(String input) {
  final normalized = decodeEntities(input).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return SafeHtml([
    for (final block in normalized.split(RegExp(r'\n\s*\n')))
      if (block.trim().isNotEmpty)
        SafeParagraph([
          SafeRun(block.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim()).join('\n')),
        ]),
  ]);
}

/// Tags that end a paragraph.
const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'blockquote',
  'ul',
  'ol',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'table',
  'tr',
  'hr',
};

const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// Tags whose content is dropped along with them.
const _droppedWithContent = {
  'script',
  'style',
  'noscript',
  'template',
  'iframe',
  'object',
  'embed',
  'svg',
  'math',
  'head',
  'title',
  'textarea',
  'select',
};

class _HtmlReducer {
  _HtmlReducer(this.input);

  final String input;
  final _paragraphs = <SafeParagraph>[];
  var _runs = <SafeRun>[];
  var _bold = 0;
  var _italic = 0;
  final _links = <Uri?>[];

  SafeHtml run() {
    var i = 0;
    while (i < input.length) {
      final lt = input.indexOf('<', i);
      if (lt < 0) {
        _text(input.substring(i));
        break;
      }
      if (lt > i) _text(input.substring(i, lt));
      // Comments, doctype, CDATA: skip to their end.
      if (input.startsWith('<!--', lt)) {
        final end = input.indexOf('-->', lt + 4);
        i = end < 0 ? input.length : end + 3;
        continue;
      }
      if (input.startsWith('<!', lt) || input.startsWith('<?', lt)) {
        final end = input.indexOf('>', lt);
        i = end < 0 ? input.length : end + 1;
        continue;
      }
      final tag = _tagAt(lt);
      if (tag == null) {
        // A lone "<" that starts no tag is text.
        _text('<');
        i = lt + 1;
        continue;
      }
      i = tag.end;
      if (!tag.closing && _droppedWithContent.contains(tag.name)) {
        i = _skipContent(tag.name, i);
        continue;
      }
      _handle(tag);
    }
    _endParagraph();
    return SafeHtml(_paragraphs);
  }

  /// Skips to after `</name>`, or to the end when it is never closed.
  int _skipContent(String name, int from) {
    final close = RegExp('<\\s*/\\s*$name\\s*>', caseSensitive: false);
    final match = close.firstMatch(input.substring(from));
    return match == null ? input.length : from + match.end;
  }

  _Tag? _tagAt(int lt) {
    final match = _tagPattern.matchAsPrefix(input, lt);
    if (match == null) return null;
    return _Tag(
      name: match.group(2)!.toLowerCase(),
      closing: match.group(1) != null,
      attributes: match.group(3) ?? '',
      end: match.end,
    );
  }

  static final _tagPattern = RegExp(
    r'''<\s*(/)?\s*([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''',
  );

  void _handle(_Tag tag) {
    switch (tag.name) {
      case 'br':
        _append('\n');
      case 'b' || 'strong':
        _bold = (_bold + (tag.closing ? -1 : 1)).clamp(0, 99);
      case 'i' || 'em':
        _italic = (_italic + (tag.closing ? -1 : 1)).clamp(0, 99);
      case 'a':
        if (tag.closing) {
          if (_links.isNotEmpty) _links.removeLast();
        } else {
          _links.add(safeLink(_attribute(tag.attributes, 'href')));
        }
      case final name when _headingTags.contains(name):
        _endParagraph();
        _bold = (_bold + (tag.closing ? -1 : 1)).clamp(0, 99);
      case 'li' when !tag.closing:
        _endParagraph();
        _append('\u2022 ');
      case final name when _blockTags.contains(name):
        _endParagraph();
      default:
      // Unknown or unsafe tag: dropped, its text stays.
    }
  }

  void _text(String raw) {
    final collapsed = decodeEntities(raw).replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return;
    _append(collapsed);
  }

  void _append(String text) {
    final link = _links.isEmpty ? null : _links.last;
    final bold = _bold > 0, italic = _italic > 0;
    // A space at the start of a paragraph or after a line break is noise.
    var value = text;
    final previous = _runs.isEmpty ? '' : _runs.last.text;
    if (previous.isEmpty || previous.endsWith('\n') || previous.endsWith(' ')) {
      value = value.replaceFirst(RegExp(r'^ +'), '');
    }
    if (value.isEmpty) return;
    if (_runs.isNotEmpty) {
      final last = _runs.last;
      if (last.bold == bold && last.italic == italic && last.link == link) {
        _runs[_runs.length - 1] = SafeRun(last.text + value, bold: bold, italic: italic, link: link);
        return;
      }
    }
    _runs.add(SafeRun(value, bold: bold, italic: italic, link: link));
  }

  void _endParagraph() {
    final runs = _trimEnd(_runs);
    if (runs.isNotEmpty) _paragraphs.add(SafeParagraph(runs));
    _runs = [];
  }

  static List<SafeRun> _trimEnd(List<SafeRun> runs) {
    final out = [...runs];
    while (out.isNotEmpty) {
      final last = out.last;
      final trimmed = last.text.replaceFirst(RegExp(r'[\s]+$'), '');
      if (trimmed.isEmpty) {
        out.removeLast();
        continue;
      }
      out[out.length - 1] = SafeRun(trimmed, bold: last.bold, italic: last.italic, link: last.link);
      break;
    }
    return out;
  }

  static String? _attribute(String attributes, String name) {
    final match = RegExp(
      '(?:^|\\s)$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(attributes);
    if (match == null) return null;
    return decodeEntities(match.group(1) ?? match.group(2) ?? match.group(3) ?? '');
  }
}

final class _Tag {
  const _Tag({required this.name, required this.closing, required this.attributes, required this.end});
  final String name;
  final bool closing;
  final String attributes;
  final int end;
}

/// The link if it is http, https or mailto with a real target, else null.
/// Whitespace and control characters some browsers ignore inside a scheme
/// ("java\tscript:") are removed before checking.
Uri? safeLink(String? href) {
  if (href == null) return null;
  final cleaned = href.replaceAll(RegExp(r'[\x00-\x20\x7f]'), '');
  final uri = Uri.tryParse(cleaned);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if ((scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty) return uri;
  if (scheme == 'mailto' && uri.path.contains('@')) return uri;
  return null;
}

/// Decodes the HTML entities descriptions use: named basics and numeric.
String decodeEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});'), (m) {
    final body = m.group(1)!;
    if (body.startsWith('#')) {
      final code = body.length > 1 && (body[1] == 'x' || body[1] == 'X')
          ? int.tryParse(body.substring(2), radix: 16)
          : int.tryParse(body.substring(1));
      if (code == null || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return '';
      // Control characters other than tab and newline add nothing.
      if (code < 0x20 && code != 0x09 && code != 0x0A) return '';
      return String.fromCharCode(code);
    }
    return _named[body.toLowerCase()] ?? m.group(0)!;
  });
}

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00a0',
  'hellip': '\u2026',
  'rsquo': '\u2019',
  'lsquo': '\u2018',
  'rdquo': '\u201d',
  'ldquo': '\u201c',
  'copy': '\u00a9',
  'reg': '\u00ae',
  'trade': '\u2122',
  'middot': '\u00b7',
  'bull': '\u2022',
};
