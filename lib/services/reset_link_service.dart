import 'package:app_links/app_links.dart';

/// Cold-start / warm-start hand-off for password-reset App Links.
///
/// Problem: [appRouter] sets `overridePlatformDefaultLocation: true` and
/// boots every cold start at `/splash`, so the platform's initial-route URI
/// (the tapped `https://kbr.com.np/auth/reset-password?token=...` link) is
/// discarded and the one-time worker token is lost. The `app_links` plugin
/// can still see that URI — this service captures it before the router
/// boots and hands it to the splash, which routes straight to the reset
/// form.
///
/// Deliberate scoping (do NOT widen):
/// - Only the EXACT path `/auth/reset-password` on kbr.com.np /
///   www.kbr.com.np is intercepted, and only with a non-empty `token`.
/// - Plain-domain links (`https://kbr.com.np`, no path — the share-link
///   case) keep the existing behavior: boot to `/splash`, no forced
///   navigation; recents resume as-is.
class ResetLinkService {
  ResetLinkService._();

  static const _resetPath = '/auth/reset-password';
  static const _allowedHosts = {'kbr.com.np', 'www.kbr.com.np'};

  /// Cold-start stash: the token from the tapped link, consumed once by
  /// the splash.
  static String? _pendingToken;

  /// Warm-start dedupe: the last token already handed to the router, so a
  /// stream re-emit of the same link (e.g. the cold-start race) is a no-op.
  static String? _lastWarmToken;

  /// Installed by main.dart. Kept as a callback (instead of importing the
  /// router here) because app_router.dart transitively imports the splash,
  /// which imports this service — a direct import would be a cycle.
  static void Function(String location)? onWarmResetLink;

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
    if (!isResetLink(uri)) return;
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

  /// Returns the reset location for a stashed cold-start link and clears the
  /// stash (consume-once). Returns null when there is none — the splash then
  /// continues its normal flow.
  static String? consumePendingResetLocation() {
    final token = _pendingToken;
    _pendingToken = null;
    if (token == null || token.isEmpty) return null;
    _lastWarmToken = token; // a stream re-emit of the same link is a no-op
    return locationFor(token);
  }

  /// Warm start: the app is already running (in recents) and a link arrives
  /// on the app_links stream. main.dart's [onWarmResetLink] callback owns
  /// the splashHasRouted guard and the actual navigation.
  static void handleIncomingUri(Uri? uri) {
    if (!isResetLink(uri)) return;
    final token = uri!.queryParameters['token']!;
    if (token == _lastWarmToken) return;
    _lastWarmToken = token;
    onWarmResetLink?.call(locationFor(token));
  }

  /// Test seam: clears the stash, the dedupe state and the warm callback.
  static void resetForTest() {
    _pendingToken = null;
    _lastWarmToken = null;
    onWarmResetLink = null;
  }
}
