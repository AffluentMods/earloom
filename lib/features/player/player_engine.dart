// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import '../../core/library/models.dart';
import '../../core/library/source_id.dart';
import '../../core/ui/cover_image.dart';
import 'audio_backend.dart';
import 'chapters.dart';
import 'playable.dart';
import 'player_prefs.dart';
import 'progress_resolver.dart';
import 'sleep_timer.dart';
import 'track_map.dart';

/// What is loaded, as the UI, lock screen and car need it.
final class NowPlaying {
  const NowPlaying({
    required this.ref,
    required this.title,
    required this.duration,
    required this.chapters,
    this.author,
    this.narrator,
    this.seriesLine,
    this.cover,
    this.artworkUri,
    this.coverKey,
  });

  final ItemRef ref;
  final String title;
  final String? author;
  final String? narrator;
  final String? seriesLine;
  final Duration duration;

  /// Never empty for a loaded book (see [effectiveChapters]).
  final List<Chapter> chapters;
  final CoverSource? cover;
  final Uri? artworkUri;
  final String? coverKey;
}

/// One frame of player state. Positions are whole-book positions.
final class PlayerSnapshot {
  const PlayerSnapshot({
    this.now,
    this.loaded = false,
    this.position = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.speed = 1.0,
    this.sleep = const SleepOff(),
    this.sleepRemaining,
    this.queue = const [],
    this.failure,
  });

  static const empty = PlayerSnapshot();

  final NowPlaying? now;

  /// The audio is in the backend. False for a book restored on cold start,
  /// which loads on the first play.
  final bool loaded;
  final Duration position;
  final bool playing;
  final bool buffering;
  final double speed;
  final SleepTimer sleep;

  /// Listening time left before the sleep timer pauses, when it is on.
  final Duration? sleepRemaining;
  final List<QueueEntry> queue;

  /// Technical details of the last failure, for "Copy details".
  final String? failure;

  bool get hasBook => now != null;
  Duration get duration => now?.duration ?? Duration.zero;
  int get chapterIndex => now == null ? 0 : chapterIndexAt(now!.chapters, position);
  Chapter? get chapter => (now?.chapters.isEmpty ?? true) ? null : now!.chapters[chapterIndex];

  /// Time left in the book at the current speed.
  Duration get remainingAtSpeed {
    final left = duration - position;
    if (left <= Duration.zero) return Duration.zero;
    return Duration(milliseconds: (left.inMilliseconds / speed).round());
  }

  PlayerSnapshot copyWith({
    NowPlaying? now,
    bool? loaded,
    Duration? position,
    bool? playing,
    bool? buffering,
    double? speed,
    SleepTimer? sleep,
    Duration? sleepRemaining,
    bool clearSleepRemaining = false,
    List<QueueEntry>? queue,
    String? failure,
    bool clearFailure = false,
  }) => PlayerSnapshot(
    now: now ?? this.now,
    loaded: loaded ?? this.loaded,
    position: position ?? this.position,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    speed: speed ?? this.speed,
    sleep: sleep ?? this.sleep,
    sleepRemaining: clearSleepRemaining ? null : sleepRemaining ?? this.sleepRemaining,
    queue: queue ?? this.queue,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

/// One-time things the UI tells the user about.
sealed class PlayerNotice {
  const PlayerNotice();
}

/// The server had a newer position from another device.
final class PickedUpElsewhere extends PlayerNotice {
  const PickedUpElsewhere(this.undoTo);
  final Duration undoTo;
}

/// Another device moved far ahead or back while this one plays.
final class RemoteJumpOffered extends PlayerNotice {
  const RemoteJumpOffered(this.position);
  final Duration position;
}

final class BookFinished extends PlayerNotice {
  const BookFinished(this.title);
  final String title;
}

final class SleepExtended extends PlayerNotice {
  const SleepExtended(this.by);
  final Duration by;
}

final class PlaybackFailed extends PlayerNotice {
  const PlaybackFailed(this.details);
  final String details;
}

/// Turns an [ItemRef] into something playable, and decides where it starts.
/// [startAt] wins over saved progress when given.
typedef BookResolver = Future<(PlayableBook, StartDecision)> Function(ItemRef ref, {Duration? startAt});

/// Names for fallback chapters (from l10n, set by the app).
final class ChapterNames {
  const ChapterNames({required this.forTrack, required this.wholeBook});
  final String Function(int number) forTrack;
  final String wholeBook;

  static ChapterNames fallback = ChapterNames(forTrack: (n) => '$n', wholeBook: '1');
}

/// The one place playback happens. UI, lock screen, car, widgets and
/// shortcuts all go through it; nothing else touches the backend.
class PlayerEngine {
  PlayerEngine({
    required this._backend,
    required this._store,
    required this._resolver,
    DateTime Function()? now,
    ChapterNames? chapterNames,
  }) : _now = now ?? DateTime.now,
       chapterNames = chapterNames ?? ChapterNames.fallback {
    _signals = _backend.signals.listen(_onSignal);
  }

  final AudioBackend _backend;
  final PlayerStore _store;
  final BookResolver _resolver;
  final DateTime Function() _now;
  ChapterNames chapterNames;

  static const tick = Duration(milliseconds: 250);
  static const reportEvery = Duration(seconds: 15);
  static const seekReportDelay = Duration(seconds: 2);
  static const interruptionResumeWindow = Duration(minutes: 2);

  late final StreamSubscription<BackendSignal> _signals;
  final _snapshots = StreamController<PlayerSnapshot>.broadcast();
  final _notices = StreamController<PlayerNotice>.broadcast();

  PlayerSnapshot _value = PlayerSnapshot.empty;
  PlayerPrefs _prefs = const PlayerPrefs();
  PlayableBook? _book;
  TrackMap _map = TrackMap(const []);
  Timer? _ticker;
  Timer? _seekReport;
  DateTime? _lastTick;
  DateTime? _pausedAt;
  DateTime? _interruptedAt;
  DateTime? _lastReportAt;
  Duration _listened = Duration.zero;
  int _openId = 0;
  DateTime? _lastReloadAt;
  bool _finishing = false;
  int _lastChapter = -1;
  double _volume = 1;

  PlayerSnapshot get value => _value;
  Stream<PlayerSnapshot> get snapshots => _snapshots.stream;
  Stream<PlayerNotice> get notices => _notices.stream;
  PlayerPrefs get prefs => _prefs;

  void _emit(PlayerSnapshot next) {
    _value = next;
    if (!_snapshots.isClosed) _snapshots.add(next);
  }

  void _notice(PlayerNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  /// Loads settings, the queue and the last book (paused, not loaded).
  Future<void> restore() async {
    _prefs = await _store.loadPrefs();
    final queue = await _store.loadQueue();
    final last = await _store.loadLast();
    if (_value.hasBook) {
      _emit(_value.copyWith(queue: queue));
      return;
    }
    if (last == null) {
      _emit(_value.copyWith(queue: queue, speed: _prefs.defaultSpeed));
      return;
    }
    final speed = (_prefs.speedPerBook ? await _store.speedFor(last.ref) : null) ?? _prefs.defaultSpeed;
    _emit(
      PlayerSnapshot(
        now: NowPlaying(
          ref: last.ref,
          title: last.title,
          author: last.author,
          duration: last.duration,
          chapters: [
            Chapter(index: 0, title: last.chapterTitle ?? last.title, start: Duration.zero, end: last.duration),
          ],
          cover: last.cover,
          coverKey: last.coverKey,
        ),
        position: last.position,
        speed: speed,
        queue: queue,
      ),
    );
  }

  Future<void> updatePrefs(PlayerPrefs prefs) async {
    final old = _prefs;
    _prefs = prefs;
    await _store.savePrefs(prefs);
    if (old.skipSilence != prefs.skipSilence) await _backend.setSkipSilence(prefs.skipSilence);
    if (old.boostDecibels != prefs.boostDecibels) await _backend.setBoost(prefs.boostDecibels);
    if (!prefs.speedPerBook && old.defaultSpeed != prefs.defaultSpeed && _value.hasBook) {
      await setSpeed(prefs.defaultSpeed);
    }
  }

  // Loading -----------------------------------------------------------------

  /// Opens [ref] and plays it (unless [autoplay] is false). Another book
  /// that was loaded is reported and closed first.
  Future<void> playItem(ItemRef ref, {Duration? startAt, bool autoplay = true}) async {
    final id = ++_openId;
    final previous = _book;
    if (previous != null && previous.ref != ref) {
      await _pauseBackend();
      await _closeBook(previous);
    } else if (previous != null) {
      // The same book again: just seek and play.
      if (startAt != null) await seek(startAt);
      if (autoplay) await play();
      return;
    }
    _emit(_value.copyWith(buffering: true, clearFailure: true));
    final PlayableBook book;
    final StartDecision decision;
    try {
      (book, decision) = await _resolver(ref, startAt: startAt);
    } on Object catch (e) {
      if (id != _openId) return;
      _emit(_value.copyWith(buffering: false, failure: '$e'));
      _notice(PlaybackFailed('$e'));
      return;
    }
    if (id != _openId) return;
    await _load(book, decision.position, autoplay: autoplay, id: id);
    if (decision.fromOtherDevice && decision.undoTo != null) _notice(PickedUpElsewhere(decision.undoTo!));
  }

  Future<void> _load(PlayableBook book, Duration start, {required bool autoplay, required int id}) async {
    final map = TrackMap(book.tracks);
    final chapters = effectiveChapters(
      book,
      titleForTrack: chapterNames.forTrack,
      wholeBookTitle: chapterNames.wholeBook,
    );
    final speed = (_prefs.speedPerBook ? await _store.speedFor(book.ref) : null) ?? _prefs.defaultSpeed;
    final total = map.total;
    // A finished book (or one within a second of its end) starts over.
    final from = start >= total - const Duration(seconds: 1) ? Duration.zero : start;
    _book = book;
    _map = map;
    _finishing = false;
    _listened = Duration.zero;
    _lastReportAt = _now();
    _pausedAt = null;
    _lastChapter = chapterIndexAt(chapters, from);
    _emit(
      PlayerSnapshot(
        now: NowPlaying(
          ref: book.ref,
          title: book.title,
          author: book.author,
          narrator: book.narrator,
          seriesLine: book.seriesLine,
          duration: total,
          chapters: chapters,
          cover: book.cover ?? _coverFromArtwork(book.artworkUri),
          artworkUri: book.artworkUri,
          coverKey: book.coverKey,
        ),
        position: from,
        speed: speed,
        buffering: true,
        sleep: _value.sleep,
        sleepRemaining: _value.sleepRemaining,
        queue: _value.queue,
      ),
    );
    final at = map.locate(from);
    try {
      await _backend.load(book.tracks, index: at.index, offset: at.offset);
      await _backend.setSpeed(speed);
      await _backend.setSkipSilence(_prefs.skipSilence);
      await _backend.setBoost(_prefs.boostDecibels);
      await _setVolume(1);
    } on Object catch (e) {
      if (id != _openId) return;
      _emit(_value.copyWith(buffering: false, failure: '$e'));
      _notice(PlaybackFailed('$e'));
      return;
    }
    if (id != _openId) return;
    _emit(_value.copyWith(loaded: true, buffering: false));
    unawaited(_saveLast());
    if (autoplay) await play(smartRewind: false);
  }

  static CoverSource? _coverFromArtwork(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme == 'file') return FileCover(uri.toFilePath());
    return null;
  }

  // Transport ---------------------------------------------------------------

  Future<void> play({bool smartRewind = true}) async {
    if (!_value.hasBook) return;
    if (!_value.loaded || _book == null) {
      await playItem(_value.now!.ref);
      return;
    }
    if (_value.position >= _value.duration - const Duration(seconds: 1)) {
      await _seekBackend(Duration.zero);
    } else if (smartRewind && _prefs.smartRewind && _pausedAt != null) {
      final back = smartRewindFor(_now().difference(_pausedAt!));
      if (back > Duration.zero) await _seekBackend(_value.position - back);
    }
    _pausedAt = null;
    _interruptedAt = null;
    _lastTick = _now();
    _backend.play();
    _emit(_value.copyWith(playing: true));
    _startTicker();
  }

  Future<void> pause() async {
    if (!_value.playing) return;
    await _pauseBackend();
    await _report();
    unawaited(_saveLast());
  }

  Future<void> _pauseBackend() async {
    _accumulate();
    await _backend.pause();
    _pausedAt = _now();
    _stopTicker();
    _emit(_value.copyWith(playing: false, position: _readPosition()));
  }

  Future<void> togglePlayPause() => _value.playing ? pause() : play();

  Future<void> seek(Duration position) async {
    if (!_value.hasBook) return;
    if (!_value.loaded) {
      _emit(_value.copyWith(position: _clamp(position)));
      return;
    }
    await _seekBackend(position);
    _seekReport?.cancel();
    _seekReport = Timer(seekReportDelay, () => unawaited(_report()));
  }

  Future<void> _seekBackend(Duration position) async {
    final target = _clamp(position);
    final at = _map.locate(target);
    _accumulate();
    await _backend.seek(at.index, at.offset);
    _emit(_value.copyWith(position: target));
    _lastChapter = _value.chapterIndex;
  }

  Duration _clamp(Duration position) {
    if (position < Duration.zero) return Duration.zero;
    final total = _value.duration;
    return position > total ? total : position;
  }

  Future<void> skipBy(Duration delta) => seek(_value.position + delta);
  Future<void> skipBack() => skipBy(-_prefs.skipBack);
  Future<void> skipForward() => skipBy(_prefs.skipForward);

  Future<void> nextChapter() async {
    final target = nextChapterTarget(_value.now?.chapters ?? const [], _value.position);
    if (target != null) await seek(target);
  }

  Future<void> previousChapter() => seek(previousChapterTarget(_value.now?.chapters ?? const [], _value.position));

  Future<void> setSpeed(double speed) async {
    final s = ((speed.clamp(PlayerPrefs.minSpeed, PlayerPrefs.maxSpeed) * 20).round() / 20);
    _accumulate();
    if (_value.loaded) await _backend.setSpeed(s);
    _emit(_value.copyWith(speed: s));
    final ref = _value.now?.ref;
    if (_prefs.speedPerBook && ref != null) {
      await _store.saveSpeed(ref, s);
    } else if (!_prefs.speedPerBook) {
      _prefs = _prefs.copyWith(defaultSpeed: s);
      await _store.savePrefs(_prefs);
    }
  }

  /// Stops playback, reports and closes the book, and clears the player.
  Future<void> stop() async {
    _openId++;
    final book = _book;
    if (_value.playing) await _pauseBackend();
    if (book != null) await _closeBook(book);
    await _backend.stop();
    _book = null;
    _map = TrackMap(const []);
    _stopTicker();
    await _store.saveLast(null);
    _emit(PlayerSnapshot(speed: _prefs.defaultSpeed, queue: _value.queue));
  }

  Future<void> _closeBook(PlayableBook book) async {
    _accumulate();
    final position = _readPosition();
    await _safe(() => book.sink.report(position: position, listened: _listened, isPlaying: false));
    _listened = Duration.zero;
    await _safe(() => book.sink.close(position: position));
    _book = null;
  }

  // Sleep timer -------------------------------------------------------------

  void setSleepTimer(SleepTimer timer) {
    _emit(_value.copyWith(sleep: timer, clearSleepRemaining: timer is SleepOff));
    if (timer is SleepOff) unawaited(_setVolume(1));
    if (timer is SleepAfter) {
      _prefs = _prefs.copyWith(sleepLast: timer.original);
      unawaited(_store.savePrefs(_prefs));
    }
    _updateSleepRemaining();
  }

  /// Adds the original duration again (shake, or the button on the fading
  /// notice). Only while a timer runs.
  void extendSleepTimer() {
    final sleep = _value.sleep;
    final Duration by;
    switch (sleep) {
      case SleepAfter(:final original, :final remaining):
        by = original;
        _emit(
          _value.copyWith(
            sleep: SleepAfter(original: original, remaining: remaining + original),
          ),
        );
      case SleepAtChapterEnd() || SleepAtBookEnd():
        by = _prefs.sleepLast;
        final left = _value.sleepRemaining ?? Duration.zero;
        _emit(
          _value.copyWith(
            sleep: SleepAfter(original: by, remaining: left + by),
          ),
        );
      case SleepOff():
        return;
    }
    unawaited(_setVolume(1));
    _updateSleepRemaining();
    _notice(SleepExtended(by));
  }

  /// Whether a shake should extend the timer now: in its last minute.
  bool get sleepEndingSoon {
    final left = _value.sleepRemaining;
    return _value.sleep is! SleepOff && left != null && left <= const Duration(minutes: 1);
  }

  void _updateSleepRemaining() {
    final sleep = _value.sleep;
    final now = _value.now;
    final Duration? left = switch (sleep) {
      SleepOff() => null,
      SleepAfter(:final remaining) => remaining,
      SleepAtChapterEnd(:final chapterIndex) when now != null && chapterIndex < now.chapters.length => _atSpeed(
        now.chapters[chapterIndex].end - _value.position,
      ),
      SleepAtChapterEnd() => null,
      SleepAtBookEnd() => _atSpeed(_value.duration - _value.position),
    };
    _emit(_value.copyWith(sleepRemaining: left, clearSleepRemaining: left == null));
  }

  Duration _atSpeed(Duration bookTime) =>
      Duration(milliseconds: (bookTime.inMilliseconds / _value.speed).round().clamp(0, 1 << 52));

  Future<void> _sleepTick(Duration elapsed) async {
    final sleep = _value.sleep;
    if (sleep is SleepAfter) {
      _emit(_value.copyWith(sleep: sleep.copyWith(remaining: sleep.remaining - elapsed)));
    }
    _updateSleepRemaining();
    final left = _value.sleepRemaining;
    if (left == null) return;
    await _setVolume(sleepFadeVolume(left, _prefs.sleepFade));
    if (left <= Duration.zero) {
      await _pauseBackend();
      // Rewind by the fade, so nothing heard half-asleep is missed.
      final fade = _prefs.sleepFade;
      if (fade > Duration.zero) await _seekBackend(_value.position - fade);
      await _setVolume(1);
      _emit(_value.copyWith(sleep: const SleepOff(), clearSleepRemaining: true));
      await _report();
      unawaited(_saveLast());
    }
  }

  Future<void> _setVolume(double volume) async {
    if ((volume - _volume).abs() < 0.001) return;
    _volume = volume;
    await _backend.setVolume(volume);
  }

  // Queue -------------------------------------------------------------------

  Future<void> addToQueue(QueueEntry entry) => _setQueue([..._without(entry.ref), entry]);
  Future<void> playNext(QueueEntry entry) => _setQueue([entry, ..._without(entry.ref)]);
  Future<void> removeFromQueue(ItemRef ref) => _setQueue(_without(ref));

  List<QueueEntry> _without(ItemRef ref) => [..._value.queue.where((e) => e.ref != ref)];
  Future<void> clearQueue() => _setQueue(const []);

  Future<void> moveInQueue(int from, int to) {
    final queue = [..._value.queue];
    if (from < 0 || from >= queue.length) return Future.value();
    final item = queue.removeAt(from);
    queue.insert(to.clamp(0, queue.length), item);
    return _setQueue(queue);
  }

  Future<void> _setQueue(List<QueueEntry> queue) async {
    _emit(_value.copyWith(queue: List.unmodifiable(queue)));
    await _store.saveQueue(queue);
  }

  // Remote progress ---------------------------------------------------------

  /// Progress for [ref] changed on another device.
  Future<void> applyRemote(ItemRef ref, PositionStamp remote) async {
    if (_value.now?.ref != ref || _finishing) return;
    final action = resolveRemote(
      here: _value.position,
      playing: _value.playing,
      remote: remote,
      lastSyncedAt: _lastReportAt,
    );
    switch (action) {
      case ApplyRemote(:final position):
        await seek(position);
      case OfferJump(:final position):
        _notice(RemoteJumpOffered(position));
      case IgnoreRemote():
        break;
    }
  }

  // Ticks, reports, signals ---------------------------------------------------

  void _startTicker() {
    _ticker ??= Timer.periodic(tick, (_) => unawaited(_onTick()));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTick = null;
  }

  /// Adds the real time spent playing since the last tick to [_listened].
  /// Returns that time.
  Duration _accumulate() {
    final now = _now();
    final last = _lastTick;
    _lastTick = _value.playing ? now : null;
    if (last == null || !_value.playing || _value.buffering) return Duration.zero;
    final elapsed = now.difference(last);
    if (elapsed.isNegative || elapsed > const Duration(minutes: 1)) return Duration.zero;
    _listened += elapsed;
    return elapsed;
  }

  Duration _readPosition() {
    if (!_value.loaded || _map.isEmpty) return _value.position;
    return _clamp(_map.toGlobal(_backend.index, _backend.offset));
  }

  Future<void> _onTick() async {
    if (!_value.loaded) return;
    final elapsed = _accumulate();
    final position = _readPosition();
    final buffering = _backend.state == BackendState.buffering || _backend.state == BackendState.loading;
    _emit(_value.copyWith(position: position, buffering: buffering));
    final chapter = _value.chapterIndex;
    final chapterChanged = chapter != _lastChapter;
    if (chapterChanged) _lastChapter = chapter;
    if (_value.sleep is! SleepOff) await _sleepTick(elapsed);
    final due = _lastReportAt == null || _now().difference(_lastReportAt!) >= reportEvery;
    if (_value.playing && (due || chapterChanged)) await _report();
  }

  Future<void> _report() async {
    final book = _book;
    if (book == null) return;
    _accumulate();
    final listened = _listened;
    _listened = Duration.zero;
    _lastReportAt = _now();
    final position = _readPosition();
    await _safe(() => book.sink.report(position: position, listened: listened, isPlaying: _value.playing));
  }

  /// The app is going to the background: write everything now.
  Future<void> flush() async {
    await _report();
    await _saveLast();
  }

  Future<void> _saveLast() async {
    final now = _value.now;
    if (now == null) return;
    final cover = now.cover;
    await _store.saveLast(
      LastPlayed(
        ref: now.ref,
        title: now.title,
        author: now.author,
        chapterTitle: _value.chapter?.title,
        position: _value.position,
        duration: now.duration,
        savedAt: _now(),
        coverPath: cover is FileCover ? cover.path : null,
        coverUrl: cover is NetworkCover ? cover.itemCoverUrl.toString() : null,
        coverKey: now.coverKey ?? (cover is NetworkCover ? cover.cacheKey : null),
      ),
    );
  }

  void _onSignal(BackendSignal signal) {
    switch (signal) {
      case BackendChanged():
        if (_backend.state == BackendState.completed && _value.loaded && !_finishing) {
          unawaited(_finishBook());
        }
      case InterruptionBegan():
        if (_value.playing) {
          _interruptedAt = _now();
          unawaited(_pauseBackend());
        }
      case InterruptionEnded(:final shouldResume):
        final at = _interruptedAt;
        _interruptedAt = null;
        if (shouldResume && at != null && _now().difference(at) < interruptionResumeWindow) {
          unawaited(play(smartRewind: false));
        }
      case BecameNoisy():
        unawaited(pause());
      case BackendFailed(:final details):
        unawaited(_onFailure(details));
    }
  }

  Future<void> _onFailure(String details) async {
    final book = _book;
    final wasPlaying = _value.playing;
    final lastReload = _lastReloadAt;
    final mayReload = lastReload == null || _now().difference(lastReload) > const Duration(minutes: 1);
    if (book != null && book.ref.source is AbsSource && mayReload) {
      // Server sessions end when the server restarts or another device of
      // this user starts one: open a fresh session where we were. Once a
      // minute at most, so a book that cannot play does not loop.
      _lastReloadAt = _now();
      final position = _readPosition();
      final id = ++_openId;
      try {
        await _backend.pause();
        _stopTicker();
        final (fresh, _) = await _resolver(book.ref, startAt: position);
        if (id != _openId) return;
        await _load(fresh, position, autoplay: wasPlaying, id: id);
        return;
      } on Object catch (e) {
        details = '$details\n$e';
      }
    }
    _stopTicker();
    _emit(_value.copyWith(playing: false, buffering: false, failure: details));
    _notice(PlaybackFailed(details));
  }

  Future<void> _finishBook() async {
    final book = _book;
    if (book == null) return;
    _finishing = true;
    _accumulate();
    final end = _value.duration;
    _stopTicker();
    _emit(_value.copyWith(playing: false, position: end));
    await _safe(() => book.sink.report(position: end, listened: _listened, isPlaying: false));
    _listened = Duration.zero;
    await _safe(() => book.sink.finished(position: end));
    _notice(BookFinished(book.title));
    final stopHere = _value.sleep is SleepAtBookEnd;
    if (stopHere) setSleepTimer(const SleepOff());
    if (!stopHere && _prefs.autoPlay == AutoPlay.queueThenStop && _value.queue.isNotEmpty) {
      final next = _value.queue.first;
      await _setQueue(_value.queue.skip(1).toList());
      await playItem(next.ref);
      return;
    }
    unawaited(_saveLast());
  }

  static Future<void> _safe(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Sinks keep their own retry state; a failed report never stops
      // playback.
    }
  }

  Future<void> dispose() async {
    _stopTicker();
    _seekReport?.cancel();
    // None of these are awaited: a broadcast controller's close waits for
    // listeners that may never cancel.
    unawaited(_signals.cancel());
    unawaited(_snapshots.close());
    unawaited(_notices.close());
  }
}
