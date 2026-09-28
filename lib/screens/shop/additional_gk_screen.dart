// GK feature home — mirrors app/additional-features/gk.tsx, which renders
// AdditionalFeatureScreen with featureId 'gk' (hero icon: earth).
import 'package:flutter/material.dart';
import 'additional_feature_home.dart';

class AdditionalGkScreen extends StatelessWidget {
  const AdditionalGkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdditionalFeatureHomeScreen(
      featureId: 'gk',
      heroIcon: Icons.public,
      reactSubtitle: 'GK & Current Affairs',
    );
  }
}
