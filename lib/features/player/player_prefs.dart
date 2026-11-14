// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import '../../core/db/global_db.dart';
import '../../core/library/source_id.dart';
import '../../core/ui/cover_image.dart';

/// What the headset and car next/previous buttons do.
enum RemoteButtons { skip, chapters }

/// What happens when a book ends.
enum AutoPlay { queueThenStop, stop }

/// The listening comfort settings of docs/plan/04-phase3-player.md 3.5 and
/// 3.8. Stored as one JSON blob in the app settings.
final class PlayerPrefs {
  const PlayerPrefs({
    this.skipBack = const Duration(seconds: 15),
    this.skipForward = const Duration(seconds: 30),
    this.defaultSpeed = 1.0,
    this.speedPerBook = true,
    this.smartRewind = true,
    this.skipSilence = false,
    this.boostDecibels = 0,
    this.remoteButtons = RemoteButtons.skip,
    this.autoPlay = AutoPlay.queueThenStop,
    this.sleepFade = const Duration(seconds: 30),
    this.sleepLast = const Duration(minutes: 30),
    this.shakeToExtend = true,
    this.chapterScrubber = true,
  });

  static const skipChoices = [5, 10, 15, 30, 45, 60, 90];
  static const minSpeed = 0.5, maxSpeed = 3.5;
  static const speedPresets = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

  final Duration skipBack;
  final Duration skipForward;
  final double defaultSpeed;
  final bool speedPerBook;
  final bool smartRewind;
  final bool skipSilence;
  final double boostDecibels;
  final RemoteButtons remoteButtons;
  final AutoPlay autoPlay;
  final Duration sleepFade;

  /// The last duration picked in the sleep sheet, offered first next time.
  final Duration sleepLast;
  final bool shakeToExtend;

  /// The Now Playing scrubber shows the chapter (true) or the whole book.
  final bool chapterScrubber;

  PlayerPrefs copyWith({
    Duration? skipBack,
    Duration? skipForward,
    double? defaultSpeed,
    bool? speedPerBook,
    bool? smartRewind,
    bool? skipSilence,
    double? boostDecibels,
    RemoteButtons? remoteButtons,
    AutoPlay? autoPlay,
    Duration? sleepFade,
    Duration? sleepLast,
    bool? shakeToExtend,
    bool? chapterScrubber,
  }) => PlayerPrefs(
    skipBack: skipBack ?? this.skipBack,
    skipForward: skipForward ?? this.skipForward,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    speedPerBook: speedPerBook ?? this.speedPerBook,
    smartRewind: smartRewind ?? this.smartRewind,
    skipSilence: skipSilence ?? this.skipSilence,
    boostDecibels: boostDecibels ?? this.boostDecibels,
    remoteButtons: remoteButtons ?? this.remoteButtons,
    autoPlay: autoPlay ?? this.autoPlay,
    sleepFade: sleepFade ?? this.sleepFade,
    sleepLast: sleepLast ?? this.sleepLast,
    shakeToExtend: shakeToExtend ?? this.shakeToExtend,
    chapterScrubber: chapterScrubber ?? this.chapterScrubber,
  );

  Map<String, Object?> toJson() => {
    'skipBack': skipBack.inSeconds,
    'skipForward': skipForward.inSeconds,
    'defaultSpeed': defaultSpeed,
    'speedPerBook': speedPerBook,
    'smartRewind': smartRewind,
    'skipSilence': skipSilence,
    'boostDecibels': boostDecibels,
    'remoteButtons': remoteButtons.name,
    'autoPlay': autoPlay.name,
    'sleepFade': sleepFade.inSeconds,
    'sleepLast': sleepLast.inSeconds,
    'shakeToExtend': shakeToExtend,
    'chapterScrubber': chapterScrubber,
  };

  /// Unknown or broken values fall back to the defaults one by one.
  factory PlayerPrefs.fromJson(Map<String, Object?> json) {
    const d = PlayerPrefs();
    Duration secs(String key, Duration fallback) =>
        json[key] is num ? Duration(seconds: (json[key]! as num).round()) : fallback;
    bool flag(String key, bool fallback) => json[key] is bool ? json[key]! as bool : fallback;
    double number(String key, double fallback) => json[key] is num ? (json[key]! as num).toDouble() : fallback;
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == json[key]).firstOrNull ?? fallback;
    return PlayerPrefs(
      skipBack: secs('skipBack', d.skipBack),
      skipForward: secs('skipForward', d.skipForward),
      defaultSpeed: number('defaultSpeed', d.defaultSpeed).clamp(minSpeed, maxSpeed),
      speedPerBook: flag('speedPerBook', d.speedPerBook),
      smartRewind: flag('smartRewind', d.smartRewind),
      skipSilence: flag('skipSilence', d.skipSilence),
      boostDecibels: number('boostDecibels', d.boostDecibels).clamp(0, 10),
      remoteButtons: pick(RemoteButtons.values, 'remoteButtons', d.remoteButtons),
      autoPlay: pick(AutoPlay.values, 'autoPlay', d.autoPlay),
      sleepFade: secs('sleepFade', d.sleepFade),
      sleepLast: secs('sleepLast', d.sleepLast),
      shakeToExtend: flag('shakeToExtend', d.shakeToExtend),
      chapterScrubber: flag('chapterScrubber', d.chapterScrubber),
    );
  }
}

/// The last book, so a cold start shows the mini player paused where the
/// user left off. Never autoplays.
final class LastPlayed {
  const LastPlayed({
    required this.ref,
    required this.title,
    required this.position,
    required this.duration,
    required this.savedAt,
    this.author,
    this.chapterTitle,
    this.coverPath,
    this.coverUrl,
    this.coverKey,
  });

  final ItemRef ref;
  final String title;
  final String? author;
  final String? chapterTitle;
  final Duration position;
  final Duration duration;
  final DateTime savedAt;
  final String? coverPath;
  final String? coverUrl;
  final String? coverKey;

  CoverSource? get cover {
    if (coverPath != null) return FileCover(coverPath!);
    if (coverUrl != null) return NetworkCover(itemCoverUrl: Uri.parse(coverUrl!), cacheKey: coverKey ?? coverUrl!);
    return null;
  }

  Map<String, Object?> toJson() => {
    'ref': ref.key,
    'title': title,
    'author': author,
    'chapterTitle': chapterTitle,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'coverPath': coverPath,
    'coverUrl': coverUrl,
    'coverKey': coverKey,
  };

  static LastPlayed? fromJson(Map<String, Object?> json) {
    final ref = ItemRef.tryParseKey('${json['ref']}');
    final title = json['title'];
    if (ref == null || title is! String) return null;
    int ms(String key) => json[key] is num ? (json[key]! as num).round() : 0;
    String? text(String key) => json[key] is String ? json[key]! as String : null;
    return LastPlayed(
      ref: ref,
      title: title,
      author: text('author'),
      chapterTitle: text('chapterTitle'),
      position: Duration(milliseconds: ms('position')),
      duration: Duration(milliseconds: ms('duration')),
      savedAt: DateTime.fromMillisecondsSinceEpoch(ms('savedAt')),
      coverPath: text('coverPath'),
      coverUrl: text('coverUrl'),
      coverKey: text('coverKey'),
    );
  }
}

/// A book waiting in Up next, with what the queue sheet shows, so the
/// queue reads well offline and before any library is loaded.
final class QueueEntry {
  const QueueEntry({required this.ref, required this.title, this.author, this.coverPath, this.coverUrl, this.coverKey});

  final ItemRef ref;
  final String title;
  final String? author;
  final String? coverPath;
  final String? coverUrl;
  final String? coverKey;

  CoverSource? get cover {
    if (coverPath != null) return FileCover(coverPath!);
    if (coverUrl != null) return NetworkCover(itemCoverUrl: Uri.parse(coverUrl!), cacheKey: coverKey ?? coverUrl!);
    return null;
  }

  factory QueueEntry.of(ItemRef ref, {required String title, String? author, CoverSource? cover}) => QueueEntry(
    ref: ref,
    title: title,
    author: author,
    coverPath: cover is FileCover ? cover.path : null,
    coverUrl: cover is NetworkCover ? cover.itemCoverUrl.toString() : null,
    coverKey: cover is NetworkCover ? cover.cacheKey : null,
  );

  Map<String, Object?> toJson() => {
    'ref': ref.key,
    'title': title,
    'author': author,
    'coverPath': coverPath,
    'coverUrl': coverUrl,
    'coverKey': coverKey,
  };

  static QueueEntry? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final ref = ItemRef.tryParseKey('${json['ref']}');
    final title = json['title'];
    if (ref == null || title is! String) return null;
    String? text(String key) => json[key] is String ? json[key]! as String : null;
    return QueueEntry(
      ref: ref,
      title: title,
      author: text('author'),
      coverPath: text('coverPath'),
      coverUrl: text('coverUrl'),
      coverKey: text('coverKey'),
    );
  }
}

/// Where the player keeps its settings and memory.
abstract interface class PlayerStore {
  Future<PlayerPrefs> loadPrefs();
  Future<void> savePrefs(PlayerPrefs prefs);
  Future<LastPlayed?> loadLast();
  Future<void> saveLast(LastPlayed? last);
  Future<double?> speedFor(ItemRef ref);
  Future<void> saveSpeed(ItemRef ref, double speed);
  Future<List<QueueEntry>> loadQueue();
  Future<void> saveQueue(List<QueueEntry> queue);
}

/// [PlayerStore] in the app settings table.
final class SettingsPlayerStore implements PlayerStore {
  SettingsPlayerStore(this._db);
  final GlobalDb _db;

  static const _prefs = 'player.prefs', _last = 'player.last', _queue = 'player.queue';
  static String _speed(ItemRef ref) => 'player.speed.${ref.key}';

  Future<Object?> _json(String key) async {
    final raw = await _db.readSetting(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<PlayerPrefs> loadPrefs() async {
    final json = await _json(_prefs);
    return json is Map<String, Object?> ? PlayerPrefs.fromJson(json) : const PlayerPrefs();
  }

  @override
  Future<void> savePrefs(PlayerPrefs prefs) => _db.writeSetting(_prefs, jsonEncode(prefs.toJson()));

  @override
  Future<LastPlayed?> loadLast() async {
    final json = await _json(_last);
    return json is Map<String, Object?> ? LastPlayed.fromJson(json) : null;
  }

  @override
  Future<void> saveLast(LastPlayed? last) =>
      last == null ? _db.deleteSetting(_last) : _db.writeSetting(_last, jsonEncode(last.toJson()));

  @override
  Future<double?> speedFor(ItemRef ref) async => double.tryParse(await _db.readSetting(_speed(ref)) ?? '');

  @override
  Future<void> saveSpeed(ItemRef ref, double speed) => _db.writeSetting(_speed(ref), '$speed');

  @override
  Future<List<QueueEntry>> loadQueue() async {
    final json = await _json(_queue);
    if (json is! List) return const [];
    return [for (final e in json) ?QueueEntry.fromJson(e)];
  }

  @override
  Future<void> saveQueue(List<QueueEntry> queue) =>
      _db.writeSetting(_queue, jsonEncode([for (final e in queue) e.toJson()]));
}

/// [PlayerStore] in memory, for tests.
final class MemoryPlayerStore implements PlayerStore {
  PlayerPrefs prefs = const PlayerPrefs();
  LastPlayed? last;
  final speeds = <String, double>{};
  List<QueueEntry> queue = [];

  @override
  Future<PlayerPrefs> loadPrefs() async => prefs;
  @override
  Future<void> savePrefs(PlayerPrefs value) async => prefs = value;
  @override
  Future<LastPlayed?> loadLast() async => last;
  @override
  Future<void> saveLast(LastPlayed? value) async => last = value;
  @override
  Future<double?> speedFor(ItemRef ref) async => speeds[ref.key];
  @override
  Future<void> saveSpeed(ItemRef ref, double speed) async => speeds[ref.key] = speed;
  @override
  Future<List<QueueEntry>> loadQueue() async => queue;
  @override
  Future<void> saveQueue(List<QueueEntry> value) async => queue = [...value];
}
