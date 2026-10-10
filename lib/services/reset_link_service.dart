import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'password_reset_service.dart';
import '../widgets/app_modal_shell.dart';
import '../widgets/popup_action_button.dart';

/// Cold-start / warm-start hand-off for password-reset App Links.
///
/// Problem: [appRouter] sets `overridePlatformDefaultLocation: true` and
/// boots every cold start at `/splash`, so the platform's initial-route URI
/// (the tapped `https://kbr.com.np/auth/reset-password?token=...` link) is
/// discarded and the one-time worker token is lost. The `app_links` plugin
/// can still see that URI — this service captures it before the router
/// boots and hands it to the splash, which SILENTLY validates the token
/// first and then routes per the matrix below.
///
/// ROUTING MATRIX (v1.0.87+):
///   valid + logged out, cold → splash → `/auth/reset-password?token=…`
///     (existing path; the reset screen's back button goes to `/login`)
///   valid + logged in, cold → splash → home → AUTO-open
///     `/auth/reset-password?token=…` (stashed, pushed after home lands;
///     NO confirmation popup)
///   valid + logged in, warm (app already open, link on the app_links
///     stream) → directly navigate to `/auth/reset-password?token=…`
///   invalid/expired + logged out → splash → `/login`, THEN the
///     AppModalShell popup (after /login lands — never over the splash)
///   invalid/expired + logged in → splash → `/home`, THEN the same popup
///     (after home lands — never over the splash)
///   validation network failure + logged out → still open the reset page
///     (the submit call surfaces the real error)
///   validation network failure + logged in → stay on home, no auto-open
///
/// Deliberate scoping (do NOT widen):
/// - Only the EXACT path `/auth/reset-password` on kbr.com.np /
///   www.kbr.com.np is intercepted, and only with a non-empty `token`.
/// - Plain-domain links (`https://kbr.com.np`, no path — the share-link
///   case) keep the existing behavior: boot to `/splash`, no forced
///   navigation; recents resume as-is.
/// - `/auth/reset-password` has NO login guard in the router (only a
///   missing-token redirect), so logged-in users can open it too.
class ResetLinkService {
  ResetLinkService._();

  static const _resetPath = '/auth/reset-password';
  static const _allowedHosts = {'kbr.com.np', 'www.kbr.com.np'};

  /// Deep-link paths this app handles. ONLY registered paths deep-link —
  /// everything else (contact pages, marketing URLs, unknown paths) is
  /// ignored: the app boots normally to `/splash` (via the router's
  /// initialLocation + overridePlatformDefaultLocation) where the splash
  /// runs its normal login check. Register a new link type here AND in
  /// the Android intent-filter / iOS AASA paths.
  static const kHandledDeepLinkPaths = {'/auth/reset-password'};

  /// Logs when a kbr.com.np link with an unhandled path is discarded, so
  /// "the app opened but ignored my link" is visible in logs instead of
  /// silent.
  static void _logDiscardedLink(Uri? uri) {
    if (uri == null) return;
    if (!_allowedHosts.contains(uri.host.toLowerCase())) return;
    if (kHandledDeepLinkPaths.contains(uri.path)) return;
    debugPrint('[DeepLink] discarded unhandled kbr.com.np path: '
        '${uri.path} — normal launch (splash login check)');
  }

  /// Cold-start stash: the token from the tapped link, consumed once by
  /// the splash.
  static String? _pendingToken;

  /// Warm-start dedupe: the last token already handed to the router, so a
  /// stream re-emit of the same link (e.g. the cold-start race) is a no-op.
  static String? _lastWarmToken;

  /// Installed by main.dart. Async: the warm callback validates the token
  /// before navigating (see [handleWarmToken]). Kept as a callback
  /// (instead of importing the router here) because app_router.dart
  /// transitively imports the splash, which imports this service — a
  /// direct import would be a cycle.
  static Future<void> Function(String location)? onWarmResetLink;

  /// Builds the in-app location for a verified token.
  static String locationFor(String token) =>
      '$_resetPath?token=${Uri.encodeComponent(token)}';

  /// True only for a genuine reset link: allowed host + exact reset path +
  /// non-empty token. Everything else (share links, plain domain, other
  /// paths, foreign hosts) keeps today's behavior.
  static bool isResetLink(Uri? uri) {
    if (uri == null) return false;
    if (!_allowedHosts.contains(uri.host.toLowerCase())) return false;
    if (uri.path != _resetPath) return false;
    final token = uri.queryParameters['token'];
    return token != null && token.isNotEmpty;
  }

  /// Filters a platform URI into the cold-start stash. Split out from
  /// [captureInitialLink] so tests can feed URIs without the platform
  /// channel.
  static void handleInitialUri(Uri? uri) {
    if (!isResetLink(uri)) {
      _logDiscardedLink(uri);
      return;
    }
    _pendingToken = uri!.queryParameters['token'];
  }

  /// Captures the cold-start App Link before the router boots. Best-effort:
  /// never throws, never blocks startup on failure.
  static Future<void> captureInitialLink() async {
    try {
      handleInitialUri(await AppLinks().getInitialLink());
    } catch (_) {
      // No link, or the plugin is unavailable — normal cold start.
    }
  }

  /// Returns the stashed cold-start token and clears the stash
  /// (consume-once). Returns null when there is none — the splash then
  /// continues its normal flow. Also marks the token handled for the
  /// warm-start dedupe below.
  static String? consumePendingToken() {
    final token = _pendingToken;
    _pendingToken = null;
    if (token == null || token.isEmpty) return null;
    _lastWarmToken = token; // a stream re-emit of the same link is a no-op
    return token;
  }

  /// Pure routing decision for a tapped reset link, given the login state
  /// and the (silent) token validation. Unit-tested exhaustively — the
  /// splash and the warm handler are thin shells over this.
  static ResetLinkDisposition decideDisposition({
    required bool loggedIn,
    required TokenValidationResult validation,
  }) {
    switch (validation) {
      case TokenValidationResult.valid:
        return ResetLinkDisposition.openReset;
      case TokenValidationResult.invalid:
      case TokenValidationResult.expired:
        return loggedIn
            ? ResetLinkDisposition.invalidLoggedIn
            : ResetLinkDisposition.invalidLoggedOut;
      case TokenValidationResult.networkError:
        return loggedIn
            ? ResetLinkDisposition.networkLoggedIn
            : ResetLinkDisposition.networkLoggedOut;
    }
  }

  /// Cold-start handling with all effects injected (the splash passes the
  /// real navigation; tests pass fakes). [validate] is
  /// [PasswordResetService.validateToken] in production. Returns the
  /// disposition so the splash knows whether navigation already happened:
  /// [go] is invoked for the terminal dispositions
  /// ([ResetLinkDisposition.openReset] when logged out,
  /// [ResetLinkDisposition.invalidLoggedOut],
  /// [ResetLinkDisposition.networkLoggedOut]); [stashAutoOpen] for
  /// [ResetLinkDisposition.openReset] when logged in (the splash routes
  /// home normally and pushes the stashed location after home lands).
  ///
  /// POPUP TIMING (v1.0.88+): this method NEVER shows the invalid-link
  /// popup itself. For the invalid/expired dispositions it navigates (or
  /// lets the splash continue its normal routing) FIRST, and the caller
  /// shows the popup AFTER the destination route lands — see
  /// [needsInvalidPopup] and the splash's post-frame popup. Showing it
  /// here would put the popup over the splash (the v1.0.87 bug).
  static Future<ResetLinkDisposition> handleColdToken(
    String token, {
    required bool loggedIn,
    required Future<TokenValidationResult> Function(String) validate,
    required void Function(String location) go,
    required void Function(String location) stashAutoOpen,
  }) async {
    final validation = await validate(token);
    final disposition =
        decideDisposition(loggedIn: loggedIn, validation: validation);
    switch (disposition) {
      case ResetLinkDisposition.openReset:
        if (loggedIn) {
          stashAutoOpen(locationFor(token));
        } else {
          go(locationFor(token));
        }
      case ResetLinkDisposition.invalidLoggedOut:
        // Navigate FIRST; the splash shows the popup after /login lands.
        go('/login');
      case ResetLinkDisposition.invalidLoggedIn:
        // The splash continues its normal routing below (lands on /home)
        // and shows the popup after home lands.
        break;
      case ResetLinkDisposition.networkLoggedOut:
        // Validation unreachable — still open the form; the submit call
        // surfaces the real error.
        go(locationFor(token));
      case ResetLinkDisposition.networkLoggedIn:
        // Stay on home: no auto-open, no popup.
        break;
    }
    return disposition;
  }

  /// True when the disposition owes the user the invalid/expired-link
  /// popup. The popup must be shown AFTER the destination route has landed
  /// (post-frame), never over the splash — the splash owns the timing.
  static bool needsInvalidPopup(ResetLinkDisposition disposition) =>
      disposition == ResetLinkDisposition.invalidLoggedOut ||
      disposition == ResetLinkDisposition.invalidLoggedIn;

  /// Warm-start handling with all effects injected (main.dart passes the
  /// real router + popup; tests pass fakes).
  static Future<void> handleWarmToken(
    String token, {
    required bool loggedIn,
    required Future<TokenValidationResult> Function(String) validate,
    required void Function(String location) navigate,
    required Future<void> Function() showInvalidPopup,
  }) async {
    final validation = await validate(token);
    final disposition =
        decideDisposition(loggedIn: loggedIn, validation: validation);
    switch (disposition) {
      case ResetLinkDisposition.openReset:
      case ResetLinkDisposition.networkLoggedOut:
        navigate(locationFor(token));
      case ResetLinkDisposition.invalidLoggedOut:
        navigate('/login');
        await showInvalidPopup();
      case ResetLinkDisposition.invalidLoggedIn:
        await showInvalidPopup();
      case ResetLinkDisposition.networkLoggedIn:
        // Stay wherever the user is: no navigation, no popup.
        break;
    }
  }

  /// The invalid/expired-link popup (AppModalShell, never a raw dialog).
  /// Exact copy, EN + NE.
  static Future<void> showInvalidLinkPopup(BuildContext context) {
    return AppModalShell.show<void>(
      context: context,
      builder: (modalContext) => AppModalShell(
        accent: const Color(0xFFDC2626),
        accentMid: const Color(0xFFEF4444),
        accentLight: const Color(0xFFFECACA),
        tagColor: const Color(0xFFDC2626),
        tagLabel: AppLanguage.tr('RESET LINK', 'रिसेट लिङ्क'),
        onClose: () => Navigator.of(modalContext).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFDC2626),
          ),
          child: const Icon(Icons.link_off_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Password Reset', 'पासवर्ड रिसेट'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          AppLanguage.tr(
            'This link has already been used or has expired. Please request a new one.',
            'यो लिङ्क प्रयोग भइसक्यो वा म्याद सकियो। नयाँ लिङ्क अनुरोध गर्नुहोस्।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: PopupActionButton(
          label: AppLanguage.tr('OK', 'ठीक छ'),
          backgroundColor: const Color(0xFF1D4ED8),
          onTap: () => Navigator.of(modalContext).pop(),
        ),
      ),
    );
  }

  /// Warm start: the app is already running (in recents) and a link arrives
  /// on the app_links stream. main.dart's [onWarmResetLink] callback owns
  /// the splashHasRouted guard, the silent validation and the actual
  /// navigation.
  static void handleIncomingUri(Uri? uri) {
    if (!isResetLink(uri)) {
      _logDiscardedLink(uri);
      return;
    }
    final token = uri!.queryParameters['token']!;
    if (token == _lastWarmToken) return;
    _lastWarmToken = token;
    // Fire-and-forget: the callback validates the token asynchronously and
    // navigates (or shows the invalid-link popup) when it resolves.
    onWarmResetLink?.call(locationFor(token));
  }

  /// Test seam: clears the stash, the dedupe state and the warm callback.
  static void resetForTest() {
    _pendingToken = null;
    _lastWarmToken = null;
    onWarmResetLink = null;
  }
}

/// Where a tapped reset link goes after its token is silently validated.
enum ResetLinkDisposition {
  /// The token is live — open the reset form.
  openReset,

  /// Invalid/expired token + logged out — `/login` + the invalid-link popup.
  invalidLoggedOut,

  /// Invalid/expired token + logged in — `/home` + the invalid-link popup.
  invalidLoggedIn,

  /// Validation unreachable + logged out — still open the reset form (the
  /// submit call surfaces the real error).
  networkLoggedOut,

  /// Validation unreachable + logged in — stay on home, no auto-open.
  networkLoggedIn,
}
