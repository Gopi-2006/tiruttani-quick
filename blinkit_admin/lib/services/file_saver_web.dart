// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'file_saver.dart';

class WebFileSaver implements FileSaver {
  @override
  Future<String> saveFile(List<int> bytes, String filename) async {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    // ignore: cascade_invocations
    html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);
    return filename; // For web, just downloading counts as saved to user-designated place
  }
}

FileSaver getFileSaver() => WebFileSaver();
