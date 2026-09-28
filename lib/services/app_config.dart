/// Backend config for the REST-based Firebase layer.
///
/// Same Firebase project as the Expo app — no backend changes needed.
/// Values are injected at build time with --dart-define, e.g.:
///   flutter build apk --dart-define=FIREBASE_API_KEY=xxx
/// In CI they come from GitHub Actions secrets (see .github/workflows).
class AppConfig {
  static const firebaseApiKey =
      String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseAuthDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId/databases/(default)/documents';

  static String get identityToolkitBase =>
      'https://identitytoolkit.googleapis.com/v1';
}
