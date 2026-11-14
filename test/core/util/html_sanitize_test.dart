// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/util/html_sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<SafeRun> runs(SafeHtml html) => [for (final p in html.paragraphs) ...p.runs];

  group('safe subset', () {
    test('paragraphs, line breaks, bold, italic and links survive', () {
      final html = sanitizeHtml(
        '<p>A <b>bold</b> and <em>quiet</em> book.</p><p>Line one<br>Line two</p>'
        '<p>See <a href="https://example.com/book">the site</a>.</p>',
      );
      expect(html.paragraphs, hasLength(3));
      expect(html.paragraphs[0].text, 'A bold and quiet book.');
      expect(runs(html).firstWhere((r) => r.text == 'bold').bold, isTrue);
      expect(runs(html).firstWhere((r) => r.text == 'quiet').italic, isTrue);
      expect(html.paragraphs[1].text, 'Line one\nLine two');
      final link = runs(html).firstWhere((r) => r.link != null);
      expect(link.text, 'the site');
      expect(link.link, Uri.parse('https://example.com/book'));
    });

    test('entities are decoded once and stay text', () {
      final html = sanitizeHtml('<p>Tom &amp; Jerry &lt;script&gt;alert(1)&lt;/script&gt; &#39;hi&#39; &#x263A;</p>');
      expect(html.plainText, "Tom & Jerry <script>alert(1)</script> 'hi' ☺");
    });

    test('plain text keeps its line breaks and paragraphs', () {
      final html = sanitizeHtml('First line\nSecond line\n\nNew paragraph');
      expect(html.paragraphs.map((p) => p.text), ['First line\nSecond line', 'New paragraph']);
    });

    test('lists become bulleted paragraphs, headings bold paragraphs', () {
      final html = sanitizeHtml('<h2>Contents</h2><ul><li>One</li><li>Two</li></ul>');
      expect(html.paragraphs.map((p) => p.text), ['Contents', '• One', '• Two']);
      expect(html.paragraphs.first.runs.single.bold, isTrue);
    });

    test('empty and blank input give nothing', () {
      expect(sanitizeHtml(null).isEmpty, isTrue);
      expect(sanitizeHtml('   ').isEmpty, isTrue);
      expect(sanitizeHtml('<p> </p><br>').isEmpty, isTrue);
    });
  });

  group('malicious HTML renders as plain safe text', () {
    test('script and style blocks are dropped with their content', () {
      final html = sanitizeHtml(
        '<p>Before</p><script>steal(document.cookie)</script><SCRIPT type="x">evil()</SCRIPT>'
        '<style>body{display:none}</style><p>After</p>',
      );
      expect(html.plainText, 'Before\n\nAfter');
      expect(html.plainText, isNot(contains('steal')));
      expect(html.plainText, isNot(contains('evil')));
    });

    test('an unclosed script drops everything after it', () {
      expect(sanitizeHtml('<p>Safe</p><script>while(1){}').plainText, 'Safe');
    });

    test('event handler attributes and images leave no trace', () {
      final html = sanitizeHtml(
        '<img src=x onerror="alert(1)"><p onclick="alert(2)">Click</p><svg onload=alert(3)>x</svg>',
      );
      expect(html.plainText, 'Click');
      expect(runs(html).every((r) => r.link == null), isTrue);
    });

    test('javascript, data and vbscript links lose the link, keep the text', () {
      for (final href in [
        'javascript:alert(1)',
        'JaVaScRiPt:alert(1)',
        ' javascript:alert(1)',
        'java\tscript:alert(1)',
        'java&#x09;script:alert(1)',
        '&#106;avascript:alert(1)',
        'data:text/html;base64,PHNjcmlwdD4=',
        'vbscript:msgbox(1)',
        '//evil.example/x',
        '/relative',
      ]) {
        final html = sanitizeHtml('<a href="$href">Read more</a>');
        expect(html.plainText, 'Read more', reason: href);
        expect(runs(html).single.link, isNull, reason: href);
      }
    });

    test('mailto and https links are kept', () {
      expect(runs(sanitizeHtml('<a href="mailto:hello@example.com">Mail</a>')).single.link?.scheme, 'mailto');
      expect(runs(sanitizeHtml("<a href='https://example.com'>Site</a>")).single.link?.host, 'example.com');
    });

    test('iframes, objects and forms do not carry their content through', () {
      final html = sanitizeHtml('<iframe src="https://evil.example">inner</iframe><object data="x">obj</object>Text');
      expect(html.plainText, 'Text');
    });

    test('comments and broken tags are not interpreted', () {
      final html = sanitizeHtml('<!-- <script>alert(1)</script> -->Hi <b onmouseover="x">there</b> 3 < 4');
      expect(html.plainText, 'Hi there 3 < 4');
    });

    test('quoted ">" inside attributes does not end the tag early', () {
      final html = sanitizeHtml('<a title="a>b" href="javascript:alert(1)">Link</a>');
      expect(html.plainText, 'Link');
      expect(runs(html).single.link, isNull);
    });
  });
}
