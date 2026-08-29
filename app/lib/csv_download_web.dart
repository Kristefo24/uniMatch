// Web implementation: hand the browser a real file to save, via a Blob +
// a throwaway anchor element with the `download` attribute — the standard
// way to trigger a file save from Flutter web without any extra package.
import 'dart:html' as html;

void downloadCsv(String filename, String csvContent) {
  final blob = html.Blob([csvContent], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
