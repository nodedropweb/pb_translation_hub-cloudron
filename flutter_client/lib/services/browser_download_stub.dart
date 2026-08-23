/// Non-web stub — no-op. This app's admin export flow targets Flutter Web
/// only (see api_client.dart's baseUrl resolution), so there's no native
/// download mechanism wired up for other platforms here.
void triggerDownload(String url, String filename) {}
