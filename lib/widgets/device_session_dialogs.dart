// Device session dialogs — all rendered through AppModalShell (global rule).
//
// Three popups, mirroring the React app:
//  1. Takeover dialog (login screen): "Already logged in on another device"
//  2. Blocking eviction dialog (guard, app open): "Your account moved to
//     another device" — single button, NOT dismissible, back button swallowed.
//  3. Notice dialog (login screen after cold-start eviction): "You were
//     signed out" — single button, shows exactly once.
//
// All text is English on both app languages (security notice about a device
// the user may not be holding; device model strings are English anyway).
import 'package:flutter/material.dart';

import 'app_modal_shell.dart';
import 'popup_action_button.dart';

// LANGUAGE CONTRACT: these security strings stay English on both app
// languages by design — a notice about a device the user may not be holding,
// and device model strings are English anyway. AppLanguage.tr is
// intentionally NOT used in this file.

Widget _warningIcon() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Icon(Icons.phone_android, color: Color(0xFFB45309), size: 28),
  );
}

Widget _dialogTitle(String text) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  );
}

Widget _dialogBody(String text) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 14),
  );
}

/// 1. Login screen: another phone holds this account.
/// Returns true = "I understand, Go Login", false/null = Cancel.
Future<bool> showDeviceTakeoverDialog(
  BuildContext context, {
  required String deviceName,
  required String lastActiveLabel,
}) {
  var busy = false;
  return AppModalShell.show<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) => AppModalShell(
        icon: _warningIcon(),
        tagLabel: 'Security',
        title: _dialogTitle('Already logged in on another device'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$deviceName · Android · last active $lastActiveLabel',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _dialogBody(
              'This account can be used on one device at a time. '
              'Continuing here will sign that device out.',
            ),
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupActionButton(
              label: 'I understand, Go Login',
              backgroundColor: const Color(0xFFDC2626),
              loading: busy,
              onTap: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      Navigator.of(ctx).pop(true);
                    },
            ),
            const SizedBox(height: 8),
            PopupCancelButton(
              label: 'Cancel',
              onTap: busy ? null : () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
        onClose: busy ? null : () => Navigator.of(ctx).pop(false),
      ),
    ),
  ).then((v) => v == true);
}

/// 2. Guard (app open): this device just lost the account.
/// Blocking — no dismiss, no back button, no cancel. The single button is
/// the only way forward.
Future<void> showBlockingEvictionDialog(
  BuildContext context, {
  String? deviceName,
}) {
  var busy = false;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Signed out',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (pageContext, _, __) {
      return PopScope(
        canPop: false,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: StatefulBuilder(
                  builder: (ctx, setState) => AppModalShell(
                    icon: _warningIcon(),
                    tagLabel: 'Security',
                    title:
                        _dialogTitle('Your account moved to another device'),
                    body: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (deviceName != null && deviceName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Now signed in on $deviceName',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF64748B)),
                            ),
                          ),
                        _dialogBody(
                          'This account can be used on one device at a time, '
                          'and it was just opened somewhere else. This device '
                          'will now be signed out.',
                        ),
                      ],
                    ),
                    footer: PopupActionButton(
                      label: 'OK, I understood — Log out',
                      backgroundColor: const Color(0xFFDC2626),
                      loading: busy,
                      onTap: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              Navigator.of(ctx).pop();
                            },
                    ),
                    // No onClose → no X button.
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// 3. Login screen after a cold-start eviction: explains the sign-out once.
Future<void> showEvictionNoticeDialog(
  BuildContext context, {
  String? deviceName,
}) {
  return AppModalShell.show<void>(
    context: context,
    builder: (dialogContext) => AppModalShell(
      icon: _warningIcon(),
      tagLabel: 'Security',
      title: _dialogTitle('You were signed out'),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (deviceName != null && deviceName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Now signed in on $deviceName',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ),
          _dialogBody(
            'This account was opened on another device while this app was '
            'closed, and only one device can use an account at a time. '
            'Log in again to use it here — the other device will be signed out.',
          ),
        ],
      ),
      footer: PopupActionButton(
        label: 'I understood',
        backgroundColor: const Color(0xFF1D4ED8),
        onTap: () => Navigator.of(dialogContext).pop(),
      ),
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
