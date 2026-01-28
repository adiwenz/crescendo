import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_mobile/services/storage/db.dart';

/// Bootstrap function to initialize test environment
/// 
/// This must be called once before running tests to:
/// - Initialize Flutter test bindings
/// - Set up sqflite FFI for desktop test environment
/// - Configure a temporary database path for tests
/// - Mock SharedPreferences for tests
/// 
/// Call this in setUpAll() at the top of your test files.
Future<void> bootstrapTests() async {
  // Initialize Flutter test bindings
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite FFI for desktop/VM tests
  // This is required because sqflite uses platform channels that don't work in VM tests
  sqfliteFfiInit();
  
  // Set the database factory to use FFI instead of platform channels
  databaseFactory = databaseFactoryFfi;
  
  // Create a temporary directory for test databases
  final tempDir = Directory('${Directory.systemTemp.path}/crescendo_mobile_tests');
  if (!tempDir.existsSync()) {
    tempDir.createSync(recursive: true);
  }
  
  // Set the databases path for sqflite to use our temp directory
  databaseFactoryFfi.setDatabasesPath(tempDir.path);
  
  // Mock SharedPreferences for tests
  // This prevents MissingPluginException when tests use SharedPreferences
  SharedPreferences.setMockInitialValues({});
}

/// Reset the test database to a clean state
/// 
/// This should be called in setUp() before each test to ensure:
/// - The database file is deleted
/// - The AppDatabase singleton is reset
/// - Each test starts with a fresh database
Future<void> resetTestDatabase() async {
  // Close and reset the AppDatabase singleton
  await AppDatabase.resetForTests();
  
  // Delete the database file
  final tempDir = Directory('${Directory.systemTemp.path}/crescendo_mobile_tests');
  final dbFile = File('${tempDir.path}/crescendo.db');
  
  if (dbFile.existsSync()) {
    await dbFile.delete();
  }
  
  // Also delete any journal files
  final journalFile = File('${tempDir.path}/crescendo.db-journal');
  if (journalFile.existsSync()) {
    await journalFile.delete();
  }
  
  final walFile = File('${tempDir.path}/crescendo.db-wal');
  if (walFile.existsSync()) {
    await walFile.delete();
  }
  
  final shmFile = File('${tempDir.path}/crescendo.db-shm');
  if (shmFile.existsSync()) {
    await shmFile.delete();
  }
}
