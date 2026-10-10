import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/device_session_service.dart';
import '../../services/firestore_rest.dart';
import '../../theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/stagger_entrance.dart';
import '../../widgets/subpage_header.dart';

/// Security Settings → Login Devices.
///
/// Lists the `users/{uid}/push_tokens` documents (one per device, keyed by
/// the stable device id). The row whose `deviceId` matches this device's id
/// (see [DeviceSessionService.getDeviceId]) wears a green blinking dot and
/// a "This device" tag. Each row shows the device model (or "Unknown
/// device"), the platform icon, the app version and the last-active time
/// from `updatedAt`.
///
/// Premium treatment: the shared gradient subpage header, a device-count
/// summary card, staggered row entrances, gradient platform icon tiles and
/// soft shadows.
class LoginDevicesScreen extends StatefulWidget {
  const LoginDevicesScreen({
    super.key,
    this.debugUid,
    this.loadDevices,
    this.currentDeviceIdForTest,
  });

  /// Test seam: list for this uid instead of the signed-in user.
  final String? debugUid;

  /// Test seam: replaces the `users/{uid}/push_tokens` list read.
  final Future<List<Map<String, dynamic>>> Function(String uid)? loadDevices;

  /// Test seam: pins "this device" instead of reading the real device id.
  final String? currentDeviceIdForTest;

  @override
  State<LoginDevicesScreen> createState() => _LoginDevicesScreenState();
}

class _DeviceRow {
  final Map<String, dynamic> doc;
  final bool isCurrent;
  _DeviceRow(this.doc, this.isCurrent);
}

class _LoginDevicesScreenState extends State<LoginDevicesScreen> {
  late Future<List<_DeviceRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_DeviceRow>> _load() async {
    final uid = widget.debugUid ?? AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) return [];
    final docs = await (widget.loadDevices?.call(uid) ?? _fetchDevices(uid));
    final currentId = widget.currentDeviceIdForTest ??
        await DeviceSessionService.getDeviceId().catchError((_) => '');
    final rows = docs
        .map((d) => _DeviceRow(
            d, '${d['deviceId'] ?? ''}' == currentId && currentId.isNotEmpty))
        .toList();
    rows.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      final at = _updatedAt(b.doc).millisecondsSinceEpoch;
      final bt = _updatedAt(a.doc).millisecondsSinceEpoch;
      return at.compareTo(bt);
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> _fetchDevices(String uid) async {
    final idToken = await AuthService.getValidIdToken().catchError((_) => '');
    return FirestoreRest.listDocuments('users/$uid/push_tokens',
        idToken: idToken);
  }

  static DateTime _updatedAt(Map<String, dynamic> doc) {
    final raw = doc['updatedAt'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _nepaliDigits(String s) =>
      s.replaceAllMapped(RegExp(r'[0-9]'), (m) {
        const digits = '०१२३४५६७८९';
        return digits[int.parse(m.group(0)!)];
      });

  String _relativeTime(DateTime t) {
    if (t.millisecondsSinceEpoch == 0) {
      return AppLanguage.tr('Unknown', 'अज्ञात');
    }
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return AppLanguage.tr('Just now', 'भर्खरै');
    if (d.inHours < 1) {
      final m = '${d.inMinutes}';
      return AppLanguage.tr('$m min ago', '${_nepaliDigits(m)} मिनेट अघि');
    }
    if (d.inDays < 1) {
      final h = '${d.inHours}';
      return AppLanguage.tr('$h hr ago', '${_nepaliDigits(h)} घण्टा अघि');
    }
    final days = '${d.inDays}';
    return AppLanguage.tr('$days days ago', '${_nepaliDigits(days)} दिन अघि');
  }

  /// Device-count summary card shown above the list.
  Widget _countCard(BuildContext context, int count) {
    final palette = ExpoPalette.of(context);
    final countText = AppLanguage.isNepali ? _nepaliDigits('$count') : '$count';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.devices_outlined,
                size: 24, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countText,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLanguage.tr(
                      'devices signed in', 'वटा डिभाइसमा साइन इन'),
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLanguage.tr('Active', 'सक्रिय'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _DeviceRow row) {
    final palette = ExpoPalette.of(context);
    final doc = row.doc;
    final platform = '${doc['platform'] ?? ''}'.toLowerCase();
    final model = '${doc['deviceModel'] ?? ''}'.trim();
    final appVersion = '${doc['appVersion'] ?? ''}'.trim();
    final isIos = platform == 'ios';
    final iconData = isIos ? Icons.phone_iphone : Icons.android;
    final subtitle = [
      if (appVersion.isNotEmpty) 'v$appVersion',
      _relativeTime(_updatedAt(doc)),
    ].join(' • ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: row.isCurrent
              ? const Color(0xFF16A34A).withValues(alpha: 0.5)
              : palette.border,
          width: row.isCurrent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isIos
                    ? const [Color(0xFF475569), Color(0xFF0F172A)]
                    : const [Color(0xFF4ADE80), Color(0xFF16A34A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: (isIos
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF16A34A))
                      .withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(iconData, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.isEmpty
                            ? AppLanguage.tr(
                                'Unknown device', 'अज्ञात डिभाइस')
                            : model,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (row.isCurrent) ...[
                      const SizedBox(width: 6),
                      const _BlinkingDot(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
                if (row.isCurrent) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF16A34A)
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      AppLanguage.tr('This device', 'यो डिभाइस'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.primary.withValues(alpha: 0.25),
                    palette.primary.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: Icon(Icons.devices_outlined,
                  size: 38, color: palette.primary),
            ),
            const SizedBox(height: 16),
            Text(
              AppLanguage.tr('No devices found', 'कुनै डिभाइस फेला परेन'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLanguage.tr(
                'Devices you sign in on will appear here.',
                'तपाईंले साइन इन गर्ने डिभाइसहरू यहाँ देखिनेछन्।',
              ),
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: Column(
          children: [
            SubpageHeader(
                title: AppLanguage.tr('Login Devices', 'लगइन डिभाइसहरू')),
            Expanded(
              child: FutureBuilder<List<_DeviceRow>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: PreloadingWidget(
                        tinted: true,
                        label: AppLanguage.tr(
                            'Loading devices...', 'डिभाइसहरू लोड हुँदैछ...'),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLanguage.tr(
                                'Could not load devices. Please try again.',
                                'डिभाइसहरू लोड गर्न सकिएन। कृपया पुनः प्रयास गर्नुहोस्।',
                              ),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: palette.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () =>
                                  setState(() => _future = _load()),
                              child: Text(AppLanguage.tr(
                                  'Retry', 'पुनः प्रयास गर्नुहोस्')),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final rows = snap.data ?? [];
                  if (rows.isEmpty) {
                    return StaggerEntrance(
                      delayMs: 0,
                      child: _empty(context),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: StaggerEntrance(
                            delayMs: 0,
                            child: _countCard(context, rows.length),
                          ),
                        );
                      }
                      final row = rows[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        // Capped stagger like the analytics lists.
                        child: StaggerEntrance(
                          delayMs: (i > 8 ? 8 : i) * 60,
                          child: _row(context, row),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green "this device" dot — gentle 900ms blink. A finite repeating
/// animation, so never pumpAndSettle while it is on screen (use small
/// pumps in tests).
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.25).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF16A34A),
        ),
      ),
    );
  }
}
