// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Single-flight token refresh: at most one refresh in flight per account.
/// Refresh tokens rotate, so two refreshers would log the user out. Built in
/// Phase 1.
library;
