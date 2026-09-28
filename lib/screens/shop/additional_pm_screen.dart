// PM feature home — mirrors app/additional-features/pm.tsx, which renders
// AdditionalFeatureScreen with featureId 'pm' (hero icon: business).
import 'package:flutter/material.dart';
import 'additional_feature_home.dart';

class AdditionalPmScreen extends StatelessWidget {
  const AdditionalPmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdditionalFeatureHomeScreen(
      featureId: 'pm',
      heroIcon: Icons.business,
      reactSubtitle: 'Project Management',
    );
  }
}
