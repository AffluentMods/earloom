// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../stats/data/stats_repository.dart';
import '../player_controller.dart';
import '../player_engine.dart';
import '../sleep_timer.dart';
import 'player_widgets.dart';

/// The motion sensor for shake to extend. Tests swap in a silent stream.
final accelerometerProvider = Provider<Stream<UserAccelerometerEvent> Function()>(
  (ref) =>
      () => userAccelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
);

/// Player things that are not on any one screen: snackbars for player
/// notices, writing progress when the app goes to the background, and the
/// shake that extends the sleep timer. Sits above the routes.
class PlayerSideEffects extends ConsumerStatefulWidget {
  const PlayerSideEffects({super.key, required this.child, this.messengerKey});
  final Widget child;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  @override
  ConsumerState<PlayerSideEffects> createState() => _PlayerSideEffectsState();
}

class _PlayerSideEffectsState extends ConsumerState<PlayerSideEffects> with WidgetsBindingObserver {
  StreamSubscription<UserAccelerometerEvent>? _shake;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shake?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(ref.read(playerEngineProvider).flush());
    }
  }

  ScaffoldMessengerState? get _messenger => widget.messengerKey?.currentState ?? ScaffoldMessenger.maybeOf(context);

  void _show(SnackBar bar) {
    final messenger = _messenger;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(bar);
  }

  void _onNotice(PlayerNotice notice) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.read(playerEngineProvider);
    switch (notice) {
      case PickedUpElsewhere(:final undoTo):
        _show(
          SnackBar(
            content: Text(l10n.progressSyncedFromOtherDevice),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: l10n.progressUndo, onPressed: () => engine.seek(undoTo)),
          ),
        );
      case RemoteJumpOffered(:final position):
        _show(
          SnackBar(
            content: Text(l10n.progressJumpPrompt(formatClock(position))),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: l10n.progressJump, onPressed: () => engine.seek(position)),
          ),
        );
      case BookFinished(:final title):
        _show(SnackBar(content: Text(l10n.finishedBook(title))));
      case SleepExtended(:final by):
        unawaited(HapticFeedback.heavyImpact());
        _show(SnackBar(content: Text(l10n.sleepExtended(by.inMinutes))));
      case PlaybackFailed(:final details):
        _show(
          SnackBar(
            content: Text(l10n.playerFailedSnack),
            action: SnackBarAction(
              label: l10n.genericCopyDetails,
              onPressed: () => Clipboard.setData(ClipboardData(text: details)),
            ),
          ),
        );
    }
  }

  /// Listens to the accelerometer only while the sleep timer runs and the
  /// setting is on, at a low rate, so it costs nothing the rest of the time.
  void _updateShake(bool wanted) {
    if (wanted && _shake == null) {
      _shake = ref
          .read(accelerometerProvider)()
          .listen(
            (e) {
              final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
              final now = DateTime.now();
              if (g < 14 || now.difference(_lastShake) < const Duration(seconds: 2)) return;
              final engine = ref.read(playerEngineProvider);
              if (engine.sleepEndingSoon) {
                _lastShake = now;
                engine.extendSleepTimer();
              }
            },
            onError: (Object _) {
              // No accelerometer (some tablets, emulators): shake just does nothing.
            },
            cancelOnError: true,
          );
    } else if (!wanted && _shake != null) {
      unawaited(_shake!.cancel());
      _shake = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(remoteProgressBridgeProvider);
    ref.watch(listeningRecorderProvider);
    ref.listen(playerNoticesProvider, (_, next) {
      if (next case AsyncData(:final value)) _onNotice(value);
    });
    final timerOn = ref.watch(playerProvider.select((s) => s.sleep is! SleepOff));
    final shakeOn = ref.watch(playerPrefsProvider.select((p) => p.shakeToExtend));
    _updateShake(timerOn && shakeOn);
    return widget.child;
  }
}
