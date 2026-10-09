import 'package:flutter/foundation.dart';

/// Shared unread-notification badge count.
///
/// The bell badge lives in the home header, but reads happen on the
/// notifications page — without a shared signal the badge stays stale after
/// "Mark all as read" until the home tab fully reloads. Writers
/// (notifications page) update this; the home header listens.
class NotificationBadge {
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static void set(int n) {
    if (unreadCount.value != n) unreadCount.value = n;
  }

  static void decrement() {
    if (unreadCount.value > 0) unreadCount.value--;
  }

  static void clear() => set(0);
}
