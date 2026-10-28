import 'cf_api.dart';

/// Remote-configurable fields — mirrors src/core/config/remoteConfig.ts.
/// Fetched from the Cloudflare API (GET /config → the meta/appConfig
/// object) at app start (splash); local defaults are the fallback if the
/// fetch fails.
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
    final data = await CfApi.getConfig();
    return RemoteConfig(
      // D1 rows may carry the flag as a 'true' string — coerce.
      maintenanceMode: CfJson.asBool(data['maintenanceMode']),
      maintenanceMessage: data['maintenanceMessage']?.toString() ?? '',
    );
  } catch (_) {
    return const RemoteConfig();
  }
}
