// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

/// Small stream combinators, so the app needs no extra package for them.
extension StreamSwitch<T> on Stream<T> {
  /// For every value, listens to the stream [inner] makes from it and
  /// forwards that stream's values, dropping the previous inner stream.
  Stream<R> switchMap<R>(Stream<R> Function(T value) inner) {
    late StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? current;
    var outerDone = false;
    controller = StreamController<R>(
      onListen: () {
        outer = listen(
          (value) {
            unawaited(current?.cancel());
            current = inner(value).listen(
              controller.add,
              onError: controller.addError,
              onDone: () {
                current = null;
                if (outerDone) unawaited(controller.close());
              },
            );
          },
          onError: controller.addError,
          onDone: () {
            outerDone = true;
            if (current == null) unawaited(controller.close());
          },
        );
      },
      onCancel: () async {
        await outer?.cancel();
        await current?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Emits [combine] of the latest values of [a] and [b] once both have
/// emitted, and again whenever either changes.
Stream<R> combineLatest2<A, B, R>(Stream<A> a, Stream<B> b, R Function(A a, B b) combine) {
  late StreamController<R> controller;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false, doneA = false, doneB = false;
  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  void done() {
    if (doneA && doneB) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      sa = a.listen(
        (v) {
          lastA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          done();
        },
      );
      sb = b.listen(
        (v) {
          lastB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          done();
        },
      );
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return controller.stream;
}
