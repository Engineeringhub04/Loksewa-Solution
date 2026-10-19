// Global "a purchase changed" signal — fixes stale purchase state after a
// successful purchase (Problem 4: no manual refresh needed).
//
// Bumped by the checkout screen on every successful purchase (gateway
// verify OR manual QR submit, any kind: subscription/exam/content).
// Listened to by:
//   - Purchase Details page  → re-runs its purchase fetch
//   - Exam tab              → force-refreshes the section cache
//   - Subject/Unit/Chapter screens → re-runs their page load
//
// Listeners reload DIRECTLY in the addListener callback (initState), even
// while their route is covered — the data is fresh the moment the user
// returns. No dirty flags, no didChangeDependencies tricks, no polling loops.
import 'package:flutter/foundation.dart';

class PurchaseRefreshBus {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void bump() {
    version.value++;
  }
}
