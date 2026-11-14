// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter/foundation.dart';

/// A note for developers. Printed in debug builds only: release builds log
/// nothing, so no error text (which could carry a server's reply) ever
/// reaches the device log.
void devLog(String message) {
  if (kDebugMode) debugPrint(message);
}
