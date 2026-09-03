// Non-web fallback: there's no browser to hand a file to, so this is a no-op.
// Real behavior lives in csv_download_web.dart, picked by main.dart's
// conditional import (dart.library.html) on the web build.
import 'dart:typed_data';

void downloadCsv(String filename, String csvContent) {}
void downloadBytes(String filename, Uint8List bytes, String mimeType) {}
