import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stagger_entrance.dart';
import '../../widgets/subpage_header.dart';

/// Profile → App Settings → Security Settings.
///
/// The signed-in user's email at the top (read-only), then two entries:
/// "Change Password" → `/settings/change-password` and "Login Devices" →
/// `/settings/login-devices`. Premium treatment: the shared gradient
/// subpage header, staggered card entrances, gradient icon tiles and soft
/// shadows — the same visual language as the analytics pages.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final email = AuthService.currentUser?.email ?? '';
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
                title:
                    AppLanguage.tr('Security Settings', 'सुरक्षा सेटिङहरू')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  StaggerEntrance(
                    delayMs: 0,
                    child: _AccountCard(email: email),
                  ),
                  const SizedBox(height: 12),
                  StaggerEntrance(
                    delayMs: 80,
                    child: _Entry(
                      icon: Icons.lock_outline,
                      gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      label: AppLanguage.tr(
                          'Change Password', 'पासवर्ड परिवर्तन'),
                      subtitle: AppLanguage.tr('Update your sign-in password',
                          'आफ्नो साइन-इन पासवर्ड अद्यावधिक गर्नुहोस्'),
                      onTap: () => context.push('/settings/change-password'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StaggerEntrance(
                    delayMs: 160,
                    child: _Entry(
                      icon: Icons.devices_outlined,
                      gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
                      label: AppLanguage.tr(
                          'Login Devices', 'लगइन डिभाइसहरू'),
                      subtitle: AppLanguage.tr(
                          'Phones signed in to your account',
                          'तपाईंको खातामा साइन इन भएका फोनहरू'),
                      onTap: () => context.push('/settings/login-devices'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StaggerEntrance(
                    delayMs: 240,
                    child: _TipCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only account email card — gradient mail tile, the address, and a
/// lock badge marking it non-editable.
class _AccountCard extends StatelessWidget {
  final String email;

  const _AccountCard({required this.email});

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
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
            child: const Icon(Icons.mail_outline,
                size: 24, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr('Account Email', 'खाता इमेल'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.isEmpty
                      ? AppLanguage.tr('Not signed in', 'साइन इन हुनुहुन्न')
                      : email,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.primary.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.lock_outline,
                size: 17, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Entry({
    required this.icon,
    required this.gradient,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.primary.withValues(alpha: 0.08),
                ),
                child: Icon(Icons.chevron_right,
                    size: 20, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small safety tip footer — shield tile + one line of advice.
class _TipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D4ED8).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
              ),
            ),
            child: const Icon(Icons.shield_outlined,
                size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr('Stay protected', 'सुरक्षित रहनुहोस्'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppLanguage.tr(
                    'Use a strong, unique password and never share it with anyone.',
                    'बलियो र अद्वितीय पासवर्ड प्रयोग गर्नुहोस् र कसैसँग पनि साझा नगर्नुहोस्।',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
