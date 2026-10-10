import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Profile → App Settings → Security Settings.
///
/// The signed-in user's email at the top (read-only), then two entries:
/// "Change Password" → `/settings/change-password` and "Login Devices" →
/// `/settings/login-devices`. Follows the settings-screen styling (gradient
/// subpage header, theme-aware cards).
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
                padding: const EdgeInsets.all(16),
                children: [
                  // Read-only account email.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: palette.primary.withValues(alpha: 0.1),
                          ),
                          child: Icon(Icons.mail_outline,
                              size: 22, color: palette.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr('Account Email', 'खाता इमेल'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email.isEmpty
                                    ? AppLanguage.tr(
                                        'Not signed in', 'साइन इन हुनुहुन्न')
                                    : email,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.lock_outline,
                            size: 18, color: palette.textDisabled),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Entry(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFF1D4ED8),
                    label: AppLanguage.tr(
                        'Change Password', 'पासवर्ड परिवर्तन'),
                    subtitle: AppLanguage.tr('Update your sign-in password',
                        'आफ्नो साइन-इन पासवर्ड अद्यावधिक गर्नुहोस्'),
                    onTap: () => context.push('/settings/change-password'),
                  ),
                  const SizedBox(height: 12),
                  _Entry(
                    icon: Icons.devices_outlined,
                    iconColor: const Color(0xFF16A34A),
                    label: AppLanguage.tr(
                        'Login Devices', 'लगइन डिभाइसहरू'),
                    subtitle: AppLanguage.tr(
                        'Phones signed in to your account',
                        'तपाईंको खातामा साइन इन भएका फोनहरू'),
                    onTap: () => context.push('/settings/login-devices'),
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

class _Entry extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Entry({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: iconColor.withValues(alpha: 0.1),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 22, color: palette.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
