
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> getPath() async {
  String? dir;
  if (Platform.isAndroid) {
    List<Directory>? cacheDirs = await getExternalCacheDirectories();
    if (cacheDirs != null && cacheDirs.isNotEmpty) {
      dir = cacheDirs[0].path;
    }
  }
  dir ??= (await getApplicationDocumentsDirectory()).path;
  return dir;
}
