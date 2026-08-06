import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'file_saver.dart';

class IoFileSaver implements FileSaver {
  @override
  Future<String> saveFile(List<int> bytes, String filename) async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }
    } else if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      // Desktop (Windows/macOS/Linux)
      directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    }

    if (directory == null) {
      throw FileSystemException('Could not access storage directory.');
    }

    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }
}

FileSaver getFileSaver() => IoFileSaver();
