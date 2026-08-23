// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation — triggers the browser's native download for a URL
/// (e.g. one already carrying a Content-Disposition: attachment header),
/// via a hidden, auto-clicked anchor. No bytes are fetched or buffered here;
/// the browser handles the request itself.
void triggerDownload(String url, String filename) {
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = filename;
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
}
