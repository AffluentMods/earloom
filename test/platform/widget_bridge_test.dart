// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/platform/widget_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _book = NowPlaying(
  ref: ItemRef(LocalSource(), 'b1'),
  title: 'Salt and Starlight',
  author: 'Mara Ellison',
  duration: Duration(hours: 2),
  chapters: [
    Chapter(index: 0, title: 'Low Tide', start: Duration.zero, end: Duration(hours: 1)),
    Chapter(index: 1, title: 'High Water', start: Duration(hours: 1), end: Duration(hours: 2)),
  ],
);

void main() {
  test('writes when what the widget shows changes, progress at most once a minute', () async {
    final writes = <Map<String, Object?>>[];
    final bridge = WidgetBridge(
      labels: (play: 'Play', pause: 'Pause', back: 'Back 15 seconds', idle: 'Earloom'),
      write: (data) async => writes.add(data),
    );
    await bridge.update(const PlayerSnapshot());
    expect(writes.single['np.hasBook'], false);
    expect(writes.single['np.title'], 'Earloom');

    await bridge.update(const PlayerSnapshot(now: _book, loaded: true, position: Duration(minutes: 30)));
    expect(writes.last['np.title'], 'Salt and Starlight');
    expect(writes.last['np.subtitle'], 'Low Tide');
    expect(writes.last['np.progress'], 250);

    await bridge.update(const PlayerSnapshot(now: _book, loaded: true, position: Duration(minutes: 31)));
    expect(writes, hasLength(2), reason: 'progress alone waits a minute');

    await bridge.update(
      const PlayerSnapshot(now: _book, loaded: true, playing: true, position: Duration(minutes: 61)),
    );
    expect(writes, hasLength(3));
    expect(writes.last['np.playing'], true);
    expect(writes.last['np.subtitle'], 'High Water');
  });
}
