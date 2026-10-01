import 'dart:async';

import 'package:app_links/app_links.dart';

/// Thin wrapper over package:app_links for the App Links deep-link flow.
///
/// Two entry points, both guarded so routing code never has to handle
/// platform errors:
/// - [getInitialLink]: the link that cold-started the app (null when the app
///   wasn't opened via a link, or on any error).
/// - [warmLinks]: broadcast stream of links that arrive while the app is
///   already running (warm start).
///
/// [isSignupLink] recognizes the shared signup link
/// (https://www.kbr.com.np/signup) — the one URL the app routes on.
class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _links = AppLinks();

  static StreamSubscription<Uri>? _warmSub;
  static final StreamController<Uri> _warmController =
      StreamController<Uri>.broadcast();

  /// Cold-start link. Never throws — returns null on any error.
  static Future<Uri?> getInitialLink() async {
    try {
      return await _links.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  /// Warm-start links. Subscribes to the platform stream lazily on first
  /// access and re-emits on a broadcast controller; platform errors are
  /// swallowed so listeners never see them.
  static Stream<Uri> get warmLinks {
    if (_warmSub == null) {
      try {
        _warmSub = _links.uriLinkStream.listen(
          _warmController.add,
          onError: (_) {},
          cancelOnError: false,
        );
      } catch (_) {
        // Platform stream unavailable — listeners simply never get links.
      }
    }
    return _warmController.stream;
  }

  /// True when [link] is the shared signup App Link on one of our hosts.
  static bool isSignupLink(Uri? link) {
    if (link == null) return false;
    final host = link.host.toLowerCase();
    if (host != 'kbr.com.np' && host != 'www.kbr.com.np') return false;
    return link.path == '/signup' || link.path.startsWith('/signup');
  }
}
