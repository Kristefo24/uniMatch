// Web implementation: hand the browser a real file to save, via a Blob +
// a throwaway anchor element with the `download` attribute — the standard
// way to trigger a file save from Flutter web without any extra package.
import 'dart:html' as html;
import 'dart:typed_data';

void downloadCsv(String filename, String csvContent) {
  final blob = html.Blob([csvContent], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

// Same mechanism as downloadCsv, for a binary payload (e.g. the admin
// applicants .xlsx) with a caller-supplied MIME type.
void downloadBytes(String filename, Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
