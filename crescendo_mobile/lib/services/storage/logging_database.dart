import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Wraps a Database to trace queries during debugging.
class LoggingDatabase implements Database {
  final Database _delegate;
  
  static int _logCount = 0;
  static const int _maxDetailedLogs = 10;
  static final DateTime _startTime = DateTime.now();

  LoggingDatabase(this._delegate) {
    debugPrint('[DB_TRACE] LoggingDatabase initialized at ${_formatDuration(DateTime.now().difference(_startTime))}');
  }

  String _formatDuration(Duration d) {
    return '${d.inMilliseconds}ms';
  }

  void _log(String operation, String sql, [List<Object?>? arguments]) {
    final now = DateTime.now();
    final elapsed = now.difference(_startTime);
    final count = ++_logCount;
    
    if (!kDebugMode) return;
    
    // Clean up SQL log for null where
    final safeSql = sql.replaceAll('WHERE null', '');

    if (count <= _maxDetailedLogs) {
      debugPrint('[DB_TRACE] #$count [${_formatDuration(elapsed)}] $operation: $safeSql');
      if (arguments != null && arguments.isNotEmpty) {
        debugPrint('[DB_TRACE]   Args: $arguments');
      }
      // Stack trace to find caller (skipping LoggingDatabase frames)
      final trace = StackTrace.current.toString().split('\n').take(10).skip(2).join('\n');
      debugPrint('[DB_TRACE]   Trace: \n$trace');
    } else {
      // Rate limit logs
       if (count % 10 == 0) { // Log every 10th query after the first 10
         debugPrint('[DB_TRACE] #$count [${_formatDuration(elapsed)}] $operation: $sql');
       }
    }
  }

  @override
  Batch batch() => _delegate.batch();

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    _log('DELETE', 'DELETE FROM $table WHERE $where', whereArgs);
    return _delegate.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    _log('EXECUTE', sql, arguments);
    return _delegate.execute(sql, arguments);
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    _log('INSERT', 'INSERT INTO $table (${values.keys.join(",")})', values.values.toList());
    return _delegate.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    _log('QUERY', 'SELECT ${columns?.join(",") ?? "*"} FROM $table WHERE $where', whereArgs);
    return _delegate.query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs, groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    _log('RAW_DELETE', sql, arguments);
    return _delegate.rawDelete(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    _log('RAW_INSERT', sql, arguments);
    return _delegate.rawInsert(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    _log('RAW_QUERY', sql, arguments);
    return _delegate.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    _log('RAW_UPDATE', sql, arguments);
    return _delegate.rawUpdate(sql, arguments);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
     _log('TRANSACTION', 'BEGIN');
    return _delegate.transaction((txn) async {
       // Ideally we would wrap txn too, but for now just logging the start is helpful
       return action(txn);
    }, exclusive: exclusive);
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    _log('UPDATE', 'UPDATE $table SET ... WHERE $where', whereArgs);
    return _delegate.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  String get path => _delegate.path;

  @override
  Future<int> getVersion() => _delegate.getVersion();

  @override
  Future<void> setVersion(int version) => _delegate.setVersion(version);
  
  // Implementation of other Database methods if needed by version updates
  // For older sqflite versions, devInvoke might be needed or not present
  @override
  Future<T> devInvokeMethod<T>(String method, [dynamic arguments]) {
      return _delegate.devInvokeMethod(method, arguments);
  }
  
  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) async {
    _log('READ_TRANSACTION', 'BEGIN');
    return _delegate.readTransaction(action);
  }

  @override
  Database get database => this;

  @override
  Future<QueryCursor> queryCursor(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset, int? bufferSize}) async {
    _log('QUERY_CURSOR', 'SELECT ... FROM $table ...', whereArgs);
    return _delegate.queryCursor(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs, groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset, bufferSize: bufferSize);
  }

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) async {
    _log('RAW_QUERY_CURSOR', sql, arguments);
    return _delegate.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
  }

  @override
  Future<T> devInvokeSqlMethod<T>(String method, String sql, [List<Object?>? arguments]) {
    return _delegate.devInvokeSqlMethod(method, sql, arguments);
  }
}
