import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Maintenance blocking screen — shown when remote config enables it.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build, size: 64, color: Colors.white70),
                SizedBox(height: 24),
                Text(
                  'Under Maintenance',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Loksewa Solution is being updated. Please check back soon.',
                  style: TextStyle(color: Color(0xFFD7E3FF), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
