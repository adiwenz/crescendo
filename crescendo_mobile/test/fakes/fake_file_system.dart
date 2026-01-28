import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crescendo_mobile/core/interfaces/i_file_system.dart';

class FakeFileSystem implements IFileSystem {
  final Map<String, Uint8List> _files = {};
  
  // Helpers to seed data
  void seedFile(String path, Uint8List bytes) {
    _files[path] = bytes;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<bool> exists(String path) async {
    return _files.containsKey(path);
  }

  @override
  Future<int> fileSize(String path) async {
    return _files[path]?.length ?? 0;
  }

  @override
  Future<String> getApplicationDocumentsPath() async {
    return '/fake/documents';
  }

  @override
  Future<String> getTemporaryPath() async {
     return '/fake/temp';
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    if (!_files.containsKey(path)) throw FileSystemException('File not found', path);
    return _files[path]!;
  }

  @override
  Future<String> readAsString(String path) async {
     if (!_files.containsKey(path)) throw FileSystemException('File not found', path);
     return String.fromCharCodes(_files[path]!);
  }

  @override
  Future<void> rename(String source, String dest) async {
      if (!_files.containsKey(source)) throw FileSystemException('File not found', source);
      _files[dest] = _files[source]!;
      _files.remove(source);
  }

  @override
  Future<void> writeAsBytes(String path, List<int> bytes) async {
    _files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeAsString(String path, String content) async {
    _files[path] = Uint8List.fromList(content.codeUnits);
  }
  
  @override
  Directory get directory => Directory('/fake/root'); // Dummy
}
