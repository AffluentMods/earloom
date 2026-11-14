// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows "New episode" notifications on this phone. Local only: nothing
/// goes through a push service (F-Droid friendly, no tracking).
abstract interface class EpisodeNotifier {
  /// Asks the system for permission to notify. Returns false when the user
  /// said no.
  Future<bool> requestPermission();

  /// [payload] comes back to [onOpen] when the user taps it.
  Future<void> show({required int id, required String title, required String body, String? payload});

  /// Called with the payload of a tapped notification.
  set onOpen(void Function(String payload)? callback);
}

/// The real notifications, through flutter_local_notifications.
class LocalEpisodeNotifier implements EpisodeNotifier {
  LocalEpisodeNotifier({required this.channelName, required this.channelDescription});

  final String channelName;
  final String channelDescription;
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  void Function(String payload)? _onOpen;

  static const _channelId = 'com.affluentlabs.earloom.episodes';

  @override
  set onOpen(void Function(String payload)? callback) => _onOpen = callback;

  Future<bool> _init() => _ready ??= () async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_earloom'),
          // Permission is asked when the user turns notifications on for a
          // show, never at start.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _onOpen?.call(payload);
        },
      );
      return ok ?? false;
    } on Object catch (e) {
      debugPrint('Notifications unavailable: $e');
      return false;
    }
  }();

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      }
    } on Object catch (e) {
      debugPrint('Notification permission not asked: $e');
    }
    return false;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (!await _init()) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.recommendation,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

/// Notifications that only remember what was shown, for tests.
class MemoryEpisodeNotifier implements EpisodeNotifier {
  final shown = <({int id, String title, String body, String? payload})>[];
  bool allow = true;

  @override
  set onOpen(void Function(String payload)? callback) {}

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async =>
      shown.add((id: id, title: title, body: body, payload: payload));
}
