import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:crescendo_mobile/core/interfaces/i_file_system.dart';

class RealFileSystem implements IFileSystem {
  @override
  Directory get directory => Directory.current; // Not typically used in path_provider context

  @override
  Future<void> delete(String path) {
    return File(path).delete();
  }

  @override
  Future<bool> exists(String path) {
    return File(path).exists();
  }

  @override
  Future<int> fileSize(String path) async {
    return (await File(path).stat()).size;
  }

  @override
  Future<String> getApplicationDocumentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  @override
  Future<String> getTemporaryPath() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  @override
  Future<Uint8List> readAsBytes(String path) {
    return File(path).readAsBytes();
  }

  @override
  Future<String> readAsString(String path) {
    return File(path).readAsString();
  }

  @override
  Future<void> rename(String source, String dest) {
    return File(source).rename(dest);
  }

  @override
  Future<void> writeAsBytes(String path, List<int> bytes) {
    return File(path).writeAsBytes(bytes);
  }

  @override
  Future<void> writeAsString(String path, String content) {
    return File(path).writeAsString(content);
  }
}
