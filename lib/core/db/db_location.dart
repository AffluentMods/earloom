// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Opens `<application support>/<name>.sqlite`.
///
/// Application Support (not Documents) keeps the databases out of the user's
/// visible files on iOS and Android.
QueryExecutor openAppDatabase(String name) {
  return driftDatabase(
    name: name,
    native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
  );
}
