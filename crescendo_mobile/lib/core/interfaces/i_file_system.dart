import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

abstract class IFileSystem {
  Future<bool> exists(String path);
  Future<Uint8List> readAsBytes(String path);
  Future<String> readAsString(String path);
  Future<void> writeAsBytes(String path, List<int> bytes);
  Future<void> writeAsString(String path, String content);
  Future<void> delete(String path);
  Future<void> rename(String source, String dest);
  Future<int> fileSize(String path);
  Directory get directory; // For temp/doc dir access if needed, or helper methods
  Future<String> getApplicationDocumentsPath();
  Future<String> getTemporaryPath();
}
