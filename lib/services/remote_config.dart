import 'auth_service.dart';
import 'firestore_rest.dart';

/// Remote-configurable fields — mirrors src/core/config/remoteConfig.ts.
/// Fetched from Firestore at app start (splash); local defaults are the
/// fallback if the fetch fails.
class RemoteConfig {
  final bool maintenanceMode;
  final String maintenanceMessage;

  const RemoteConfig({
    this.maintenanceMode = false,
    this.maintenanceMessage = '',
  });
}

Future<RemoteConfig> fetchRemoteConfig() async {
  try {
    final idToken = await AuthService.getValidIdToken();
    final data = await FirestoreRest.getDocument('meta/appConfig', idToken: idToken);
    if (data == null) return const RemoteConfig();
    return RemoteConfig(
      maintenanceMode: data['maintenanceMode'] as bool? ?? false,
      maintenanceMessage: data['maintenanceMessage'] as String? ?? '',
    );
  } catch (_) {
    return const RemoteConfig();
  }
}
